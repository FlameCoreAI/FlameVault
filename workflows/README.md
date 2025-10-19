# FlameVault n8n Workflows

This directory contains production-ready n8n workflows for the FlameVault Multichannel stack integration.

## 📁 Directory Structure

```
workflows/
├── README.md                           # This file
├── ai-brain-request-handler.json      # Main AI Brain integration workflow
└── [other-workflow-name].json         # Additional workflows
```

## 🚀 Quick Start

### Prerequisites

- n8n instance (self-hosted or cloud)
- Redis instance for state management and idempotency
- Access to AI Brain API
- Credentials configured in n8n

### Import Workflows

1. Open n8n UI
2. Go to **Workflows** → **Import from File**
3. Select the workflow JSON file from this directory
4. Configure credentials (see Credentials section below)
5. Activate the workflow

### Using n8n CLI

```bash
# Import workflow
n8n import:workflow --input=workflows/ai-brain-request-handler.json

# Export workflow
n8n export:workflow --id=<workflow-id> --output=workflows/my-workflow.json

# List all workflows
n8n list:workflow
```

## 🔐 Credentials Configuration

Each workflow requires specific credentials to be configured in n8n. Follow these steps:

### 1. Redis Credentials

1. In n8n UI, go to **Credentials** → **New**
2. Select **Redis**
3. Configure:
   - **Name**: `Redis Credentials`
   - **Host**: `${REDIS_HOST}` (use environment variable)
   - **Port**: `${REDIS_PORT}` (default: 6379)
   - **Password**: `${REDIS_PASSWORD}`
   - **Database**: `0`

### 2. AI Brain API Key

1. In n8n UI, go to **Credentials** → **New**
2. Select **Header Auth**
3. Configure:
   - **Name**: `AI Brain API Key`
   - **Header Name**: `Authorization`
   - **Header Value**: `Bearer ${AI_BRAIN_API_KEY}`

### 3. Slack Webhook (for alerts)

1. In n8n UI, go to **Credentials** → **New**
2. Select **HTTP Request** (or use environment variable in workflow)
3. Configure:
   - **Name**: `Slack Webhook`
   - **URL**: `${SLACK_WEBHOOK_URL}`

## 🌍 Environment Variables

Set these environment variables in your n8n deployment:

```bash
# Core Configuration
N8N_HOST=your-n8n-domain.com
N8N_PROTOCOL=https
N8N_PORT=5678

# Webhook Security
WEBHOOK_SECRET=your-secure-secret-key-here

# AI Brain Integration
AI_BRAIN_URL=https://ai-brain.example.com
AI_BRAIN_API_KEY=your-api-key-here

# Redis Configuration
REDIS_HOST=redis.example.com
REDIS_PORT=6379
REDIS_PASSWORD=your-redis-password

# Ollama Configuration (if used)
OLLAMA_URL=http://ollama:11434
OLLAMA_MODEL=llama2

# Monitoring & Alerts
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
PROMETHEUS_PUSHGATEWAY=http://prometheus-pushgateway:9091

# FlameVault Integration
FLAMEVAULT_API_URL=https://api.flamevault.com
FLAMEVAULT_API_KEY=your-flamevault-key
```

### Using .env file

Create a `.env` file in your n8n deployment directory (DO NOT commit this file):

```bash
cp .env.example .env
# Edit .env with your actual values
```

## 📋 Workflows

### ai-brain-request-handler.json

**Purpose**: Handles incoming webhook requests, processes them through AI Brain, and returns structured responses.

**Features**:
- ✅ HMAC signature verification for webhook security
- ✅ Redis-based idempotency (prevents duplicate processing)
- ✅ Exponential backoff retry logic
- ✅ Dead letter queue for failed requests
- ✅ Slack alerts on failures
- ✅ Structured logging and metrics
- ✅ Proper error responses

**Trigger**: Webhook (POST `/ai-brain-webhook`)

**Input Schema**:
```json
{
  "requestId": "optional-unique-id",
  "message": "Your message to process",
  "metadata": {
    "userId": "user-123",
    "source": "web"
  }
}
```

**Output Schema (Success)**:
```json
{
  "success": true,
  "requestId": "uuid-v4",
  "data": {
    "response": "AI Brain processed response"
  },
  "timestamp": "2025-10-19T21:00:00.000Z",
  "metrics": {
    "workflow": "ai-brain-request-handler",
    "status": "success",
    "duration_ms": 1234
  }
}
```

**Output Schema (Error)**:
```json
{
  "success": false,
  "requestId": "uuid-v4",
  "error": "Request processing failed",
  "message": "Your request has been saved and will be retried"
}
```

**Dependencies**:
- Redis (idempotency, DLQ)
- AI Brain API
- Slack (optional, for alerts)

**Error Handling**:
- AI Brain failures → Dead letter queue + Slack alert
- Duplicate requests → 409 response
- Invalid signatures → 401 response
- Validation errors → 400 response

## 🧪 Testing Workflows

### Manual Testing

Use curl to test the webhook:

```bash
# Generate HMAC signature
MESSAGE='{"message":"test message","metadata":{"source":"test"}}'
SIGNATURE=$(echo -n "$MESSAGE" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -hex | cut -d' ' -f2)

# Send request
curl -X POST https://your-n8n-domain.com/webhook/ai-brain-webhook \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -d "$MESSAGE"
```

### Automated Testing

See the CI/CD pipeline in `.github/workflows/n8n-validation.yml` for automated workflow testing.

### Test Cases

1. **Happy Path**: Valid request → Success response
2. **Idempotency**: Duplicate requestId → 409 response
3. **Invalid Signature**: Wrong HMAC → 401 response
4. **AI Brain Failure**: Backend error → DLQ + Alert
5. **Timeout**: Long-running request → Retry logic

## 🔄 Deployment

### Docker Compose (Development/Staging)

```bash
# Start n8n with workflows
docker-compose up -d

# Import workflows
docker exec -it n8n n8n import:workflow --input=/workflows/ai-brain-request-handler.json
```

### Kubernetes (Production)

```bash
# Deploy n8n
kubectl apply -f k8s/n8n-deployment.yml

# Import workflows via init container or API
kubectl exec -it n8n-0 -- n8n import:workflow --input=/workflows/ai-brain-request-handler.json
```

### CI/CD Deployment

Workflows are automatically validated and deployed via GitHub Actions:
- On PR: Validate workflow JSON syntax
- On merge to main: Deploy to staging
- On release: Deploy to production

See `.github/workflows/n8n-validation.yml` for details.

## 📊 Monitoring

### Metrics

Workflows emit metrics to Prometheus (via pushgateway) or logs:

- `workflow_execution_total` - Total executions
- `workflow_execution_duration_seconds` - Execution time
- `workflow_execution_errors_total` - Error count
- `workflow_queue_size` - Pending requests

### Logs

Structured logs are output in JSON format:

```json
{
  "timestamp": "2025-10-19T21:00:00.000Z",
  "level": "info",
  "workflow": "ai-brain-request-handler",
  "requestId": "uuid-v4",
  "message": "Request processed successfully",
  "duration_ms": 1234
}
```

### Alerts

Configured in monitoring system:
- High error rate (>5% in 5 minutes)
- Long execution time (>30 seconds)
- Dead letter queue backlog (>100 items)
- Workflow failures (immediate Slack notification)

## 🔧 Troubleshooting

### Common Issues

#### Workflow not triggering
- Check webhook URL is correct
- Verify n8n is accessible from trigger source
- Check firewall/security group settings

#### Credential errors
- Verify credentials are configured in n8n UI
- Check environment variables are set
- Ensure credential names match workflow JSON

#### Redis connection failures
- Verify Redis is accessible from n8n
- Check Redis credentials
- Monitor Redis memory usage

#### AI Brain timeouts
- Increase timeout in HTTP Request node
- Check AI Brain service health
- Review retry configuration

### Debug Mode

Enable detailed logging:

```bash
# Set environment variable
N8N_LOG_LEVEL=debug

# Restart n8n
docker-compose restart n8n
```

### Workflow Execution History

View execution history in n8n UI:
1. Open workflow
2. Click **Executions** tab
3. Click on specific execution to see details

## 📚 Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Community Forum](https://community.n8n.io/)
- [Workflow Checklist](../WORKFLOW_CHECKLIST.md)
- [Runbooks](../docs/runbooks/)

## 🤝 Contributing

When adding new workflows:

1. Export workflow as JSON
2. Place in this directory with descriptive name
3. Update this README with workflow documentation
4. Add workflow-specific tests
5. Update WORKFLOW_CHECKLIST.md
6. Submit PR with changes

## 📝 Workflow Naming Convention

Use kebab-case with descriptive names:
- `ai-brain-request-handler.json`
- `data-processing-pipeline.json`
- `user-notification-sender.json`

## 🔒 Security Notes

- Never commit credentials or secrets
- Use environment variables for sensitive data
- Enable HMAC signature verification on all webhooks
- Regularly rotate API keys and tokens
- Review and audit workflow permissions
- Keep n8n version up to date

## 📞 Support

For issues or questions:
- Open an issue in the repository
- Contact the DevOps team
- Check runbooks for common problems
