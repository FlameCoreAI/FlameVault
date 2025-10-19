# FlameVault n8n Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         External Clients                             │
│                    (Web Apps, Mobile, APIs)                         │
└────────────────────────┬────────────────────────────────────────────┘
                         │ HTTPS
                         │
┌────────────────────────▼────────────────────────────────────────────┐
│                       API Gateway                                    │
│              (Rate Limiting, Authentication)                         │
└────────────────────────┬────────────────────────────────────────────┘
                         │
                         │ Webhook
                         │
┌────────────────────────▼────────────────────────────────────────────┐
│                                                                      │
│                          n8n Workflow Engine                         │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Webhook → Validate → Idempotency → Process → Respond       │  │
│  │     ↓         ↓            ↓           ↓          ↓          │  │
│  │  Security   Input      Redis Check   AI Brain  Success/Error│  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────┬────────┬─────────┬─────────┬──────────┬────────┬────────────┘
      │        │         │         │          │        │
      │        │         │         │          │        │
┌─────▼──┐ ┌──▼───┐ ┌───▼────┐ ┌──▼─────┐ ┌─▼──────┐ ┌▼──────────┐
│ Redis  │ │ PG   │ │AI Brain│ │ Ollama │ │FlameVlt│ │   Slack   │
│        │ │      │ │        │ │        │ │        │ │  Alerts   │
│Queue & │ │Store │ │ (AI)   │ │(Local) │ │Secrets │ │           │
│Idem.   │ │      │ │        │ │  AI)   │ │Storage │ │           │
└────────┘ └──────┘ └────────┘ └────────┘ └────────┘ └───────────┘
      │        │         │         │          │        
      │        │         │         │          │        
┌─────▼────────▼─────────▼─────────▼──────────▼────────────────────┐
│                    Observability Layer                             │
│                                                                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────────┐ │
│  │Prometheus│  │  Grafana │  │   Loki   │  │  Alertmanager   │ │
│  │ (Metrics)│  │(Dashboard│  │  (Logs)  │  │  (Alerting)     │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

## Workflow Execution Flow

```
1. Client Request
   │
   ├─→ API Gateway (Rate limit, Auth)
   │
   ├─→ n8n Webhook
   │
   ├─→ Security Validation (HMAC)
   │
   ├─→ Redis Idempotency Check
   │   ├─→ [Duplicate] → 409 Response
   │   └─→ [New] → Continue
   │
   ├─→ Mark Processing (Redis)
   │
   ├─→ Call AI Brain (with retry)
   │   ├─→ [Success] → Format Response
   │   │               └─→ Emit Metrics
   │   │                   └─→ Return 200
   │   │
   │   └─→ [Failure] → Dead Letter Queue
   │                   └─→ Send Alert
   │                       └─→ Return 500
   │
   └─→ Client receives response
```

## Data Flow

```
┌─────────────┐
│   Webhook   │ Receives HTTP POST
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Validate HMAC   │ Verify signature
└──────┬──────────┘
       │
       ▼
┌─────────────────┐
│ Extract Request │ Parse JSON, generate ID
└──────┬──────────┘
       │
       ▼
┌─────────────────┐         ┌──────────┐
│ Check Redis     │────────▶│  Redis   │
│ (Idempotency)   │◀────────│          │
└──────┬──────────┘         └──────────┘
       │
       ├─→ [Exists] ─→ Return 409
       │
       └─→ [New]
           │
           ▼
       ┌─────────────────┐  ┌──────────┐
       │ Mark Processing │─▶│  Redis   │
       └──────┬──────────┘  └──────────┘
              │
              ▼
       ┌─────────────────┐  ┌──────────┐
       │ Call AI Brain   │─▶│ AI Brain │
       │ (with retry)    │◀─│   API    │
       └──────┬──────────┘  └──────────┘
              │
              ├─→ [Success]
              │   │
              │   ▼
              │  ┌──────────────┐
              │  │ Format Result│
              │  └──────┬───────┘
              │         │
              │         ▼
              │  ┌──────────────┐
              │  │ Emit Metrics │
              │  └──────┬───────┘
              │         │
              │         ▼
              │  ┌──────────────┐
              │  │Return Success│
              │  └──────────────┘
              │
              └─→ [Failure]
                  │
                  ▼
             ┌────────────────┐  ┌──────────┐
             │ Save to DLQ    │─▶│  Redis   │
             └────────┬───────┘  └──────────┘
                      │
                      ▼
             ┌────────────────┐  ┌──────────┐
             │ Send Alert     │─▶│  Slack   │
             └────────┬───────┘  └──────────┘
                      │
                      ▼
             ┌────────────────┐
             │ Return Error   │
             └────────────────┘
```

## Deployment Architecture

### Development
```
┌────────────────────────────────────┐
│      Developer Workstation         │
│                                    │
│  ┌──────────────────────────────┐ │
│  │    Docker Compose            │ │
│  │  ┌────┐ ┌────┐ ┌─────┐      │ │
│  │  │n8n │ │PG  │ │Redis│      │ │
│  │  └────┘ └────┘ └─────┘      │ │
│  └──────────────────────────────┘ │
│                                    │
│  Access: http://localhost:5678    │
└────────────────────────────────────┘
```

### Staging
```
┌─────────────────────────────────────────┐
│         Staging Server (EC2/VM)         │
│                                         │
│  ┌───────────────────────────────────┐ │
│  │       Docker Compose              │ │
│  │  ┌────┐ ┌────┐ ┌─────┐ ┌────────┐│ │
│  │  │n8n │ │PG  │ │Redis│ │Monitor ││ │
│  │  └────┘ └────┘ └─────┘ └────────┘│ │
│  └───────────────────────────────────┘ │
│                                         │
│  URL: https://staging-n8n.example.com  │
└─────────────────────────────────────────┘
```

### Production (Kubernetes)
```
┌─────────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                         │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                Load Balancer                           │ │
│  └──────────────────┬─────────────────────────────────────┘ │
│                     │                                        │
│  ┌──────────────────┴─────────────────────────────────────┐ │
│  │              n8n Deployment (3 replicas)               │ │
│  │  ┌──────┐    ┌──────┐    ┌──────┐                     │ │
│  │  │ n8n  │    │ n8n  │    │ n8n  │                     │ │
│  │  │ Pod1 │    │ Pod2 │    │ Pod3 │                     │ │
│  │  └──┬───┘    └──┬───┘    └──┬───┘                     │ │
│  └─────┼───────────┼───────────┼────────────────────────┘ │
│        │           │           │                            │
│  ┌─────┴───────────┴───────────┴────────────────────────┐ │
│  │              Shared Services                          │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐           │ │
│  │  │PostgreSQL│  │  Redis   │  │ Monitoring│           │ │
│  │  │StatefulSet│ │  Cluster │  │  Stack    │           │ │
│  │  └──────────┘  └──────────┘  └──────────┘           │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                              │
│  Ingress: https://n8n.example.com                          │
└─────────────────────────────────────────────────────────────┘
```

## Security Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Layers                           │
└─────────────────────────────────────────────────────────────┘

Layer 1: Network Security
├─ Firewall rules
├─ VPC/Network segmentation
└─ TLS/SSL encryption

Layer 2: Authentication & Authorization
├─ API Gateway authentication
├─ Webhook HMAC signatures
├─ n8n basic auth/OAuth
└─ Service-to-service auth

Layer 3: Secrets Management
├─ HashiCorp Vault
├─ AWS Secrets Manager
├─ Kubernetes Secrets
└─ Environment variables (encrypted)

Layer 4: Application Security
├─ Input validation
├─ HMAC signature verification
├─ Rate limiting
└─ SQL injection prevention

Layer 5: Audit & Monitoring
├─ Access logs
├─ Audit logs
├─ Security alerts
└─ Compliance reports
```

## High Availability Setup

```
┌─────────────────────────────────────────────────────────────┐
│                 High Availability Configuration              │
│                                                              │
│  Multiple n8n Instances                                     │
│  ┌──────┐  ┌──────┐  ┌──────┐                             │
│  │ n8n  │  │ n8n  │  │ n8n  │                             │
│  │  #1  │  │  #2  │  │  #3  │                             │
│  └──┬───┘  └──┬───┘  └──┬───┘                             │
│     │         │         │                                   │
│     └─────────┼─────────┘                                   │
│               │                                             │
│  ┌────────────▼─────────────┐                              │
│  │    Redis Queue           │  ← Shared queue for jobs     │
│  │    (High Availability)   │                              │
│  └────────────┬─────────────┘                              │
│               │                                             │
│  ┌────────────▼─────────────┐                              │
│  │   PostgreSQL             │  ← Shared database           │
│  │   (with replication)     │                              │
│  └──────────────────────────┘                              │
│                                                              │
│  Benefits:                                                  │
│  • No single point of failure                              │
│  • Load distribution                                       │
│  • Automatic failover                                      │
│  • Horizontal scaling                                      │
└─────────────────────────────────────────────────────────────┘
```

## Backup & Recovery

```
┌─────────────────────────────────────────────────────────────┐
│                  Backup & Recovery Strategy                  │
│                                                              │
│  Automated Daily Backups                                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 1. Export workflows (JSON)                           │  │
│  │ 2. Backup PostgreSQL database (pg_dump)             │  │
│  │ 3. Backup n8n data directory (tar)                  │  │
│  │ 4. Compress all (tar.gz)                            │  │
│  │ 5. Upload to S3 (optional)                          │  │
│  │ 6. Cleanup old backups (>30 days)                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                          │                                   │
│                          ▼                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Backup Storage                               │  │
│  │  ┌────────────┐         ┌────────────┐              │  │
│  │  │   Local    │         │     S3     │              │  │
│  │  │  /backup/  │────────▶│   Bucket   │              │  │
│  │  └────────────┘         └────────────┘              │  │
│  │   30-day retention     90-day retention             │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  Recovery Process                                           │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 1. Select backup file                                │  │
│  │ 2. Stop services                                     │  │
│  │ 3. Extract backup                                    │  │
│  │ 4. Restore database                                  │  │
│  │ 5. Import workflows                                  │  │
│  │ 6. Start services                                    │  │
│  │ 7. Verify restoration                                │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  RTO (Recovery Time Objective): < 30 minutes                │
│  RPO (Recovery Point Objective): < 24 hours                 │
└─────────────────────────────────────────────────────────────┘
```

## Monitoring & Alerting Flow

```
┌─────────────────────────────────────────────────────────────┐
│                Monitoring & Alerting Architecture            │
│                                                              │
│  Data Collection                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  n8n Workflows                                       │  │
│  │    ├─→ Metrics (Prometheus format)                  │  │
│  │    ├─→ Logs (Structured JSON)                       │  │
│  │    └─→ Traces (OpenTelemetry)                       │  │
│  └────────┬─────────────────────┬────────────────┬──────┘  │
│           │                     │                │          │
│           ▼                     ▼                ▼          │
│  ┌────────────────┐   ┌────────────┐   ┌──────────────┐   │
│  │  Prometheus    │   │    Loki    │   │   Jaeger     │   │
│  │  (Metrics)     │   │   (Logs)   │   │  (Traces)    │   │
│  └────────┬───────┘   └──────┬─────┘   └──────┬───────┘   │
│           │                  │                 │            │
│           └──────────────────┼─────────────────┘            │
│                              │                              │
│                              ▼                              │
│                   ┌──────────────────┐                      │
│                   │     Grafana      │                      │
│                   │   (Dashboards)   │                      │
│                   └──────────────────┘                      │
│                              │                              │
│                              ▼                              │
│                   ┌──────────────────┐                      │
│                   │  Alertmanager    │                      │
│                   │   (Routing)      │                      │
│                   └────────┬─────────┘                      │
│                            │                                │
│                            ├─→ Slack                        │
│                            ├─→ PagerDuty                    │
│                            └─→ Email                        │
└─────────────────────────────────────────────────────────────┘
```

## Key Components Summary

| Component | Purpose | Technology |
|-----------|---------|------------|
| n8n | Workflow orchestration | Node.js application |
| PostgreSQL | Workflow storage | Relational database |
| Redis | Queue & idempotency | In-memory data store |
| AI Brain | AI processing | External API |
| Ollama | Local AI models | LLM inference engine |
| FlameVault | Secrets & artifacts | Storage service |
| Prometheus | Metrics collection | TSDB |
| Grafana | Visualization | Dashboard platform |
| Loki | Log aggregation | Log storage |
| Alertmanager | Alert routing | Notification system |
| Jaeger | Distributed tracing | APM |
