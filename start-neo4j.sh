#!/bin/bash
# ============================================================
# Standalone Neo4j with APOC + GDS
# ============================================================
# Usage:
#   ./start-neo4j.sh          # start (detached)
#   ./start-neo4j.sh stop     # stop
#   ./start-neo4j.sh status   # check if running
# ============================================================

CONTAINER_NAME="neo4j-standalone"
NEO4J_IMAGE="neo4j:5.26.0-enterprise"
NEO4J_PASSWORD="llmgraphbuilder"
DATA_DIR="./neo4j/data"
IMPORT_DIR="./neo4j/import"

start() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Neo4j is already running on:"
        echo "  Browser: http://localhost:7474"
        echo "  Bolt:    bolt://localhost:7687"
        exit 0
    fi

    mkdir -p "$DATA_DIR" "$IMPORT_DIR"

    echo "Starting Neo4j ${NEO4J_IMAGE}..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p 7474:7474 \
        -p 7687:7687 \
        -e NEO4J_ACCEPT_LICENSE_AGREEMENT=yes \
        -e "NEO4J_AUTH=neo4j/${NEO4J_PASSWORD}" \
        -e 'NEO4J_PLUGINS=["apoc","graph-data-science"]' \
        -e NEO4J_dbms_security_procedures_unrestricted=apoc.*,gds.* \
        -v "$(pwd)/${DATA_DIR}:/data" \
        -v "$(pwd)/${IMPORT_DIR}:/var/lib/neo4j/import" \
        "$NEO4J_IMAGE"

    echo ""
    echo "Neo4j starting up..."
    echo "  Browser: http://localhost:7474"
    echo "  Bolt:    bolt://localhost:7687"
    echo "  Login:   neo4j / ${NEO4J_PASSWORD}"
    echo ""
    echo "Note: First start downloads APOC + GDS plugins (may take a moment)."
}

stop() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Stopping Neo4j..."
        docker stop "$CONTAINER_NAME" && docker rm "$CONTAINER_NAME"
        echo "Stopped."
    else
        echo "Neo4j is not running."
    fi
}

status() {
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Neo4j is running."
        echo "  Browser: http://localhost:7474"
        echo "  Bolt:    bolt://localhost:7687"
    else
        echo "Neo4j is not running."
    fi
}

case "${1:-start}" in
    start)  start  ;;
    stop)   stop   ;;
    status) status ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
