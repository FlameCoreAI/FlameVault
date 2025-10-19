# FlameVault

FlameVault is a production-ready workflow automation platform built on n8n, integrated with the Multichannel stack (API Gateway, AI Brain, Redis, Ollama).

## 🚀 Features

- **Production-Ready Workflows**: Comprehensive error handling, retries, and idempotency
- **Secure Secrets Management**: Integrated with HashiCorp Vault, AWS Secrets Manager, or Kubernetes Secrets
- **Full Observability**: Prometheus metrics, Loki logging, and Grafana dashboards
- **CI/CD Pipeline**: Automated workflow validation and deployment
- **High Availability**: Support for Docker Compose and Kubernetes deployments

## 📚 Documentation

- **[Workflow Checklist](WORKFLOW_CHECKLIST.md)** - Production readiness checklist
- **[Workflows](workflows/README.md)** - Available workflows and usage guide
- **[Deployment Guide](docs/DEPLOYMENT.md)** - Local, staging, and production deployment
- **[Secrets Management](docs/SECRETS.md)** - Security and credentials management
- **[Monitoring](docs/MONITORING.md)** - Observability and alerting setup
- **[Runbooks](docs/runbooks/workflow-failures.md)** - Troubleshooting guide

## 🏃 Quick Start

### Local Development

```bash
# Clone repository
git clone https://github.com/FlameCoreAI/FlameVault.git
cd FlameVault

# Configure environment
cp .env.example .env
# Edit .env with your values

# Start services
docker-compose up -d

# Import workflows
docker exec flamevault-n8n n8n import:workflow --input=/workflows/ai-brain-request-handler.json

# Access n8n
open http://localhost:5678
```

### Test Workflow

```bash
# Generate HMAC signature
MESSAGE='{"message":"test message"}'
SIGNATURE=$(echo -n "$MESSAGE" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" -hex | cut -d' ' -f2)

# Send request
curl -X POST http://localhost:5678/webhook/ai-brain-webhook \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -d "$MESSAGE"
```

## 🛠️ Tech Stack

- **n8n**: Workflow automation platform
- **PostgreSQL**: Workflow storage and execution history
- **Redis**: Queue management and idempotency checks
- **AI Brain**: AI processing backend
- **Ollama**: Local AI model inference
- **Prometheus**: Metrics collection
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation

## 🏗️ Architecture

```
┌─────────────┐
│   Webhook   │
└──────┬──────┘
       │
┌──────▼──────┐     ┌──────────┐
│   n8n       │────▶│  Redis   │ (Idempotency)
└──────┬──────┘     └──────────┘
       │
       ├──────▶ AI Brain
       ├──────▶ Ollama
       └──────▶ FlameVault
```

## 📋 Available Workflows

### ai-brain-request-handler
Handles webhook requests, processes through AI Brain, returns structured responses.

**Features**:
- ✅ HMAC signature verification
- ✅ Redis-based idempotency
- ✅ Exponential backoff retry
- ✅ Dead letter queue for failures
- ✅ Slack alerting
- ✅ Structured logging

See [workflows/README.md](workflows/README.md) for details.

## 🔒 Security

- All credentials stored in environment variables or secret stores
- Webhook HMAC signature verification
- No secrets committed to repository
- Regular security audits and updates

See [docs/SECRETS.md](docs/SECRETS.md) for details.

## 📊 Monitoring

- Real-time metrics via Prometheus
- Centralized logging with Loki
- Grafana dashboards for visualization
- Alerting via Slack and PagerDuty

See [docs/MONITORING.md](docs/MONITORING.md) for setup.

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## 📝 License

See [LICENSE.md](LICENSE.md) for license information.

## 📞 Support

- **Documentation**: See [docs/README.md](docs/README.md)
- **Issues**: [GitHub Issues](https://github.com/FlameCoreAI/FlameVault/issues)
- **Runbooks**: [docs/runbooks/](docs/runbooks/)

## 🎯 Roadmap

See [dev-plan.md](dev-plan.md) for development roadmap.