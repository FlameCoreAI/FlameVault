# FlameVault Scripts

Operational scripts for managing n8n workflows and infrastructure.

## 📁 Available Scripts

### backup-workflows.sh

Automated backup script for n8n workflows, database, and data.

**Usage:**
```bash
./scripts/backup-workflows.sh
```

**Environment Variables:**
- `BACKUP_DIR` - Backup destination directory (default: `/backup/workflows`)
- `RETENTION_DAYS` - Number of days to keep backups (default: `30`)
- `S3_BUCKET` - Optional S3 bucket for remote backup
- `CONTAINER_NAME` - n8n container name (default: `flamevault-n8n`)
- `POSTGRES_CONTAINER` - PostgreSQL container name (default: `flamevault-postgres`)
- `SLACK_WEBHOOK_URL` - Optional Slack webhook for notifications

**Features:**
- ✅ Export all workflows from n8n
- ✅ Backup PostgreSQL database
- ✅ Backup n8n data directory
- ✅ Compress backups
- ✅ Upload to S3 (optional)
- ✅ Cleanup old backups
- ✅ Slack notifications
- ✅ Integrity verification

**Cron Setup:**
```bash
# Run daily at 2 AM
0 2 * * * /opt/FlameVault/scripts/backup-workflows.sh >> /var/log/n8n-backup.log 2>&1
```

### restore-workflows.sh

Restore script for recovering from backups.

**Usage:**
```bash
./scripts/restore-workflows.sh /backup/workflows/20251019_120000.tar.gz
```

**Environment Variables:**
- `CONTAINER_NAME` - n8n container name (default: `flamevault-n8n`)
- `POSTGRES_CONTAINER` - PostgreSQL container name (default: `flamevault-postgres`)
- `POSTGRES_DB` - Database name (default: `n8n`)
- `POSTGRES_USER` - Database user (default: `n8n`)
- `RESTORE_WORKFLOWS` - Restore workflows (default: `true`)
- `RESTORE_DATABASE` - Restore database (default: `true`)
- `RESTORE_N8N_DATA` - Restore n8n data directory (default: `false`)

**Features:**
- ✅ Restore workflows
- ✅ Restore database
- ✅ Restore n8n data directory
- ✅ Pre-restore backup of current state
- ✅ Confirmation prompt
- ✅ Verification of restored data
- ✅ Slack notifications

**Examples:**
```bash
# Restore everything
./scripts/restore-workflows.sh /backup/workflows/20251019_120000.tar.gz

# Restore only workflows
RESTORE_DATABASE=false ./scripts/restore-workflows.sh /backup/workflows/20251019_120000.tar.gz

# Restore only database
RESTORE_WORKFLOWS=false ./scripts/restore-workflows.sh /backup/workflows/20251019_120000.tar.gz
```

## 🔧 Script Development

### Adding New Scripts

1. Create script in `scripts/` directory
2. Make it executable: `chmod +x scripts/new-script.sh`
3. Add documentation to this README
4. Test thoroughly
5. Add to CI/CD if applicable

### Script Standards

- Use bash with `set -euo pipefail`
- Include usage/help function
- Add colored logging (info, warn, error)
- Validate inputs and requirements
- Include error handling
- Add notifications for critical operations
- Document environment variables

### Testing Scripts

```bash
# Test backup
./scripts/backup-workflows.sh

# Verify backup exists
ls -lh /backup/workflows/

# Test restore (use test backup)
./scripts/restore-workflows.sh /backup/workflows/test-backup.tar.gz
```

## 📊 Monitoring Scripts

Add monitoring for script execution:

```bash
# Log script execution
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") backup-workflows.sh started" >> /var/log/n8n-scripts.log

# Send metrics to Prometheus
cat <<EOF | curl --data-binary @- http://pushgateway:9091/metrics/job/backup/instance/$(hostname)
# TYPE backup_success gauge
backup_success 1
# TYPE backup_duration_seconds gauge
backup_duration_seconds $DURATION
EOF
```

## 🔒 Security Considerations

- Scripts should not contain hardcoded credentials
- Use environment variables for sensitive data
- Ensure backup files have proper permissions (600)
- Encrypt backups if storing sensitive data
- Audit script execution logs regularly

## 🚨 Troubleshooting

### Backup Script Issues

**"Container not running"**
- Verify containers are up: `docker ps`
- Start containers: `docker-compose up -d`

**"Permission denied"**
- Check file permissions: `ls -l scripts/`
- Make executable: `chmod +x scripts/backup-workflows.sh`

**"Disk space full"**
- Check disk space: `df -h`
- Clean old backups manually
- Adjust `RETENTION_DAYS`

### Restore Script Issues

**"Backup file not found"**
- Verify file path is correct
- Check file exists: `ls -lh /path/to/backup.tar.gz`

**"Database connection failed"**
- Verify PostgreSQL is running
- Check credentials in .env
- Review PostgreSQL logs

**"n8n not starting after restore"**
- Check n8n logs: `docker logs flamevault-n8n`
- Verify database connectivity
- Ensure proper file permissions

## 📝 Script Logs

View script execution logs:

```bash
# View backup logs
tail -f /var/log/n8n-backup.log

# View restore logs
# (output goes to stdout by default)

# View cron logs
grep CRON /var/log/syslog
```

## 🔗 Related Documentation

- [Deployment Guide](../docs/DEPLOYMENT.md)
- [Backup and Restore Section](../docs/DEPLOYMENT.md#backup-and-restore)
- [Runbook](../docs/runbooks/workflow-failures.md)

## 📞 Support

For script issues:
- Check logs first
- Review troubleshooting section
- Open GitHub issue
- Contact DevOps team
