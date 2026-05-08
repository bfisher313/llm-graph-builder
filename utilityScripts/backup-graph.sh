#!/bin/bash
# Neo4j Knowledge Graph Backup Script (Binary Dump)
# Creates a complete binary backup of a Neo4j database
# This is NON-DESTRUCTIVE and safe to run anytime

set -e  # Exit on error

# Configuration
DEFAULT_BACKUP_DIR="./backups"
DEFAULT_DATABASE="theblackbookofpower"
CONTAINER_NAME="neo4j-llm-graph-builder"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
DATABASE_NAME="$DEFAULT_DATABASE"
HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --database-name)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --help)
            HELP=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            HELP=true
            shift
            ;;
    esac
done

# Show help
if [ "$HELP" = true ]; then
    echo "Neo4j Knowledge Graph Backup Script"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --backup-dir DIR       Backup directory (default: $DEFAULT_BACKUP_DIR)"
    echo "  --database-name NAME   Database name (default: $DEFAULT_DATABASE)"
    echo "  --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use defaults"
    echo "  $0 --backup-dir ./my-backups         # Custom backup directory"
    echo "  $0 --database-name mygraph --backup-dir /backups  # Custom both"
    echo ""
    echo "Notes:"
    echo "  - This creates a binary backup (fast, complete, Enterprise only)"
    echo "  - Backup requires Neo4j container to be stopped temporarily"
    echo "  - Backup is non-destructive - source data is never modified"
    echo "  - Backup includes all nodes, relationships, properties, indexes, constraints"
    echo "  - ⚠️ Binary backups are VERSION-SPECIFIC - Neo4j version is included in backup name"
    exit 0
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Neo4j Knowledge Graph Backup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Validate container is running
echo -e "${YELLOW}Checking Neo4j container status...${NC}"
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${RED}❌ Error: Neo4j container '$CONTAINER_NAME' is not running${NC}"
    echo "Please start it with: docker compose up -d neo4j"
    exit 1
fi
echo -e "${GREEN}✓ Container is running${NC}"
echo ""

# Get Neo4j version for version tracking
echo -e "${YELLOW}Getting Neo4j version...${NC}"
NEO4J_VERSION=$(docker exec "$CONTAINER_NAME" neo4j --version 2>/dev/null | head -1 || echo 'unknown')
echo -e "  Version: ${BLUE}$NEO4J_VERSION${NC}"
echo ""

# Create backup directory with timestamp and Neo4j version
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
VERSION_TAG=$(echo "$NEO4J_VERSION" | sed 's/neo4j version //; s/[^0-9.].*//' | sed 's/\./-/g')
BACKUP_PATH="$BACKUP_DIR/binary-backup-${VERSION_TAG}-${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"

echo -e "${YELLOW}Backup configuration:${NC}"
echo -e "  Database: ${BLUE}$DATABASE_NAME${NC}"
echo -e "  Backup directory: ${BLUE}$BACKUP_PATH${NC}"
echo -e "  Container: ${BLUE}$CONTAINER_NAME${NC}"
echo ""

# Get initial statistics
echo -e "${YELLOW}Getting database statistics...${NC}"
NODE_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH (n) RETURN count(n) AS count" 2>/dev/null | tail -n 1 || echo "0")
REL_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH ()-[r]->() RETURN count(r) AS count" 2>/dev/null | tail -n 1 || echo "0")
echo -e "  Nodes: ${GREEN}$NODE_COUNT${NC}"
echo -e "  Relationships: ${GREEN}$REL_COUNT${NC}"
echo ""

# Determine the data volume/mount used by the container BEFORE stopping it
echo -e "${YELLOW}Identifying data storage...${NC}"
DATA_MOUNT=$(docker inspect "$CONTAINER_NAME" -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Type}}:{{.Source}}{{end}}{{end}}' 2>/dev/null | head -1)
DATA_TYPE=$(echo "$DATA_MOUNT" | cut -d: -f1)
DATA_SOURCE=$(echo "$DATA_MOUNT" | cut -d: -f2)

if [ -z "$DATA_MOUNT" ] || [ -z "$DATA_SOURCE" ]; then
    echo -e "${RED}❌ Error: Could not determine data mount for container '$CONTAINER_NAME'${NC}"
    exit 1
fi

echo -e "  Storage type: ${BLUE}$DATA_TYPE${NC}"
echo -e "  Source: ${BLUE}$DATA_SOURCE${NC}"
echo ""

# Stop container safely
echo -e "${YELLOW}Stopping Neo4j container for backup...${NC}"
docker stop "$CONTAINER_NAME"
echo -e "${GREEN}✓ Container stopped${NC}"
echo ""

# Create backup based on storage type
echo -e "${YELLOW}Creating binary backup...${NC}"

if [ "$DATA_TYPE" = "volume" ]; then
    # Named volume approach
    docker run --rm \
        -e NEO4J_ACCEPT_LICENSE_AGREEMENT=yes \
        -v "${DATA_SOURCE}:/data" \
        -v "${BACKUP_PATH}:/backups" \
        neo4j:5.26.0-enterprise \
        neo4j-admin database dump "$DATABASE_NAME" --to-path=/backups
elif [ "$DATA_TYPE" = "bind" ]; then
    # Bind mount approach - mount the actual directory
    docker run --rm \
        -e NEO4J_ACCEPT_LICENSE_AGREEMENT=yes \
        -v "${DATA_SOURCE}:/data" \
        -v "${BACKUP_PATH}:/backups" \
        neo4j:5.26.0-enterprise \
        neo4j-admin database dump "$DATABASE_NAME" --to-path=/backups
else
    echo -e "${RED}❌ Error: Unsupported storage type '$DATA_TYPE'${NC}"
    docker start "$CONTAINER_NAME"
    exit 1
fi

echo -e "${GREEN}✓ Backup created${NC}"
echo ""

# Create manifest
MANIFEST_FILE="$BACKUP_PATH/manifest.json"
echo -e "${YELLOW}Creating backup manifest...${NC}"
# Extract version number for compatibility checking
VERSION_NUMBER=$(echo "$NEO4J_VERSION" | sed 's/neo4j version //; s/[^0-9.].*//')
cat > "$MANIFEST_FILE" << EOF
{
    "backup_type": "binary",
    "database_name": "$DATABASE_NAME",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "timestamp_local": "$(date)",
    "node_count": ${NODE_COUNT:-0},
    "relationship_count": ${REL_COUNT:-0},
    "backup_path": "$BACKUP_PATH",
    "container_name": "$CONTAINER_NAME",
    "neo4j_version": "$NEO4J_VERSION",
    "neo4j_version_number": "$VERSION_NUMBER",
    "backup_compatibility": {
        "note": "Binary backups are version-specific. Restore to same or compatible Neo4j version.",
        "source_version": "$VERSION_NUMBER",
        "recommended_restore_versions": ["$VERSION_NUMBER"]
    }
}
EOF
echo -e "${GREEN}✓ Manifest created with version information${NC}"
echo ""

# Restart container
echo -e "${YELLOW}Restarting Neo4j container...${NC}"
docker start "$CONTAINER_NAME"

# Wait for container to be healthy
echo -e "${YELLOW}Waiting for Neo4j to be healthy...${NC}"
for i in {1..30}; do
    if docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder "RETURN 1" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Container is healthy${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${YELLOW}⚠ Warning: Container not fully healthy yet, but continuing${NC}"
    fi
    sleep 2
done
echo ""

# Get backup size
BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Backup completed successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Backup Summary:${NC}"
echo -e "  Location: ${BLUE}$BACKUP_PATH${NC}"
echo -e "  Size: ${BLUE}$BACKUP_SIZE${NC}"
echo -e "  Database: ${BLUE}$DATABASE_NAME${NC}"
echo -e "  Nodes backed up: ${GREEN}$NODE_COUNT${NC}"
echo -e "  Relationships backed up: ${GREEN}$REL_COUNT${NC}"
echo ""
echo -e "${YELLOW}To restore this backup, run:${NC}"
echo -e "  ${BLUE}./utilityScripts/restore-graph.sh --backup-dir $BACKUP_PATH --database-name $DATABASE_NAME${NC}"
echo ""
echo -e "${GREEN}Backup is safe and non-destructive. Original data is unchanged.${NC}"
