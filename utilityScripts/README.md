# Neo4j Knowledge Graph Backup & Restore Utilities

Comprehensive set of scripts for backing up, restoring, exporting, and importing Neo4j knowledge graphs. These utilities provide both binary dumps (fast, complete) and Cypher exports (portable, human-readable) with robust safety features.

## 🚀 Quick Start

### Binary Backup (Recommended for Production)
```bash
# Create a full binary backup
./utilityScripts/backup-graph.sh

# Restore from backup
./utilityScripts/restore-graph.sh --backup-dir ./backups/binary-backup-2026-05-06-143022
```

### Cypher Export (Portability & Version Control)
```bash
# Export as Cypher statements
./utilityScripts/export-graph.sh

# Import from Cypher file
./utilityScripts/import-graph.sh --import-dir ./backups/cypher-exports/theblackbookofpower-export-2026-05-06-143022
```

## 📁 Directory Structure

```
utilityScripts/
├── backup-graph.sh      # Binary backup (fast, complete, Enterprise only)
├── restore-graph.sh     # Binary restore with safety features
├── export-graph.sh      # Cypher export (portable, human-readable)
├── import-graph.sh      # Cypher import with safety features
└── README.md           # This documentation

backups/  (created automatically)
├── binary-backup-2026-05-06-143022/
│   ├── dump/
│   └── manifest.json
└── cypher-exports/
    ├── theblackbookofpower-export-2026-05-06-143022.cypher
    └── manifest.json
```

## 🛡️ Safety Features

### All Scripts Include:
- ✅ **Validation**: Container status, database existence, file integrity
- ✅ **Error Handling**: Graceful failure with clear error messages
- ✅ **Progress Indicators**: Real-time status updates
- ✅ **Colored Output**: Green (success), Yellow (warning), Red (danger)
- ✅ **Dry-Run Mode**: Preview operations without making changes

### Destructive Operations (Restore/Import):
- ⚠️ **Database Existence Check**: Warns if target database exists
- ⚠️ **Non-Empty Detection**: Shows node/relationship counts before proceeding
- ⚠️ **Multi-Step Confirmation**: Multiple safety prompts
- ⚠️ **Backup-Before-Replace**: Option to backup existing data first
- ⚠️ **Force Protection**: Explicit `--force` flag needed to skip safety

### Safety Workflow Example:
```
⚠️  DANGER: Database 'theblackbookofpower' is not empty!
  Nodes: 1,234
  Relationships: 5,678

What would you like to do?
  [1] Cancel (RECOMMENDED) - Stop and protect existing data
  [2] Backup existing data first, then restore
  [3] Create new database instead
  [4] Force overwrite (DANGEROUS) - Delete all existing data and restore

Your choice [1]:
```

## 📋 Prerequisites

### Required:
- **Neo4j Enterprise** (for binary backup/restore)
- **Docker** (container management)
- **Bash** (shell environment)

### Neo4j Plugins:
- **APOC** (required for Cypher export)
- **Graph Data Science (GDS)** (recommended for graph algorithms)

### Permissions:
- **Docker access** (ability to run docker commands)
- **File system access** (read/write to backup directories)

## 📖 Script Reference

### `backup-graph.sh` - Binary Backup

Creates a complete binary backup of a Neo4j database using `neo4j-admin dump`.

**Usage:**
```bash
./utilityScripts/backup-graph.sh [options]
```

**Options:**
- `--backup-dir DIR` - Backup directory (default: `./backups`)
- `--database-name NAME` - Database name (default: `theblackbookofpower`)
- `--help` - Show help message

**Examples:**
```bash
# Use defaults
./utilityScripts/backup-graph.sh

# Custom backup location
./utilityScripts/backup-graph.sh --backup-dir ./my-backups

# Backup specific database
./utilityScripts/backup-graph.sh --database-name mygraph --backup-dir /backups
```

**What it does:**
1. Validates container is running
2. Gets database statistics (nodes, relationships)
3. Stops Neo4j container safely
4. Creates binary backup using `neo4j-admin dump`
5. Creates JSON manifest with metadata
6. Restarts container and verifies health
7. Provides backup summary

**Output:**
- Binary dump files in `backup-dir/binary-backup-TIMESTAMP/dump/`
- JSON manifest with metadata
- Console output with colored status

**Characteristics:**
- ✅ **Non-destructive** - Read-only operation
- ✅ **Complete** - Includes all data, indexes, constraints
- ✅ **Fast** - Binary format for quick backup/restore
- ⚠️ **Downtime required** - Container must be stopped temporarily
- ⚠️ **Enterprise only** - Requires Neo4j Enterprise

---

### `restore-graph.sh` - Binary Restore

Restores a binary backup to a Neo4j database with comprehensive safety features.

**Usage:**
```bash
./utilityScripts/restore-graph.sh --backup-dir BACKUP_DIR [options]
```

**Required:**
- `--backup-dir DIR` - Backup directory to restore from

**Options:**
- `--database-name NAME` - Target database name (default: `theblackbookofpower`)
- `--dry-run` - Show what would happen without making changes
- `--force` - Skip safety warnings
- `--help` - Show help message

**Examples:**
```bash
# Basic restore
./utilityScripts/restore-graph.sh --backup-dir ./backups/binary-backup-2026-05-06-143022

# Restore to different database
./utilityScripts/restore-graph.sh --backup-dir ./backups/binary-backup-2026-05-06-143022 --database-name test-db

# Dry run to see what would happen
./utilityScripts/restore-graph.sh --backup-dir ./backups/binary-backup-2026-05-06-143022 --dry-run

# Force restore (skips safety warnings)
./utilityScripts/restore-graph.sh --backup-dir ./backups/binary-backup-2026-05-06-143022 --force
```

**Safety Features:**
- Warns if target database exists and is not empty
- Offers backup-before-restore option
- Multiple confirmation steps
- Dry-run mode available
- Post-restore verification

**What it does:**
1. Validates backup directory and manifest
2. Checks if target database exists and is empty
3. Offers safety options if database is not empty
4. Stops Neo4j container
5. Restores database using `neo4j-admin load`
6. Starts container and verifies health
7. Grants write privileges
8. Verifies restore success

**Characteristics:**
- ❌ **Destructive** - Replaces existing data
- ✅ **Complete** - Full database restoration
- ✅ **Fast** - Binary format for quick restore
- ⚠️ **Downtime required** - Container must be stopped temporarily
- ⚠️ **Enterprise only** - Requires Neo4j Enterprise

---

### `export-graph.sh` - Cypher Export

Exports graph data as Cypher statements for portability and human readability.

**Usage:**
```bash
./utilityScripts/export-graph.sh [options]
```

**Options:**
- `--export-dir DIR` - Export directory (default: `./backups/cypher-exports`)
- `--database-name NAME` - Database name (default: `theblackbookofpower`)
- `--labels LABELS` - Comma-separated list of labels to export (default: all)
- `--help` - Show help message

**Examples:**
```bash
# Export all data
./utilityScripts/export-graph.sh

# Export specific labels only
./utilityScripts/export-graph.sh --labels Document,Person,Company

# Custom export location
./utilityScripts/export-graph.sh --export-dir ./my-exports

# Export specific database
./utilityScripts/export-graph.sh --database-name mygraph --export-dir /exports
```

**What it does:**
1. Validates container is running
2. Gets database statistics
3. Exports nodes and relationships as Cypher statements
4. Creates combined export file with metadata
5. Creates JSON manifest
6. Provides export summary

**Output:**
- Combined Cypher file: `database-export-TIMESTAMP.cypher`
- JSON manifest with metadata
- Separate files for nodes and relationships

**Characteristics:**
- ✅ **Non-destructive** - Read-only operation
- ✅ **Portable** - Works across Neo4j versions
- ✅ **Human-readable** - Can be reviewed and edited
- ✅ **No downtime** - Runs while database is online
- ✅ **Flexible** - Can export specific labels or everything

---

### `import-graph.sh` - Cypher Import

Imports graph data from Cypher export files with safety features.

**Usage:**
```bash
./utilityScripts/import-graph.sh --import-dir IMPORT_DIR [options]
```

**Required:**
- `--import-dir DIR` - Export directory to import from

**Options:**
- `--database-name NAME` - Target database name (default: `theblackbookofpower`)
- `--mode MODE` - Import mode: `append` or `replace` (default: `append`)
- `--dry-run` - Show what would happen without making changes
- `--force` - Skip safety warnings
- `--help` - Show help message

**Examples:**
```bash
# Append to existing database
./utilityScripts/import-graph.sh --import-dir ./backups/cypher-exports/theblackbookofpower-export-2026-05-06-143022

# Replace database content
./utilityScripts/import-graph.sh --import-dir ./exports --mode replace

# Import into new database
./utilityScripts/import-graph.sh --import-dir ./exports --database-name test-db --mode append

# Dry run to see what would happen
./utilityScripts/import-graph.sh --import-dir ./exports --dry-run

# Force import (skips safety warnings)
./utilityScripts/import-graph.sh --import-dir ./exports --force
```

**Import Modes:**
- **append**: Add data to existing database (default, safer)
- **replace**: Clear database before importing (destructive)

**Safety Features:**
- Warns if target database exists and is not empty
- Offers backup-before-import option
- Multiple confirmation steps
- Dry-run mode available
- Post-import verification

**What it does:**
1. Validates import directory and finds export files
2. Checks if target database exists
3. In replace mode: warns if database is not empty
4. Offers safety options for non-empty databases
5. Clears database if in replace mode
6. Imports data from Cypher files
7. Grants write privileges
8. Verifies import success

**Characteristics:**
- ⚠️ **Can be destructive** - Replace mode deletes existing data
- ✅ **Portable** - Works across Neo4j versions
- ✅ **Flexible** - Can append or replace
- ✅ **No downtime** - Runs while database is online
- ✅ **Partial imports** - Can import specific labels

## 🔧 Backup Formats

### Binary Dump (`backup-graph.sh` / `restore-graph.sh`)

**Format:** Native Neo4j binary format

**Advantages:**
- ⚡ **Fastest** backup and restore times
- 💾 **Complete** - Includes all data, indexes, constraints
- 🔄 **Reliable** - Official Neo4j method
- 📊 **Accurate** - Bit-for-bit data copy

**Disadvantages:**
- 🔒 **Enterprise only** - Requires Neo4j Enterprise
- 🛑 **Downtime required** - Container must be stopped
- 📦 **Less portable** - Version-specific
- 👀 **Not human-readable** - Binary format

**Best for:**
- Production backups
- Disaster recovery
- Complete database migrations
- Performance-critical environments

### Cypher Export (`export-graph.sh` / `import-graph.sh`)

**Format:** Cypher query language statements

**Advantages:**
- 🌐 **Portable** - Works across Neo4j versions
- 👀 **Human-readable** - Can be reviewed and edited
- 🔄 **No downtime** - Runs while database is online
- 🎯 **Flexible** - Can export/import specific parts
- 📝 **Version control** - Can be tracked in Git

**Disadvantages:**
- ⏱️ **Slower** - Requires Cypher parsing
- 🔧 **Complex data** - May need manual adjustments
- 📊 **Less complete** - May miss some metadata
- 🐛 **Potential errors** - Cypher syntax issues

**Best for:**
- Development and testing
- Version control
- Partial data migration
- Cross-version compatibility
- Code review and auditing

## 🚦 Best Practices

### Backup Strategy

**Daily Backups:**
```bash
# Cron job for daily binary backups
0 2 * * * cd /path/to/project && ./utilityScripts/backup-graph.sh --backup-dir ./backups/daily
```

**Weekly Exports:**
```bash
# Cron job for weekly Cypher exports
0 3 * * 0 cd /path/to/project && ./utilityScripts/export-graph.sh --export-dir ./backups/weekly
```

**Retention Policy:**
```bash
# Keep 7 daily backups
find ./backups/daily -type d -mtime +7 -exec rm -rf {} \;

# Keep 4 weekly exports
find ./backups/weekly -type d -mtime +28 -exec rm -rf {} \;
```

### Restore Workflow

**Safe Restore Process:**
```bash
# 1. Dry run to see what will happen
./utilityScripts/restore-graph.sh --backup-dir ./backups/binary-backup-2026-05-06-143022 --dry-run

# 2. Backup current state
./utilityScripts/backup-graph.sh --backup-dir ./backups/pre-restore-$(date +%Y%m%d)

# 3. Restore to test database first
./utilityScripts/restore-graph.sh --backup-dir ./backups/binary-backup-2026-05-06-143022 --database-name test-restore

# 4. Verify data integrity
# (Manual verification process)

# 5. If verified, restore to production
./utilityScripts/restore-graph.sh --backup-dir ./backups/binary-backup-2026-05-06-143022
```

### Migration Strategy

**Cross-Environment Migration:**
```bash
# 1. Export from source
./utilityScripts/export-graph.sh --database-name source-db --export-dir ./exports

# 2. Transfer export files to target environment
# (Copy ./exports to target server)

# 3. Import to target
./utilityScripts/import-graph.sh --import-dir ./exports/source-db-export-2026-05-06-143022 --database-name target-db --mode replace
```

## 🔍 Troubleshooting

### Common Issues

**Container Not Running:**
```
❌ Error: Neo4j container 'neo4j-llm-graph-builder' is not running
```
**Solution:** Start the container:
```bash
docker compose up -d neo4j
```

**Database Doesn't Exist:**
```
❌ Error: Database 'mydb' does not exist
```
**Solution:** Create the database first:
```bash
docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder "CREATE DATABASE mydb WAIT"
```

**Write Privilege Errors:**
```
⚠ Warning: Could not grant write privileges
```
**Solution:** Manually grant privileges:
```bash
docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder "GRANT WRITE ON GRAPH mydb TO admin"
```

**APOC Export Fails:**
```
⚠ APOC export not available, using manual export...
```
**Solution:** This is a fallback that still works. If you want faster exports, ensure APOC plugin is installed.

**Disk Space Issues:**
```
❌ Error: No space left on device
```
**Solution:** Clean up old backups:
```bash
find ./backups -type d -mtime +30 -exec rm -rf {} \;
```

### Debug Mode

For detailed debugging, run scripts with bash debug mode:
```bash
bash -x ./utilityScripts/backup-graph.sh
```

### Log Files

Check container logs for detailed error information:
```bash
docker logs neo4j-llm-graph-builder
```

## 🤖 Automation

### Cron Jobs

**Daily Backup (2 AM):**
```bash
0 2 * * * cd /home/user/llm-graph-builder && ./utilityScripts/backup-graph.sh --backup-dir ./backups/daily >> /var/log/graph-backup.log 2>&1
```

**Weekly Export (3 AM on Sunday):**
```bash
0 3 * * 0 cd /home/user/llm-graph-builder && ./utilityScripts/export-graph.sh --export-dir ./backups/weekly >> /var/log/graph-export.log 2>&1
```

### Systemd Timers

**Create systemd service file:** `/etc/systemd/system/graph-backup.service`
```ini
[Unit]
Description=Neo4j Knowledge Graph Backup
After=docker.service

[Service]
Type=oneshot
User=youruser
WorkingDirectory=/home/user/llm-graph-builder
ExecStart=/home/user/llm-graph-builder/utilityScripts/backup-graph.sh --backup-dir ./backups/daily
StandardOutput=append:/var/log/graph-backup.log
StandardError=append:/var/log/graph-backup.log
```

**Create systemd timer file:** `/etc/systemd/system/graph-backup.timer`
```ini
[Unit]
Description=Daily Neo4j Knowledge Graph Backup

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

**Enable the timer:**
```bash
sudo systemctl enable graph-backup.timer
sudo systemctl start graph-backup.timer
```

### Monitoring

**Backup Health Check:**
```bash
#!/bin/bash
# Check if latest backup is recent
LATEST_BACKUP=$(ls -t ./backups/daily/binary-backup-* 2>/dev/null | head -1)
if [ -z "$LATEST_BACKUP" ]; then
    echo "WARNING: No backups found!"
    exit 1
fi

BACKUP_AGE=$(( ($(date +%s) - $(stat -c %Y "$LATEST_BACKUP")) / 86400 ))
if [ "$BACKUP_AGE" -gt 2 ]; then
    echo "WARNING: Latest backup is $BACKUP_AGE days old!"
    exit 1
fi

echo "OK: Latest backup is recent"
exit 0
```

## 📊 Backup Manifest Format

### Binary Backup Manifest
```json
{
    "backup_type": "binary",
    "database_name": "theblackbookofpower",
    "timestamp": "2026-05-06T14:30:22Z",
    "timestamp_local": "Wed May  6 10:30:22 EDT 2026",
    "node_count": 1234,
    "relationship_count": 5678,
    "backup_path": "./backups/binary-backup-2026-05-06-143022",
    "container_name": "neo4j-llm-graph-builder",
    "neo4j_version": "neo4j version 5.26.0"
}
```

### Cypher Export Manifest
```json
{
    "export_type": "cypher",
    "database_name": "theblackbookofpower",
    "timestamp": "2026-05-06T14:30:22Z",
    "timestamp_local": "Wed May  6 10:30:22 EDT 2026",
    "node_count": 1234,
    "relationship_count": 5678,
    "export_path": "./backups/cypher-exports/theblackbookofpower-export-2026-05-06-143022",
    "export_file": "./backups/cypher-exports/theblackbookofpower-export-2026-05-06-143022/theblackbookofpower-export-2026-05-06-143022.cypher",
    "labels_filtered": "none",
    "container_name": "neo4j-llm-graph-builder"
}
```

## 🚨 Disaster Recovery

### Complete Recovery Process

**1. Assess the Situation:**
```bash
# Check container status
docker ps -a | grep neo4j

# Check data volume
docker volume ls | grep neo4j

# Check available backups
ls -la ./backups/
```

**2. Restore from Latest Binary Backup:**
```bash
# Find latest binary backup
LATEST_BACKUP=$(ls -t ./backups/binary-backup-* 2>/dev/null | head -1)

# Restore with full safety features
./utilityScripts/restore-graph.sh --backup-dir "$LATEST_BACKUP"
```

**3. Verify Data Integrity:**
```bash
# Check database statistics
docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder -d theblackbookofpower "MATCH (n) RETURN count(n)"
docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder -d theblackbookofpower "MATCH ()-[r]->() RETURN count(r)"

# Verify sample data
docker exec neo4j-llm-graph-builder cypher-shell -u neo4j -p llmgraphbuilder -d theblackbookofpower "MATCH (n) RETURN n LIMIT 5"
```

**4. Test Application Functionality:**
- Access application UI
- Try basic operations
- Verify graph visualization
- Test chat functionality

### Partial Recovery

If only some data is corrupted, you can:

**Export clean data:**
```bash
./utilityScripts/export-graph.sh --labels Document,Person --export-dir ./clean-data
```

**Import to fresh database:**
```bash
./utilityScripts/import-graph.sh --import-dir ./clean-data --database-name recovered-db --mode replace
```

## 📚 Additional Resources

### Neo4j Documentation
- [Neo4j Backup and Restore](https://neo4j.com/docs/operations-manual/current/backup-restore/)
- [neo4j-admin Commands](https://neo4j.com/docs/operations-manual/current/tools/neo4j-admin/)
- [APOC Procedures](https://neo4j.com/labs/apoc/4.4/)

### Docker Documentation
- [Docker Volume Management](https://docs.docker.com/storage/volumes/)
- [Docker Container Lifecycle](https://docs.docker.com/engine/reference/commandline/container/)

## 🤝 Contributing

These scripts are designed to be robust and safe. If you find issues or have suggestions for improvements:

1. Test changes thoroughly in a non-production environment
2. Add appropriate error handling
3. Update this README with any new features
4. Maintain backward compatibility

## 📄 License

These utilities are part of the LLM Graph Builder project and follow the same license terms.

## 🎯 Summary

- **Binary Backup**: Fast, complete, Enterprise only, requires downtime
- **Cypher Export**: Portable, human-readable, no downtime, cross-version
- **Safety Features**: Comprehensive warnings, confirmations, and dry-run mode
- **Automation**: Ready for cron jobs and systemd timers
- **Disaster Recovery**: Complete recovery procedures included

Choose the backup method that best fits your use case, and always test your restore procedures!

**Remember: A backup is only as good as its restore!** 🔄
