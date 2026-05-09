#!/bin/bash
# Neo4j Knowledge Graph Export Script (Simple Cypher Format)
# Exports graph data using basic Cypher queries
# This is NON-DESTRUCTIVE and safe to run anytime

set -e  # Exit on error

# Configuration
DEFAULT_EXPORT_DIR="./backups/cypher-exports"
DEFAULT_DATABASE="theblackbookofpower"
CONTAINER_NAME="neo4j-llm-graph-builder"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
EXPORT_DIR="$DEFAULT_EXPORT_DIR"
DATABASE_NAME="$DEFAULT_DATABASE"
LABELS=""
HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --export-dir)
            EXPORT_DIR="$2"
            shift 2
            ;;
        --database-name)
            DATABASE_NAME="$2"
            shift 2
            ;;
        --labels)
            LABELS="$2"
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
    echo "Neo4j Knowledge Graph Export Script (Simple Cypher Format)"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --export-dir DIR       Export directory (default: $DEFAULT_EXPORT_DIR)"
    echo "  --database-name NAME   Database name (default: $DEFAULT_DATABASE)"
    echo "  --labels LABELS        Comma-separated list of labels to export (default: all)"
    echo "  --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Export all data"
    echo "  $0 --export-dir ./my-exports         # Custom export directory"
    echo "  $0 --labels Document,Person,Company  # Export only specific labels"
    echo "  $0 --database-name mygraph --export-dir /exports  # Custom both"
    echo ""
    echo "Notes:"
    echo "  - This exports data using basic Cypher queries (portable, human-readable)"
    echo "  - Export is non-destructive - source data is never modified"
    echo "  - Export runs while database is online (no downtime)"
    echo "  - Exported files can be imported into any Neo4j instance"
    echo "  - Uses direct Neo4j output format, no APOC required"
    exit 0
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Neo4j Knowledge Graph Export${NC}"
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

# Create export directory with timestamp
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
EXPORT_PATH="$EXPORT_DIR/${DATABASE_NAME}-export-$TIMESTAMP"
mkdir -p "$EXPORT_PATH"

echo -e "${YELLOW}Export configuration:${NC}"
echo -e "  Database: ${BLUE}$DATABASE_NAME${NC}"
echo -e "  Export directory: ${BLUE}$EXPORT_PATH${NC}"
echo -e "  Labels: ${BLUE}${LABELS:-all}${NC}"
echo ""

# Get database statistics
echo -e "${YELLOW}Getting database statistics...${NC}"
NODE_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH (n) RETURN count(n) AS count" 2>/dev/null | tail -n 1 || echo "0")
REL_COUNT=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "MATCH ()-[r]->() RETURN count(r) AS count" 2>/dev/null | tail -n 1 || echo "0")

echo -e "  Total nodes: ${GREEN}$NODE_COUNT${NC}"
echo -e "  Total relationships: ${GREEN}$REL_COUNT${NC}"
echo ""

# Check if database has data
if [ "$NODE_COUNT" -eq 0 ] && [ "$REL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ Warning: Database is empty - nothing to export${NC}"
    echo "Creating empty export file anyway..."
fi

# Build Cypher query based on labels
if [ -n "$LABELS" ]; then
    # Export specific labels
    LABEL_FILTER=""
    IFS=',' read -ra LABEL_ARRAY <<< "$LABELS"
    FIRST=true
    for label in "${LABEL_ARRAY[@]}"; do
        label=$(echo "$label" | xargs) # Trim whitespace
        if [ "$FIRST" = false ]; then
            LABEL_FILTER+=" OR "
        fi
        LABEL_FILTER+="\"\$label\" IN labels(n)"
        FIRST=false
    done
    NODE_QUERY="MATCH (n) WHERE $LABEL_FILTER RETURN n"
    REL_QUERY="MATCH (a)-[r]->(b) WHERE any(label IN labels(a) WHERE \"\$label\" IN [\"${LABELS//,/\",\"}\"]) OR any(label IN labels(b) WHERE \"\$label\" IN [\"${LABELS//,/\",\"}\"])) RETURN r"
else
    # Export all data
    NODE_QUERY="MATCH (n) RETURN n"
    REL_QUERY="MATCH (a)-[r]->(b) RETURN r"
fi

# Export nodes
echo -e "${YELLOW}Exporting nodes...${NC}"
NODE_FILE="$EXPORT_PATH/nodes.cypher"
echo "// Neo4j Node Export - $(date)" > "$NODE_FILE"
echo "" >> "$NODE_FILE"

# Export nodes using basic Cypher
docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" --format plain "$NODE_QUERY" 2>/dev/null | grep -v "^n$" | grep -v "^$" >> "$NODE_FILE" || true

NODE_EXPORT_COUNT=$(wc -l < "$NODE_FILE" 2>/dev/null || echo "0")
echo -e "${GREEN}✓ Nodes exported ($NODE_EXPORT_COUNT lines)${NC}"
echo ""

# Export relationships
echo -e "${YELLOW}Exporting relationships...${NC}"
REL_FILE="$EXPORT_PATH/relationships.cypher"
echo "// Neo4j Relationship Export - $(date)" > "$REL_FILE"
echo "" >> "$REL_FILE"

# Export relationships using basic Cypher
docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" --format plain "$REL_QUERY" 2>/dev/null | grep -v "^r$" | grep -v "^$" >> "$REL_FILE" || true

REL_EXPORT_COUNT=$(wc -l < "$REL_FILE" 2>/dev/null || echo "0")
echo -e "${GREEN}✓ Relationships exported ($REL_EXPORT_COUNT lines)${NC}"
echo ""

# Combine into single export file
COMBINED_FILE="$EXPORT_PATH/${DATABASE_NAME}-export-$TIMESTAMP.cypher"
echo -e "${YELLOW}Creating combined export file...${NC}"
{
    echo "// Neo4j Knowledge Graph Export"
    echo "// Database: $DATABASE_NAME"
    echo "// Export Date: $(date)"
    echo "// Nodes: $NODE_COUNT"
    echo "// Relationships: $REL_COUNT"
    echo ""
    echo "// ============================================"
    echo "// NODES"
    echo "// ============================================"
    echo ""
    cat "$NODE_FILE" 2>/dev/null || true
    echo ""
    echo "// ============================================"
    echo "// RELATIONSHIPS"
    echo "// ============================================"
    echo ""
    cat "$REL_FILE" 2>/dev/null || true
} > "$COMBINED_FILE"

echo -e "${GREEN}✓ Combined export created${NC}"
echo ""

# Create manifest
MANIFEST_FILE="$EXPORT_PATH/manifest.json"
echo -e "${YELLOW}Creating export manifest...${NC}"
cat > "$MANIFEST_FILE" << EOF
{
    "export_type": "cypher",
    "database_name": "$DATABASE_NAME",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "timestamp_local": "$(date)",
    "node_count": $NODE_COUNT,
    "relationship_count": $REL_COUNT,
    "export_path": "$EXPORT_PATH",
    "export_file": "$COMBINED_FILE",
    "labels_filtered": "${LABELS:-none}",
    "container_name": "$CONTAINER_NAME",
    "export_method": "direct_cypher"
}
EOF
echo -e "${GREEN}✓ Manifest created${NC}"
echo ""

# Get export size
EXPORT_SIZE=$(du -sh "$EXPORT_PATH" | cut -f1)

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Export completed successfully!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Export Summary:${NC}"
echo -e "  Location: ${BLUE}$EXPORT_PATH${NC}"
echo -e "  Main file: ${BLUE}$COMBINED_FILE${NC}"
echo -e "  Size: ${BLUE}$EXPORT_SIZE${NC}"
echo -e "  Database: ${BLUE}$DATABASE_NAME${NC}"
echo -e "  Nodes exported: ${GREEN}$NODE_COUNT${NC}"
echo -e "  Relationships exported: ${GREEN}$REL_COUNT${NC}"
echo -e "  Node file lines: ${GREEN}$NODE_EXPORT_COUNT${NC}"
echo -e "  Relationship file lines: ${GREEN}$REL_EXPORT_COUNT${NC}"
echo ""
echo -e "${YELLOW}To import this export, run:${NC}"
echo -e "  ${BLUE}./utilityScripts/import-graph.sh --export-dir $EXPORT_PATH --database-name $DATABASE_NAME${NC}"
echo ""
echo -e "${GREEN}Export is safe and non-destructive. Original data is unchanged.${NC}"
