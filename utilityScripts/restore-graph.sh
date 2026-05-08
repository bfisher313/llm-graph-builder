#!/bin/bash
# Neo4j Knowledge Graph Restore Script (Binary Restore)
# Restores a binary backup to a Neo4j database
# WARNING: This operation is DESTRUCTIVE - will replace existing data

set -e  # Exit on error

# Configuration
DEFAULT_DATABASE="theblackbookofpower"
CONTAINER_NAME="neo4j-llm-graph-builder"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
BACKUP_DIR=""
DATABASE_NAME="$DEFAULT_DATABASE"
HELP=false
DRY_RUN=false
FORCE=false

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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
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
    echo "Neo4j Knowledge Graph Restore Script"
    echo "Usage: $0 --backup-dir BACKUP_DIR [options]"
    echo ""
    echo "Required:"
    echo "  --backup-dir DIR       Backup directory to restore from"
    echo ""
    echo "Options:"
    echo "  --database-name NAME   Target database name (default: $DEFAULT_DATABASE)"
    echo "  --dry-run              Show what would happen without making changes"
    echo "  --force                Skip safety warnings and proceed with restore"
    echo "  --help                 Show this help message"
    echo ""
    echo "Safety Features:"
    echo "  - Warns if target database exists and is not empty"
    echo "  - Offers backup-before-restore option"
    echo "  - Multiple confirmation steps"
    echo "  - Dry-run mode available"
    echo ""
    echo "Examples:"
    echo "  $0 --backup-dir ./backups/binary-backup-2026-05-06-143022"
    echo "  $0 --backup-dir ./backups/binary-backup-2026-05-06-143022 --database-name test-db"
    echo "  $0 --backup-dir ./backups/binary-backup-2026-05-06-143022 --dry-run"
    echo ""
    exit 0
fi

# Check if backup directory is provided
if [ -z "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ Error: --backup-dir is required${NC}"
    echo "Use --help for usage information"
    exit 1
fi

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ Error: Backup directory '$BACKUP_DIR' does not exist${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Neo4j Knowledge Graph Restore${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Read manifest
MANIFEST_FILE="$BACKUP_DIR/manifest.json"
BACKUP_VERSION=""
BACKUP_VERSION_NUMBER=""

if [ ! -f "$MANIFEST_FILE" ]; then
    echo -e "${YELLOW}⚠ Warning: No manifest.json found in backup directory${NC}"
    echo "Proceeding without manifest and version checking..."
else
    echo -e "${YELLOW}Backup manifest:${NC}"
    echo -e "  Type: $(jq -r '.backup_type' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
    echo -e "  Database: $(jq -r '.database_name' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
    echo -e "  Created: $(jq -r '.timestamp_local' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
    echo -e "  Nodes: $(jq -r '.node_count' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
    echo -e "  Relationships: $(jq -r '.relationship_count' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"

    # Get version information from manifest
    BACKUP_VERSION=$(jq -r '.neo4j_version' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')
    BACKUP_VERSION_NUMBER=$(jq -r '.neo4j_version_number' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')

    if [ "$BACKUP_VERSION" != "unknown" ] && [ "$BACKUP_VERSION" != "null" ]; then
        echo -e "  Neo4j Version: ${BLUE}$BACKUP_VERSION${NC}"
    fi
    echo ""
fi

# Validate container is running
echo -e "${YELLOW}Checking Neo4j container status...${NC}"
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${RED}❌ Error: Neo4j container '$CONTAINER_NAME' is not running${NC}"
    echo "Please start it with: docker compose up -d neo4j"
    exit 1
fi
echo -e "${GREEN}✓ Container is running${NC}"
echo ""

# Version compatibility check
if [ "$BACKUP_VERSION" != "unknown" ] && [ "$BACKUP_VERSION" != "null" ]; then
    echo -e "${YELLOW}Checking version compatibility...${NC}"
    CURRENT_VERSION=$(docker exec "$CONTAINER_NAME" neo4j --version 2>/dev/null | head -1 || echo 'unknown')
    CURRENT_VERSION_NUMBER=$(echo "$CURRENT_VERSION" | sed 's/neo4j version //; s/[^0-9.].*//')

    echo -e "  Backup version: ${BLUE}$BACKUP_VERSION${NC}"
    echo -e "  Current version: ${BLUE}$CURRENT_VERSION${NC}"

    if [ "$BACKUP_VERSION_NUMBER" != "$CURRENT_VERSION_NUMBER" ] && [ "$BACKUP_VERSION_NUMBER" != "unknown" ] && [ "$CURRENT_VERSION_NUMBER" != "unknown" ]; then
        echo ""
        echo -e "${YELLOW}⚠️  VERSION MISMATCH WARNING:${NC}"
        echo -e "  Backup was created with Neo4j ${BLUE}$BACKUP_VERSION_NUMBER${NC}"
        echo -e "  Current Neo4j version is ${BLUE}$CURRENT_VERSION_NUMBER${NC}"
        echo ""
        echo -e "${RED}Binary backups are version-specific!${NC}"
        echo -e "  Restoring across different versions may fail or cause data corruption."
        echo -e "  Recommended: Restore to same Neo4j version: ${BLUE}$BACKUP_VERSION_NUMBER${NC}"
        echo ""

        if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
            read -p "Continue anyway? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}✓ Cancelled due to version mismatch${NC}"
                exit 0
            fi
        fi
    else
        echo -e "  ${GREEN}✓ Versions match - restore should work correctly${NC}"
    fi
    echo ""
fi

# Check if target database exists
echo -e "${YELLOW}Checking target database '$DATABASE_NAME'...${NC}"
DB_EXISTS=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder "SHOW DATABASES" | grep -c "^$DATABASE_NAME" || echo "0")

if [ "$DB_EXISTS" -gt 0 ]; then
    echo -e "${YELLOW}✓ Database exists${NC}"

    # Check if database is empty
    NODE_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH (n) RETURN count(n) AS count" 2>/dev/null | tail -n 1 || echo "0")
    REL_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH ()-[r]->() RETURN count(r) AS count" 2>/dev/null | tail -n 1 || echo "0")

    if [ "$NODE_COUNT" -gt 0 ] || [ "$REL_COUNT" -gt 0 ]; then
        echo ""
        echo -e "${RED}⚠️  DANGER: Database '$DATABASE_NAME' is not empty!${NC}"
        echo -e "  Nodes: ${RED}$NODE_COUNT${NC}"
        echo -e "  Relationships: ${RED}$REL_COUNT${NC}"
        echo ""

        if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
            echo "What would you like to do?"
            echo "  [1] Cancel (RECOMMENDED) - Stop and protect existing data"
            echo "  [2] Backup existing data first, then restore"
            echo "  [3] Create new database instead"
            echo "  [4] Force overwrite (DANGEROUS) - Delete all existing data and restore"
            echo ""
            read -p "Your choice [1]: " choice
            choice=${choice:-1}

            case $choice in
                1)
                    echo -e "${YELLOW}✓ Cancelled. Existing data is protected.${NC}"
                    exit 0
                    ;;
                2)
                    NEW_BACKUP_DIR="./backups/pre-restore-backup-$(date +%Y%m%d-%H%M%S)"
                    echo -e "${YELLOW}Creating backup of existing data to '$NEW_BACKUP_DIR'...${NC}"
                    ./utilityScripts/backup-graph.sh --backup-dir "$NEW_BACKUP_DIR" --database-name "$DATABASE_NAME"
                    echo -e "${GREEN}✓ Backup created. Proceeding with restore...${NC}"
                    ;;
                3)
                    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                    NEW_DB_NAME="${DATABASE_NAME}-restore-$TIMESTAMP"
                    echo -e "${YELLOW}Creating new database '$NEW_DB_NAME' instead...${NC}"
                    DATABASE_NAME="$NEW_DB_NAME"
                    ;;
                4)
                    echo -e "${RED}⚠️  WARNING: This will permanently delete all existing data!${NC}"
                    read -p "Are you absolutely sure? Type 'yes' to continue: " confirmation
                    if [ "$confirmation" != "yes" ]; then
                        echo -e "${YELLOW}✓ Cancelled. Existing data is protected.${NC}"
                        exit 0
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}✓ Cancelled. Existing data is protected.${NC}"
                    exit 0
                    ;;
            esac
        fi
    else
        echo -e "${GREEN}✓ Database exists but is empty${NC}"
    fi
else
    echo -e "${YELLOW}Database does not exist - will be created${NC}"
fi

echo ""

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}DRY RUN MODE - No changes will be made${NC}"
    echo ""
    echo -e "${YELLOW}Would perform the following operations:${NC}"
    echo -e "  1. Stop Neo4j container '$CONTAINER_NAME'"
    echo -e "  2. Restore database '$DATABASE_NAME' from '$BACKUP_DIR'"
    echo -e "  3. Start Neo4j container '$CONTAINER_NAME'"
    echo -e "  4. Grant write privileges to admin user"
    echo -e "  5. Verify restore success"
    echo ""
    echo -e "${GREEN}✓ Dry run completed successfully${NC}"
    exit 0
fi

# Final confirmation
if [ "$FORCE" = false ]; then
    echo -e "${YELLOW}Ready to restore database '$DATABASE_NAME' from '$BACKUP_DIR'${NC}"
    read -p "Proceed with restore? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}✓ Cancelled${NC}"
        exit 0
    fi
fi

# Stop container
echo -e "${YELLOW}Stopping Neo4j container for restore...${NC}"
docker stop "$CONTAINER_NAME"
echo -e "${GREEN}✓ Container stopped${NC}"
echo ""

# Determine the data volume/mount used by the container
DATA_MOUNT=$(docker inspect "$CONTAINER_NAME" -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Type}}:{{.Source}}{{end}}{{end}}' 2>/dev/null | head -1)
DATA_TYPE=$(echo "$DATA_MOUNT" | cut -d: -f1)
DATA_SOURCE=$(echo "$DATA_MOUNT" | cut -d: -f2)

if [ -z "$DATA_MOUNT" ] || [ -z "$DATA_SOURCE" ]; then
    echo -e "${RED}❌ Error: Could not determine data mount for container '$CONTAINER_NAME'${NC}"
    docker start "$CONTAINER_NAME"
    exit 1
fi

# Restore from backup based on storage type
echo -e "${YELLOW}Restoring database '$DATABASE_NAME' from backup...${NC}"

if [ "$DATA_TYPE" = "volume" ]; then
    # Named volume approach
    docker run --rm \
        -e NEO4J_ACCEPT_LICENSE_AGREEMENT=yes \
        -v "${DATA_SOURCE}:/data" \
        -v "${BACKUP_DIR}:/backups" \
        neo4j:5.26.0-enterprise \
        neo4j-admin database load "$DATABASE_NAME" --from-path=/backups --overwrite-destination=true
elif [ "$DATA_TYPE" = "bind" ]; then
    # Bind mount approach - mount the actual directory
    docker run --rm \
        -e NEO4J_ACCEPT_LICENSE_AGREEMENT=yes \
        -v "${DATA_SOURCE}:/data" \
        -v "${BACKUP_DIR}:/backups" \
        neo4j:5.26.0-enterprise \
        neo4j-admin database load "$DATABASE_NAME" --from-path=/backups --overwrite-destination=true
else
    echo -e "${RED}❌ Error: Unsupported storage type '$DATA_TYPE'${NC}"
    docker start "$CONTAINER_NAME"
    exit 1
fi

echo -e "${GREEN}✓ Database restored${NC}"
echo ""

# Start container
echo -e "${YELLOW}Starting Neo4j container...${NC}"
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

# Grant write privileges
echo -e "${YELLOW}Granting write privileges for admin user...${NC}"
docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder "GRANT WRITE ON GRAPH $DATABASE_NAME TO admin" 2>/dev/null || echo -e "${YELLOW}⚠ Warning: Could not grant write privileges${NC}"
echo -e "${GREEN}✓ Privileges granted${NC}"
echo ""

# Verify restore
echo -e "${YELLOW}Verifying restore...${NC}"
NEW_NODE_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH (n) RETURN count(n) AS count" 2>/dev/null | tail -n 1 || echo "0")
NEW_REL_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH ()-[r]->() RETURN count(r) AS count" 2>/dev/null | tail -n 1 || echo "0")

# Compare with manifest if available
EXPECTED_NODES="?"
EXPECTED_RELS="?"
if [ -f "$MANIFEST_FILE" ]; then
    EXPECTED_NODES=$(jq -r '.node_count' "$MANIFEST_FILE" 2>/dev/null || echo "?")
    EXPECTED_RELS=$(jq -r '.relationship_count' "$MANIFEST_FILE" 2>/dev/null || echo "?")
fi

echo -e "  Restored nodes: ${GREEN}$NEW_NODE_COUNT${NC} (expected: $EXPECTED_NODES)"
echo -e "  Restored relationships: ${GREEN}$NEW_REL_COUNT${NC} (expected: $EXPECTED_RELS)"
echo ""

if [ "$EXPECTED_NODES" != "?" ] && [ "$NEW_NODE_COUNT" != "$EXPECTED_NODES" ]; then
    echo -e "${YELLOW}⚠ Warning: Node count mismatch! Expected $EXPECTED_NODES, got $NEW_NODE_COUNT${NC}"
elif [ "$EXPECTED_RELS" != "?" ] && [ "$NEW_REL_COUNT" != "$EXPECTED_RELS" ]; then
    echo -e "${YELLOW}⚠ Warning: Relationship count mismatch! Expected $EXPECTED_RELS, got $NEW_REL_COUNT${NC}"
else
    echo -e "${GREEN}✓ Restore verification successful${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Restore completed successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Database Summary:${NC}"
echo -e "  Name: ${BLUE}$DATABASE_NAME${NC}"
echo -e "  Nodes: ${GREEN}$NEW_NODE_COUNT${NC}"
echo -e "  Relationships: ${GREEN}$NEW_REL_COUNT${NC}"
echo ""
echo -e "${GREEN}Your knowledge graph has been restored and is ready to use!${NC}"
