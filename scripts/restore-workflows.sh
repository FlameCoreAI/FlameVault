#!/bin/bash
# restore-workflows.sh
# Restore script for n8n workflows and database

set -euo pipefail

# Configuration
BACKUP_FILE="${1:-}"
CONTAINER_NAME="${CONTAINER_NAME:-flamevault-n8n}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-flamevault-postgres}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
POSTGRES_USER="${POSTGRES_USER:-n8n}"
RESTORE_WORKFLOWS="${RESTORE_WORKFLOWS:-true}"
RESTORE_DATABASE="${RESTORE_DATABASE:-true}"
RESTORE_N8N_DATA="${RESTORE_N8N_DATA:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show usage
usage() {
    cat <<EOF
Usage: $0 <backup-file>

Restore n8n workflows and database from backup.

Arguments:
  backup-file    Path to backup tar.gz file

Environment Variables:
  CONTAINER_NAME       n8n container name (default: flamevault-n8n)
  POSTGRES_CONTAINER   PostgreSQL container name (default: flamevault-postgres)
  POSTGRES_DB          Database name (default: n8n)
  POSTGRES_USER        Database user (default: n8n)
  RESTORE_WORKFLOWS    Restore workflows (default: true)
  RESTORE_DATABASE     Restore database (default: true)
  RESTORE_N8N_DATA     Restore n8n data directory (default: false)

Examples:
  # Restore everything
  $0 /backup/workflows/20251019_120000.tar.gz

  # Restore only workflows
  RESTORE_DATABASE=false $0 /backup/workflows/20251019_120000.tar.gz

  # Restore only database
  RESTORE_WORKFLOWS=false $0 /backup/workflows/20251019_120000.tar.gz

EOF
}

# Validate arguments
validate_args() {
    if [ -z "$BACKUP_FILE" ]; then
        log_error "No backup file specified"
        usage
        exit 1
    fi
    
    if [ ! -f "$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    if ! tar tzf "$BACKUP_FILE" > /dev/null 2>&1; then
        log_error "Invalid backup file (not a valid tar.gz)"
        exit 1
    fi
}

# Check if containers are running
check_containers() {
    log_info "Checking container status..."
    
    if [ "$RESTORE_WORKFLOWS" = "true" ] && ! docker ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        log_error "Container $CONTAINER_NAME is not running"
        exit 1
    fi
    
    if [ "$RESTORE_DATABASE" = "true" ] && ! docker ps --format '{{.Names}}' | grep -q "^$POSTGRES_CONTAINER$"; then
        log_error "Container $POSTGRES_CONTAINER is not running"
        exit 1
    fi
    
    log_info "All required containers are running"
}

# Create temporary directory
create_temp_dir() {
    TEMP_DIR=$(mktemp -d)
    log_info "Created temporary directory: $TEMP_DIR"
    
    # Cleanup on exit
    trap "rm -rf $TEMP_DIR" EXIT
}

# Extract backup
extract_backup() {
    log_info "Extracting backup file..."
    
    tar xzf "$BACKUP_FILE" -C "$TEMP_DIR" || {
        log_error "Failed to extract backup"
        exit 1
    }
    
    # Find the backup directory (should be a timestamp directory)
    BACKUP_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "[0-9]*" | head -1)
    
    if [ -z "$BACKUP_DIR" ]; then
        log_error "Could not find backup directory in archive"
        exit 1
    fi
    
    log_info "Backup extracted to: $BACKUP_DIR"
}

# Show backup metadata
show_metadata() {
    if [ -f "$BACKUP_DIR/metadata.json" ]; then
        log_info "Backup metadata:"
        cat "$BACKUP_DIR/metadata.json" | jq '.'
    else
        log_warn "No metadata file found in backup"
    fi
}

# Confirm restore
confirm_restore() {
    log_warn "This will restore data from backup and may overwrite existing data!"
    log_warn "Backup file: $BACKUP_FILE"
    
    if [ "$RESTORE_WORKFLOWS" = "true" ]; then
        log_warn "  - Workflows will be restored"
    fi
    
    if [ "$RESTORE_DATABASE" = "true" ]; then
        log_warn "  - Database will be restored"
    fi
    
    if [ "$RESTORE_N8N_DATA" = "true" ]; then
        log_warn "  - n8n data directory will be restored"
    fi
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r response
    
    if [ "$response" != "yes" ]; then
        log_info "Restore cancelled"
        exit 0
    fi
}

# Create backup of current state
backup_current_state() {
    log_info "Creating backup of current state..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="/backup/pre-restore-$timestamp"
    
    mkdir -p "$backup_dir"
    
    # Quick backup
    if [ "$RESTORE_WORKFLOWS" = "true" ]; then
        docker exec "$CONTAINER_NAME" n8n export:workflow \
            --all \
            --output=/tmp/current-workflows.json 2>/dev/null || true
        docker cp "$CONTAINER_NAME:/tmp/current-workflows.json" \
            "$backup_dir/workflows.json" 2>/dev/null || true
    fi
    
    if [ "$RESTORE_DATABASE" = "true" ]; then
        docker exec "$POSTGRES_CONTAINER" pg_dump \
            -U "$POSTGRES_USER" "$POSTGRES_DB" \
            > "$backup_dir/database.sql" 2>/dev/null || true
    fi
    
    log_info "Current state backed up to: $backup_dir"
}

# Restore workflows
restore_workflows() {
    if [ "$RESTORE_WORKFLOWS" != "true" ]; then
        log_info "Skipping workflow restore"
        return 0
    fi
    
    log_info "Restoring workflows..."
    
    if [ -f "$BACKUP_DIR/workflows.json" ]; then
        # Copy to container
        docker cp "$BACKUP_DIR/workflows.json" "$CONTAINER_NAME:/tmp/workflows-restore.json"
        
        # Import workflows
        docker exec "$CONTAINER_NAME" n8n import:workflow \
            --separate \
            --input=/tmp/workflows-restore.json || {
            log_error "Failed to import workflows"
            return 1
        }
        
        log_info "Workflows restored successfully"
    else
        log_warn "No workflows file found in backup"
    fi
}

# Restore database
restore_database() {
    if [ "$RESTORE_DATABASE" != "true" ]; then
        log_info "Skipping database restore"
        return 0
    fi
    
    log_info "Restoring database..."
    
    if [ -f "$BACKUP_DIR/database.sql" ]; then
        # Stop n8n to prevent conflicts
        log_info "Stopping n8n temporarily..."
        docker stop "$CONTAINER_NAME" || true
        
        # Drop and recreate database
        log_info "Recreating database..."
        docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -c "DROP DATABASE IF EXISTS $POSTGRES_DB;" postgres
        docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -c "CREATE DATABASE $POSTGRES_DB;" postgres
        
        # Restore database
        docker exec -i "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" "$POSTGRES_DB" \
            < "$BACKUP_DIR/database.sql" || {
            log_error "Failed to restore database"
            docker start "$CONTAINER_NAME"
            return 1
        }
        
        # Start n8n
        log_info "Starting n8n..."
        docker start "$CONTAINER_NAME"
        
        # Wait for n8n to be ready
        log_info "Waiting for n8n to be ready..."
        for i in {1..30}; do
            if docker exec "$CONTAINER_NAME" wget -q -O- http://localhost:5678/healthz > /dev/null 2>&1; then
                log_info "n8n is ready"
                break
            fi
            sleep 2
        done
        
        log_info "Database restored successfully"
    else
        log_warn "No database file found in backup"
    fi
}

# Restore n8n data directory
restore_n8n_data() {
    if [ "$RESTORE_N8N_DATA" != "true" ]; then
        log_info "Skipping n8n data directory restore"
        return 0
    fi
    
    log_info "Restoring n8n data directory..."
    
    if [ -f "$BACKUP_DIR/n8n-data.tar.gz" ]; then
        # Stop n8n
        log_info "Stopping n8n..."
        docker stop "$CONTAINER_NAME"
        
        # Copy and extract
        docker cp "$BACKUP_DIR/n8n-data.tar.gz" "$CONTAINER_NAME:/tmp/n8n-data.tar.gz"
        docker exec "$CONTAINER_NAME" sh -c "rm -rf /home/node/.n8n/* && tar xzf /tmp/n8n-data.tar.gz -C /home/node/.n8n"
        
        # Start n8n
        log_info "Starting n8n..."
        docker start "$CONTAINER_NAME"
        
        log_info "n8n data directory restored successfully"
    else
        log_warn "No n8n data file found in backup"
    fi
}

# Verify restore
verify_restore() {
    log_info "Verifying restore..."
    
    if [ "$RESTORE_WORKFLOWS" = "true" ]; then
        # Check if workflows exist
        if docker exec "$CONTAINER_NAME" n8n list:workflow 2>&1 | grep -q "Found"; then
            log_info "Workflows verified"
        else
            log_warn "Could not verify workflows"
        fi
    fi
    
    if [ "$RESTORE_DATABASE" = "true" ]; then
        # Check database connection
        if docker exec "$POSTGRES_CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" > /dev/null 2>&1; then
            log_info "Database connection verified"
        else
            log_error "Database connection failed"
            return 1
        fi
    fi
}

# Send notification
send_notification() {
    local status=$1
    local message=$2
    
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        local color="good"
        local emoji=":white_check_mark:"
        
        if [ "$status" != "success" ]; then
            color="danger"
            emoji=":x:"
        fi
        
        curl -X POST "$SLACK_WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{
                \"attachments\": [{
                    \"color\": \"$color\",
                    \"title\": \"$emoji n8n Restore $status\",
                    \"text\": \"$message\",
                    \"fields\": [
                        {
                            \"title\": \"Backup File\",
                            \"value\": \"$(basename $BACKUP_FILE)\",
                            \"short\": true
                        },
                        {
                            \"title\": \"Hostname\",
                            \"value\": \"$(hostname)\",
                            \"short\": true
                        }
                    ],
                    \"footer\": \"n8n Restore Script\",
                    \"ts\": $(date +%s)
                }]
            }" 2>&1 > /dev/null || log_warn "Failed to send Slack notification"
    fi
}

# Main execution
main() {
    log_info "Starting n8n restore process..."
    log_info "Backup file: $BACKUP_FILE"
    
    # Validate arguments
    validate_args
    
    # Check containers
    check_containers
    
    # Create temp directory
    create_temp_dir
    
    # Extract backup
    extract_backup
    
    # Show metadata
    show_metadata
    
    # Confirm restore
    confirm_restore
    
    # Backup current state
    backup_current_state
    
    # Restore workflows
    restore_workflows || {
        log_error "Failed to restore workflows"
        send_notification "failed" "Failed to restore workflows"
        exit 1
    }
    
    # Restore database
    restore_database || {
        log_error "Failed to restore database"
        send_notification "failed" "Failed to restore database"
        exit 1
    }
    
    # Restore n8n data
    restore_n8n_data || {
        log_error "Failed to restore n8n data"
        send_notification "failed" "Failed to restore n8n data"
        exit 1
    }
    
    # Verify restore
    verify_restore || {
        log_error "Restore verification failed"
        send_notification "failed" "Restore verification failed"
        exit 1
    }
    
    log_info "Restore completed successfully!"
    send_notification "success" "Restore completed successfully from $(basename $BACKUP_FILE)"
}

# Run main function
main "$@"
