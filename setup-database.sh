#!/bin/bash
# Database Setup Script
# Creates the custom Neo4j database and grants necessary write privileges
# for the knowledge graph builder. Run this after docker compose up.

echo "Setting up Neo4j database for knowledge graph builder..."

# Wait for Neo4j to be ready
echo "Waiting for Neo4j to start..."
while ! docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder "RETURN 1" > /dev/null 2>&1; do
    echo "Neo4j not ready yet, waiting..."
    sleep 2
done

echo "Neo4j is ready."

# Step 1: Create the custom database if it doesn't already exist
echo "Checking if database 'theblackbookofpower' exists..."
if ! docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder "SHOW DATABASES" | grep -q "theblackbookofpower"; then
    echo "Creating database 'theblackbookofpower'..."
    docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder "CREATE DATABASE theblackbookofpower WAIT"
else
    echo "Database 'theblackbookofpower' already exists."
fi

# Step 2: Grant write privileges to admin user for the new database
# This is required because Neo4j Enterprise's permission system requires
# explicit database-specific grants for the backend's privilege checks
echo "Granting write privileges for admin user..."
docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder "GRANT WRITE ON GRAPH theblackbookofpower TO admin"

echo ""
echo "✓ Database 'theblackbookofpower' setup complete!"
echo ""
echo "Database status:"
docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder "SHOW DATABASES"
echo ""
echo "Write privileges:"
docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder "SHOW USER PRIVILEGES YIELD action, graph WHERE graph = 'theblackbookofpower' AND action = 'write'"
echo ""
echo "You can now access the application at http://localhost:8080"
