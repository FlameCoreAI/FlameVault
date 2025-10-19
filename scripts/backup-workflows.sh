#!/bin/bash
# backup-workflows.sh
# Automated backup script for n8n workflows and database

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backup/workflows}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
S3_BUCKET="${S3_BUCKET:-}"
CONTAINER_NAME="${CONTAINER_NAME:-flamevault-n8n}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-flamevault-postgres}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
POSTGRES_USER="${POSTGRES_USER:-n8n}"

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

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

# Check if required tools are available
check_requirements() {
    local missing=0
    
    if ! command -v docker &> /dev/null; then
        log_error "docker is not installed"
        missing=1
    fi
    
    if [ -n "$S3_BUCKET" ] && ! command -v aws &> /dev/null; then
        log_error "aws cli is not installed but S3_BUCKET is configured"
        missing=1
    fi
    
    return $missing
}

# Create backup directory
create_backup_dir() {
    log_info "Creating backup directory: $BACKUP_PATH"
    mkdir -p "$BACKUP_PATH"
}

# Export n8n workflows
export_workflows() {
    log_info "Exporting n8n workflows..."
    
    if docker ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        docker exec "$CONTAINER_NAME" n8n export:workflow \
            --all \
            --output=/tmp/workflows-backup.json 2>&1 || {
            log_error "Failed to export workflows"
            return 1
        }
        
        docker cp "$CONTAINER_NAME:/tmp/workflows-backup.json" "$BACKUP_PATH/workflows.json"
        log_info "Workflows exported successfully"
    else
        log_error "Container $CONTAINER_NAME is not running"
        return 1
    fi
}

# Export individual workflow files
export_workflow_files() {
    log_info "Copying workflow files from repository..."
    
    if [ -d "workflows" ]; then
        cp -r workflows "$BACKUP_PATH/"
        log_info "Workflow files copied"
    else
        log_warn "No workflows directory found"
    fi
}

# Backup PostgreSQL database
backup_database() {
    log_info "Backing up PostgreSQL database..."
    
    if docker ps --format '{{.Names}}' | grep -q "^$POSTGRES_CONTAINER$"; then
        docker exec "$POSTGRES_CONTAINER" pg_dump \
            -U "$POSTGRES_USER" \
            "$POSTGRES_DB" \
            > "$BACKUP_PATH/database.sql" 2>&1 || {
            log_error "Failed to backup database"
            return 1
        }
        
        log_info "Database backed up successfully"
    else
        log_error "Container $POSTGRES_CONTAINER is not running"
        return 1
    fi
}

# Backup n8n data directory
backup_n8n_data() {
    log_info "Backing up n8n data directory..."
    
    if docker ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        docker exec "$CONTAINER_NAME" tar czf /tmp/n8n-data.tar.gz \
            -C /home/node/.n8n . 2>&1 || {
            log_warn "Failed to backup n8n data directory (may not exist)"
            return 0
        }
        
        docker cp "$CONTAINER_NAME:/tmp/n8n-data.tar.gz" "$BACKUP_PATH/n8n-data.tar.gz"
        log_info "n8n data directory backed up"
    else
        log_error "Container $CONTAINER_NAME is not running"
        return 1
    fi
}

# Create metadata file
create_metadata() {
    log_info "Creating backup metadata..."
    
    cat > "$BACKUP_PATH/metadata.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "$(hostname)",
  "n8n_version": "$(docker exec "$CONTAINER_NAME" n8n --version 2>/dev/null || echo 'unknown')",
  "backup_components": [
    "workflows",
    "database",
    "n8n_data"
  ]
}
EOF
    
    log_info "Metadata created"
}

# Compress backup
compress_backup() {
    log_info "Compressing backup..."
    
    tar czf "$BACKUP_DIR/${TIMESTAMP}.tar.gz" -C "$BACKUP_DIR" "$TIMESTAMP"
    
    if [ $? -eq 0 ]; then
        rm -rf "$BACKUP_PATH"
        log_info "Backup compressed: ${TIMESTAMP}.tar.gz"
    else
        log_error "Failed to compress backup"
        return 1
    fi
}

# Upload to S3 (if configured)
upload_to_s3() {
    if [ -z "$S3_BUCKET" ]; then
        log_info "S3_BUCKET not configured, skipping upload"
        return 0
    fi
    
    log_info "Uploading backup to S3: $S3_BUCKET"
    
    aws s3 cp "$BACKUP_DIR/${TIMESTAMP}.tar.gz" \
        "s3://$S3_BUCKET/n8n-backups/${TIMESTAMP}.tar.gz" \
        --storage-class STANDARD_IA || {
        log_error "Failed to upload to S3"
        return 1
    }
    
    log_info "Backup uploaded to S3 successfully"
}

# Clean old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than $RETENTION_DAYS days..."
    
    find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +"$RETENTION_DAYS" -delete
    
    local deleted_count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +"$RETENTION_DAYS" | wc -l)
    log_info "Cleaned up $deleted_count old backup(s)"
    
    # Clean S3 if configured
    if [ -n "$S3_BUCKET" ]; then
        log_info "Cleaning up old S3 backups..."
        
        local cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d)
        
        aws s3 ls "s3://$S3_BUCKET/n8n-backups/" | \
            awk '{print $4}' | \
            while read -r file; do
                local file_date=$(echo "$file" | grep -oP '^\d{8}')
                if [ -n "$file_date" ] && [ "$file_date" -lt "$cutoff_date" ]; then
                    aws s3 rm "s3://$S3_BUCKET/n8n-backups/$file"
                    log_info "Deleted old S3 backup: $file"
                fi
            done
    fi
}

# Verify backup integrity
verify_backup() {
    log_info "Verifying backup integrity..."
    
    if tar tzf "$BACKUP_DIR/${TIMESTAMP}.tar.gz" > /dev/null 2>&1; then
        log_info "Backup integrity verified"
    else
        log_error "Backup integrity check failed"
        return 1
    fi
}

# Send notification (optional)
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
                    \"title\": \"$emoji n8n Backup $status\",
                    \"text\": \"$message\",
                    \"fields\": [
                        {
                            \"title\": \"Timestamp\",
                            \"value\": \"$TIMESTAMP\",
                            \"short\": true
                        },
                        {
                            \"title\": \"Hostname\",
                            \"value\": \"$(hostname)\",
                            \"short\": true
                        }
                    ],
                    \"footer\": \"n8n Backup Script\",
                    \"ts\": $(date +%s)
                }]
            }" 2>&1 > /dev/null || log_warn "Failed to send Slack notification"
    fi
}

# Main execution
main() {
    log_info "Starting n8n backup process..."
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Retention: $RETENTION_DAYS days"
    
    # Check requirements
    if ! check_requirements; then
        log_error "Requirements check failed"
        send_notification "failed" "Requirements check failed"
        exit 1
    fi
    
    # Create backup directory
    create_backup_dir || {
        log_error "Failed to create backup directory"
        send_notification "failed" "Failed to create backup directory"
        exit 1
    }
    
    # Export workflows
    export_workflows || {
        log_error "Failed to export workflows"
        send_notification "failed" "Failed to export workflows"
        exit 1
    }
    
    # Copy workflow files
    export_workflow_files
    
    # Backup database
    backup_database || {
        log_error "Failed to backup database"
        send_notification "failed" "Failed to backup database"
        exit 1
    }
    
    # Backup n8n data
    backup_n8n_data
    
    # Create metadata
    create_metadata
    
    # Compress backup
    compress_backup || {
        log_error "Failed to compress backup"
        send_notification "failed" "Failed to compress backup"
        exit 1
    }
    
    # Verify backup
    verify_backup || {
        log_error "Backup verification failed"
        send_notification "failed" "Backup verification failed"
        exit 1
    }
    
    # Upload to S3
    upload_to_s3
    
    # Cleanup old backups
    cleanup_old_backups
    
    log_info "Backup completed successfully: ${TIMESTAMP}.tar.gz"
    
    # Send success notification
    send_notification "success" "Backup completed successfully: ${TIMESTAMP}.tar.gz"
}

# Run main function
main "$@"
