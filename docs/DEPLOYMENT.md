# n8n Workflow Deployment Guide

This guide covers deployment strategies for n8n workflows in different environments.

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Local Development](#local-development)
3. [Staging Deployment](#staging-deployment)
4. [Production Deployment](#production-deployment)
5. [Kubernetes Deployment](#kubernetes-deployment)
6. [Backup and Restore](#backup-and-restore)
7. [Monitoring Setup](#monitoring-setup)

## Prerequisites

### Required Tools
- Docker and Docker Compose
- Git
- kubectl (for Kubernetes deployment)
- jq (for JSON processing)
- openssl (for generating secrets)

### Required Services
- PostgreSQL database
- Redis instance
- AI Brain API access
- (Optional) Ollama instance
- (Optional) FlameVault access

### Generate Secrets

```bash
# Generate encryption key
openssl rand -hex 32

# Generate webhook secret
openssl rand -hex 32

# Generate strong passwords
openssl rand -base64 32
```

## 🖥️ Local Development

### 1. Clone Repository

```bash
git clone https://github.com/FlameCoreAI/FlameVault.git
cd FlameVault
```

### 2. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit with your values
nano .env
```

Required environment variables:
```bash
N8N_ENCRYPTION_KEY=<your-encryption-key>
N8N_BASIC_AUTH_PASSWORD=<your-password>
POSTGRES_PASSWORD=<postgres-password>
REDIS_PASSWORD=<redis-password>
WEBHOOK_SECRET=<webhook-secret>
AI_BRAIN_URL=<ai-brain-url>
AI_BRAIN_API_KEY=<ai-brain-api-key>
```

### 3. Start Services

```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f n8n
```

### 4. Access n8n

Open browser to: `http://localhost:5678`

Login with credentials from `.env`:
- Username: `admin` (or your configured user)
- Password: From `N8N_BASIC_AUTH_PASSWORD`

### 5. Import Workflows

```bash
# Import via CLI
docker exec flamevault-n8n n8n import:workflow --input=/workflows/ai-brain-request-handler.json

# Or use n8n UI:
# - Go to Workflows → Import from File
# - Select workflow JSON
# - Configure credentials
# - Activate workflow
```

### 6. Configure Credentials

In n8n UI:
1. Go to **Credentials** → **New**
2. Add required credentials:
   - Redis Credentials
   - AI Brain API Key
   - Slack Webhook (optional)

### 7. Test Workflow

```bash
# Test webhook
MESSAGE='{"message":"test message"}'
SIGNATURE=$(echo -n "$MESSAGE" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -hex | cut -d' ' -f2)

curl -X POST http://localhost:5678/webhook/ai-brain-webhook \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -d "$MESSAGE"
```

## 🏗️ Staging Deployment

### 1. Prepare Staging Environment

```bash
# Set up staging server
ssh staging.example.com

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 2. Clone and Configure

```bash
# Clone repository
git clone https://github.com/FlameCoreAI/FlameVault.git
cd FlameVault

# Checkout staging branch
git checkout staging

# Configure environment
cp .env.example .env
nano .env
```

Update staging-specific values:
```bash
N8N_HOST=staging-n8n.example.com
N8N_PROTOCOL=https
AI_BRAIN_URL=https://staging-ai-brain.example.com
```

### 3. Set Up SSL/TLS

```bash
# Using Let's Encrypt with Certbot
sudo apt-get update
sudo apt-get install certbot

# Generate certificate
sudo certbot certonly --standalone -d staging-n8n.example.com
```

Add to `docker-compose.yml`:
```yaml
n8n:
  volumes:
    - /etc/letsencrypt:/etc/letsencrypt:ro
  environment:
    - N8N_SSL_KEY=/etc/letsencrypt/live/staging-n8n.example.com/privkey.pem
    - N8N_SSL_CERT=/etc/letsencrypt/live/staging-n8n.example.com/fullchain.pem
```

### 4. Deploy

```bash
# Start services
docker-compose up -d

# Import workflows
for workflow in workflows/*.json; do
  docker exec flamevault-n8n n8n import:workflow --input=/workflows/$(basename $workflow)
done

# Verify
curl https://staging-n8n.example.com/healthz
```

### 5. Configure Monitoring

```bash
# Set up log aggregation
docker-compose logs -f n8n | tee -a /var/log/n8n/n8n.log

# Set up metrics collection
# (Configure Prometheus scraping)
```

## 🚀 Production Deployment

### 1. Infrastructure Preparation

```bash
# Production checklist:
# - [ ] High-availability setup (3+ nodes)
# - [ ] Load balancer configured
# - [ ] Database backups enabled
# - [ ] SSL/TLS certificates
# - [ ] Firewall rules configured
# - [ ] Monitoring and alerting
# - [ ] Disaster recovery plan
```

### 2. Deploy with High Availability

Update `docker-compose.yml` for production:

```yaml
services:
  n8n:
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
        max_attempts: 3
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
```

### 3. Database Configuration

Use managed database service:

```bash
# Update .env for managed PostgreSQL
DB_POSTGRESDB_HOST=prod-postgres.example.com
DB_POSTGRESDB_SSL=true
```

### 4. Redis Configuration

Use managed Redis with persistence:

```bash
# Update .env for managed Redis
REDIS_HOST=prod-redis.example.com
REDIS_SSL=true
```

### 5. Load Balancer Setup

Nginx configuration:

```nginx
upstream n8n {
    least_conn;
    server n8n-1:5678;
    server n8n-2:5678;
    server n8n-3:5678;
}

server {
    listen 443 ssl http2;
    server_name n8n.example.com;

    ssl_certificate /etc/ssl/certs/n8n.crt;
    ssl_certificate_key /etc/ssl/private/n8n.key;

    location / {
        proxy_pass http://n8n;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 6. Deploy Production

```bash
# Deploy with zero downtime
docker-compose up -d --no-deps --build n8n

# Verify health
for i in {1..3}; do
  docker exec flamevault-n8n-$i wget -O- http://localhost:5678/healthz
done

# Import workflows
docker exec flamevault-n8n-1 n8n import:workflow --input=/workflows/ai-brain-request-handler.json
```

## ☸️ Kubernetes Deployment

### 1. Create Namespace

```bash
kubectl create namespace n8n-production
```

### 2. Create Secrets

```bash
# Create secret from .env
kubectl create secret generic n8n-secrets \
  --from-env-file=.env \
  -n n8n-production

# Verify
kubectl get secrets -n n8n-production
```

### 3. Deploy PostgreSQL

```yaml
# postgres-deployment.yml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: n8n-production
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_DB
          value: n8n
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: n8n-secrets
              key: POSTGRES_USER
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: n8n-secrets
              key: POSTGRES_PASSWORD
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 20Gi
```

### 4. Deploy n8n

```yaml
# n8n-deployment.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: n8n
  namespace: n8n-production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      containers:
      - name: n8n
        image: n8nio/n8n:latest
        envFrom:
        - secretRef:
            name: n8n-secrets
        ports:
        - containerPort: 5678
        volumeMounts:
        - name: workflows
          mountPath: /workflows
        - name: n8n-data
          mountPath: /home/node/.n8n
        livenessProbe:
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /healthz
            port: 5678
          initialDelaySeconds: 15
          periodSeconds: 5
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 2
            memory: 2Gi
      volumes:
      - name: workflows
        configMap:
          name: n8n-workflows
      - name: n8n-data
        persistentVolumeClaim:
          claimName: n8n-data
---
apiVersion: v1
kind: Service
metadata:
  name: n8n
  namespace: n8n-production
spec:
  selector:
    app: n8n
  ports:
  - port: 5678
    targetPort: 5678
  type: LoadBalancer
```

### 5. Create ConfigMap for Workflows

```bash
kubectl create configmap n8n-workflows \
  --from-file=workflows/ \
  -n n8n-production
```

### 6. Deploy

```bash
# Apply all manifests
kubectl apply -f k8s/

# Check status
kubectl get pods -n n8n-production
kubectl logs -f deployment/n8n -n n8n-production

# Get service URL
kubectl get svc n8n -n n8n-production
```

### 7. Set Up Ingress

```yaml
# n8n-ingress.yml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n
  namespace: n8n-production
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - n8n.example.com
    secretName: n8n-tls
  rules:
  - host: n8n.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: n8n
            port:
              number: 5678
```

## 💾 Backup and Restore

### Automated Backups

```bash
#!/bin/bash
# backup-workflows.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backup/workflows/$DATE"

mkdir -p "$BACKUP_DIR"

# Export all workflows
docker exec flamevault-n8n n8n export:workflow --all --output=/backup/workflows.json

# Copy to backup location
docker cp flamevault-n8n:/backup/workflows.json "$BACKUP_DIR/"

# Backup database
docker exec flamevault-postgres pg_dump -U n8n n8n > "$BACKUP_DIR/database.sql"

# Compress
tar czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"

# Upload to S3 (optional)
aws s3 cp "$BACKUP_DIR.tar.gz" s3://flamevault-backups/n8n/

echo "Backup completed: $BACKUP_DIR.tar.gz"
```

Schedule with cron:
```bash
# Run daily at 2 AM
0 2 * * * /opt/scripts/backup-workflows.sh
```

### Restore Procedure

```bash
#!/bin/bash
# restore-workflows.sh

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup-file>"
  exit 1
fi

# Extract backup
tar xzf "$BACKUP_FILE"
BACKUP_DIR=$(basename "$BACKUP_FILE" .tar.gz)

# Restore database
docker exec -i flamevault-postgres psql -U n8n n8n < "$BACKUP_DIR/database.sql"

# Import workflows
docker exec flamevault-n8n n8n import:workflow --separate --input=/backup/workflows.json

echo "Restore completed from $BACKUP_FILE"
```

## 📊 Monitoring Setup

### Prometheus Metrics

Create metrics endpoint:

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: '/metrics'
    scrape_interval: 30s
```

### Grafana Dashboard

Import dashboard for n8n metrics:
- Workflow execution count
- Error rates
- Execution duration
- Queue depth
- Resource usage

### Alerting

```yaml
# alertmanager.yml
route:
  receiver: 'slack-notifications'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'

receivers:
  - name: 'slack-notifications'
    slack_configs:
      - api_url: '{{ SLACK_WEBHOOK_URL }}'
        channel: '#n8n-alerts'
        
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '{{ PAGERDUTY_KEY }}'
```

## 🔄 CI/CD Integration

GitHub Actions automatically validates and deploys workflows. See `.github/workflows/n8n-validation.yml`.

Manual deployment trigger:

```bash
# Trigger deployment
gh workflow run n8n-validation.yml \
  --ref main \
  -f environment=production
```

## 📋 Post-Deployment Checklist

- [ ] All workflows imported successfully
- [ ] Credentials configured and tested
- [ ] Health checks passing
- [ ] Monitoring and alerting configured
- [ ] Backups running
- [ ] Documentation updated
- [ ] Team notified
- [ ] Runbook reviewed
- [ ] Test webhook endpoints
- [ ] Verify integrations (AI Brain, Redis, etc.)

## 🆘 Rollback Procedure

If deployment fails:

```bash
# Rollback to previous version
docker-compose down
git checkout <previous-commit>
docker-compose up -d

# Restore from backup if needed
./restore-workflows.sh /backup/workflows/latest.tar.gz

# Verify rollback
curl https://n8n.example.com/healthz
```

## 📞 Support

For deployment issues:
- Check [Runbook](../runbooks/workflow-failures.md)
- Review [Workflow Checklist](../../WORKFLOW_CHECKLIST.md)
- Contact DevOps team
- Open GitHub issue

## 🔗 References

- [n8n Deployment Guide](https://docs.n8n.io/hosting/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
