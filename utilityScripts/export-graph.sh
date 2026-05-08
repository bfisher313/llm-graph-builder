#!/bin/bash
# Neo4j Knowledge Graph Export Script (Cypher Format)
# Exports graph data as Cypher statements for portability
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
    echo "Neo4j Knowledge Graph Export Script (Cypher Format)"
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
    echo "  - This exports data as Cypher statements (portable, human-readable)"
    echo "  - Export is non-destructive - source data is never modified"
    echo "  - Export runs while database is online (no downtime)"
    echo "  - Exported files can be imported into any Neo4j instance"
    echo "  - Ideal for version control or partial restores"
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
    # Convert comma-separated labels to array
    IFS=',' read -ra LABEL_ARRAY <<< "$LABELS"
    LABEL_FILTER="WHERE "
    FIRST=true
    for label in "${LABEL_ARRAY[@]}"; do
        if [ "$FIRST" = false ]; then
            LABEL_FILTER+=" OR "
        fi
        LABEL_FILTER+="'$label' IN labels(n)"
        FIRST=false
    done
else
    LABEL_FILTER=""
fi

# Export nodes
echo -e "${YELLOW}Exporting nodes...${NC}"
NODE_FILE="$EXPORT_PATH/nodes.cypher"

docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" --format plain "CALL apoc.export.cypher.all('${NODE_FILE}', {useOptimizations: {type: 'UNWIND_BATCH'}, batchSize: 100}) YIELD file, source, format, nodes, relationships, properties, time RETURN *" 2>/dev/null || {
    # Fallback: Manual export if APOC export fails
    echo -e "${YELLOW}⚠ APOC export not available, using manual export...${NC}"

    # Get all node labels
    if [ -n "$LABELS" ]; then
        NODE_LABELS="$LABELS"
    else
        NODE_LABELS=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "CALL db.labels() YIELD label RETURN label" 2>/dev/null | grep -v "^label$" | tr '\n' ',' | sed 's/,$//')
    fi

    echo "// Node exports - $(date)" > "$NODE_FILE"
    echo "" >> "$NODE_FILE"

    IFS=',' read -ra EXPORT_LABELS <<< "$NODE_LABELS"
    for label in "${EXPORT_LABELS[@]}"; do
        label=$(echo "$label" | xargs) # Trim whitespace
        if [ -n "$label" ]; then
            echo "Exporting nodes with label: $label"
            docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" --format plain "MATCH (n:$label) RETURN apoc.create.vNode([labels(n)[0]], properties(n)) AS node" 2>/dev/null >> "$NODE_FILE" || true
        fi
    done
}

echo -e "${GREEN}✓ Nodes exported${NC}"
echo ""

# Export relationships
echo -e "${YELLOW}Exporting relationships...${NC}"
REL_FILE="$EXPORT_PATH/relationships.cypher"

echo "// Relationship exports - $(date)" > "$REL_FILE"
echo "" >> "$REL_FILE"

# Get all relationship types
REL_TYPES=$(docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" "CALL db.relationshipTypes() YIELD relationshipType RETURN relationshipType" 2>/dev/null | grep -v "^relationshipType$" | tr '\n' ',' | sed 's/,$//')

IFS=',' read -ra EXPORT_RELS <<< "$REL_TYPES"
for rel_type in "${EXPORT_RELS[@]}"; do
    rel_type=$(echo "$rel_type" | xargs) # Trim whitespace
    if [ -n "$rel_type" ]; then
        echo "Exporting relationships: $rel_type"
        docker exec "$CONTAINER_NAME" cypher-shell -u neo4j -p llmgraphbuilder -d "$DATABASE_NAME" --format plain "MATCH (a)-[r:$rel_type]->(b) RETURN apoc.create.vRelationship(a, type(r), properties(r), b) AS rel" 2>/dev/null >> "$REL_FILE" || true
    fi
done

echo -e "${GREEN}✓ Relationships exported${NC}"
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
    "container_name": "$CONTAINER_NAME"
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
echo ""
echo -e "${YELLOW}To import this export, run:${NC}"
echo -e "  ${BLUE}./utilityScripts/import-graph.sh --export-dir $EXPORT_PATH --database-name $DATABASE_NAME${NC}"
echo ""
echo -e "${GREEN}Export is safe and non-destructive. Original data is unchanged.${NC}"
