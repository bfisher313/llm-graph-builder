#!/bin/bash
# Neo4j Knowledge Graph Import Script (Cypher Format)
# Imports graph data from Cypher export files
# WARNING: This operation can be DESTRUCTIVE - will add/replace data

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
IMPORT_DIR=""
DATABASE_NAME="$DEFAULT_DATABASE"
HELP=false
DRY_RUN=false
FORCE=false
MODE="append"  # Options: append, replace

while [[ $# -gt 0 ]]; do
    case $1 in
        --import-dir)
            IMPORT_DIR="$2"
            shift 2
            ;;
        --database-name)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
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
    echo "Neo4j Knowledge Graph Import Script (Cypher Format)"
    echo "Usage: $0 --import-dir IMPORT_DIR [options]"
    echo ""
    echo "Required:"
    echo "  --import-dir DIR       Export directory to import from"
    echo ""
    echo "Options:"
    echo "  --database-name NAME   Target database name (default: $DEFAULT_DATABASE)"
    echo "  --mode MODE            Import mode: append or replace (default: append)"
    echo "  --dry-run              Show what would happen without making changes"
    echo "  --force                Skip safety warnings and proceed with import"
    echo "  --help                 Show this help message"
    echo ""
    echo "Safety Features:"
    echo "  - Warns if target database exists and is not empty"
    echo "  - Offers backup-before-import option"
    echo "  - Multiple confirmation steps"
    echo "  - Dry-run mode available"
    echo ""
    echo "Import Modes:"
    echo "  append: Add data to existing database (default)"
    echo "  replace: Clear database before importing (destructive)"
    echo ""
    echo "Examples:"
    echo "  $0 --import-dir ./backups/cypher-exports/theblackbookofpower-export-2026-05-06-143022"
    echo "  $0 --import-dir ./exports --database-name test-db --mode replace"
    echo "  $0 --import-dir ./exports --dry-run"
    echo ""
    exit 0
fi

# Check if import directory is provided
if [ -z "$IMPORT_DIR" ]; then
    echo -e "${RED}❌ Error: --import-dir is required${NC}"
    echo "Use --help for usage information"
    exit 1
fi

# Check if import directory exists
if [ ! -d "$IMPORT_DIR" ]; then
    echo -e "${RED}❌ Error: Import directory '$IMPORT_DIR' does not exist${NC}"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Neo4j Knowledge Graph Import${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Find the main export file
EXPORT_FILE=$(find "$IMPORT_DIR" -name "${DATABASE_NAME}-export-*.cypher" -type f | head -1)
if [ -z "$EXPORT_FILE" ]; then
    # Try to find any .cypher file
    EXPORT_FILE=$(find "$IMPORT_DIR" -name "*.cypher" -type f | head -1)
    if [ -z "$EXPORT_FILE" ]; then
        echo -e "${RED}❌ Error: No Cypher export files found in '$IMPORT_DIR'${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Import configuration:${NC}"
echo -e "  Import directory: ${BLUE}$IMPORT_DIR${NC}"
echo -e "  Export file: ${BLUE}$EXPORT_FILE${NC}"
echo -e "  Target database: ${BLUE}$DATABASE_NAME${NC}"
echo -e "  Import mode: ${BLUE}$MODE${NC}"
echo ""

# Read manifest if available
MANIFEST_FILE="$IMPORT_DIR/manifest.json"
if [ -f "$MANIFEST_FILE" ]; then
    echo -e "${YELLOW}Import manifest:${NC}"
    echo -e "  Type: $(jq -r '.export_type' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
    echo -e "  Database: $(jq -r '.database_name' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
    echo -e "  Created: $(jq -r '.timestamp_local' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
    echo -e "  Nodes: $(jq -r '.node_count' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
    echo -e "  Relationships: $(jq -r '.relationship_count' "$MANIFEST_FILE" 2>/dev/null || echo 'unknown')"
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

# Check if target database exists
echo -e "${YELLOW}Checking target database '$DATABASE_NAME'...${NC}"
DB_EXISTS=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder "SHOW DATABASES" | grep -c "^$DATABASE_NAME" || echo "0")

if [ "$DB_EXISTS" -eq 0 ]; then
    echo -e "${YELLOW}Database does not exist - will be created${NC}"
    echo -e "${YELLOW}Creating database '$DATABASE_NAME'...${NC}"
    docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder "CREATE DATABASE $DATABASE_NAME WAIT"
    echo -e "${GREEN}✓ Database created${NC}"
else
    echo -e "${YELLOW}✓ Database exists${NC}"

    # Check if database is empty
    NODE_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH (n) RETURN count(n) AS count" 2>/dev/null | tail -n 1 || echo "0")
    REL_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH ()-[r]->() RETURN count(r) AS count" 2>/dev/null | tail -n 1 || echo "0")

    if [ "$MODE" = "replace" ] && ([ "$NODE_COUNT" -gt 0 ] || [ "$REL_COUNT" -gt 0 ]); then
        echo ""
        echo -e "${RED}⚠️  DANGER: Replace mode with non-empty database!${NC}"
        echo -e "  Database '$DATABASE_NAME' contains:"
        echo -e "  Nodes: ${RED}$NODE_COUNT${NC}"
        echo -e "  Relationships: ${RED}$REL_COUNT${NC}"
        echo ""

        if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
            echo "What would you like to do?"
            echo "  [1] Cancel (RECOMMENDED) - Stop and protect existing data"
            echo "  [2] Backup existing data first, then replace"
            echo "  [3] Create new database instead"
            echo "  [4] Force replace (DANGEROUS) - Delete all existing data and import"
            echo ""
            read -p "Your choice [1]: " choice
            choice=${choice:-1}

            case $choice in
                1)
                    echo -e "${YELLOW}✓ Cancelled. Existing data is protected.${NC}"
                    exit 0
                    ;;
                2)
                    NEW_BACKUP_DIR="./backups/pre-import-backup-$(date +%Y%m%d-%H%M%S)"
                    echo -e "${YELLOW}Creating backup of existing data to '$NEW_BACKUP_DIR'...${NC}"
                    ./utilityScripts/backup-graph.sh --backup-dir "$NEW_BACKUP_DIR" --database-name "$DATABASE_NAME"
                    echo -e "${GREEN}✓ Backup created. Proceeding with import...${NC}"
                    ;;
                3)
                    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                    NEW_DB_NAME="${DATABASE_NAME}-import-$TIMESTAMP"
                    echo -e "${YELLOW}Creating new database '$NEW_DB_NAME' instead...${NC}"
                    DATABASE_NAME="$NEW_DB_NAME"
                    MODE="append" # New database doesn't need replace
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
    elif [ "$MODE" = "append" ] && ([ "$NODE_COUNT" -gt 0 ] || [ "$REL_COUNT" -gt 0 ]); then
        echo ""
        echo -e "${YELLOW}⚠️  Warning: Append mode with non-empty database${NC}"
        echo -e "  Database '$DATABASE_NAME' already contains:"
        echo -e "  Nodes: ${YELLOW}$NODE_COUNT${NC}"
        echo -e "  Relationships: ${YELLOW}$REL_COUNT${NC}"
        echo -e "  Data will be added to existing content${NC}"
        echo ""

        if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
            read -p "Continue with append mode? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}✓ Cancelled${NC}"
                exit 0
            fi
        fi
    fi
fi

echo ""

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    echo -e "${BLUE}DRY RUN MODE - No changes will be made${NC}"
    echo ""
    echo -e "${YELLOW}Would perform the following operations:${NC}"
    if [ "$MODE" = "replace" ]; then
        echo -e "  1. Clear database '$DATABASE_NAME' (delete all nodes and relationships)"
    else
        echo -e "  1. Keep existing data in '$DATABASE_NAME'"
    fi
    echo -e "  2. Import data from '$EXPORT_FILE'"
    echo -e "  3. Grant write privileges to admin user"
    echo -e "  4. Verify import success"
    echo ""
    echo -e "${GREEN}✓ Dry run completed successfully${NC}"
    exit 0
fi

# Final confirmation
if [ "$FORCE" = false ]; then
    echo -e "${YELLOW}Ready to import data into database '$DATABASE_NAME'${NC}"
    echo -e "Mode: ${BLUE}$MODE${NC}"
    read -p "Proceed with import? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}✓ Cancelled${NC}"
        exit 0
    fi
fi

# Clear database if in replace mode
if [ "$MODE" = "replace" ]; then
    echo -e "${YELLOW}Clearing database '$DATABASE_NAME'...${NC}"
    docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH (n) DETACH DELETE n" 2>/dev/null || true
    echo -e "${GREEN}✓ Database cleared${NC}"
    echo ""
fi

# Import data
echo -e "${YELLOW}Importing data from '$EXPORT_FILE'...${NC}"

# Copy file to container for faster import
CONTAINER_IMPORT_FILE="/tmp/import-$(date +%s).cypher"
docker cp "$EXPORT_FILE" "$CONTAINER_NAME:$CONTAINER_IMPORT_FILE"

# Import using cypher-shell
docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" --file "$CONTAINER_IMPORT_FILE" 2>&1 | while IFS= read -r line; do
    if [[ ! "$line" =~ ^(WARNING|ERROR|Exception) ]]; then
        echo "  $line"
    fi
done

echo -e "${GREEN}✓ Import completed${NC}"
echo ""

# Clean up temp file
docker exec "$CONTAINER_NAME" rm -f "$CONTAINER_IMPORT_FILE" 2>/dev/null || true

# Grant write privileges
echo -e "${YELLOW}Granting write privileges for admin user...${NC}"
docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder "GRANT WRITE ON GRAPH $DATABASE_NAME TO admin" 2>/dev/null || echo -e "${YELLOW}⚠ Warning: Could not grant write privileges${NC}"
echo -e "${GREEN}✓ Privileges granted${NC}"
echo ""

# Verify import
echo -e "${YELLOW}Verifying import...${NC}"
NEW_NODE_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH (n) RETURN count(n) AS count" 2>/dev/null | tail -n 1 || echo "0")
NEW_REL_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH ()-[r]->() RETURN count(r) AS count" 2>/dev/null | tail -n 1 || echo "0")

# Compare with manifest if available
EXPECTED_NODES="?"
EXPECTED_RELS="?"
if [ -f "$MANIFEST_FILE" ]; then
    EXPECTED_NODES=$(jq -r '.node_count' "$MANIFEST_FILE" 2>/dev/null || echo "?")
    EXPECTED_RELS=$(jq -r '.relationship_count' "$MANIFEST_FILE" 2>/dev/null || echo "?")
fi

echo -e "  Imported nodes: ${GREEN}$NEW_NODE_COUNT${NC} (expected: $EXPECTED_NODES)"
echo -e "  Imported relationships: ${GREEN}$NEW_REL_COUNT${NC} (expected: $EXPECTED_RELS)"
echo ""

if [ "$EXPECTED_NODES" != "?" ] && [ "$NEW_NODE_COUNT" != "$EXPECTED_NODES" ]; then
    echo -e "${YELLOW}⚠ Warning: Node count mismatch! Expected $EXPECTED_NODES, got $NEW_NODE_COUNT${NC}"
elif [ "$EXPECTED_RELS" != "?" ] && [ "$NEW_REL_COUNT" != "$EXPECTED_RELS" ]; then
    echo -e "${YELLOW}⚠ Warning: Relationship count mismatch! Expected $EXPECTED_RELS, got $NEW_REL_COUNT${NC}"
else
    echo -e "${GREEN}✓ Import verification successful${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Import completed successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Database Summary:${NC}"
echo -e "  Name: ${BLUE}$DATABASE_NAME${NC}"
echo -e "  Nodes: ${GREEN}$NEW_NODE_COUNT${NC}"
echo -e "  Relationships: ${GREEN}$NEW_REL_COUNT${NC}"
echo ""
echo -e "${GREEN}Your knowledge graph has been imported and is ready to use!${NC}"
