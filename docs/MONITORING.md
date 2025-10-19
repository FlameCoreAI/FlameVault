# Monitoring and Observability Guide

This guide covers monitoring, logging, and observability for n8n workflows in the FlameVault stack.

## 📊 Monitoring Architecture

```
┌─────────────────┐
│   n8n Workflows │
└────────┬────────┘
         │ Metrics, Logs, Traces
         ├──────────┬──────────┬────────────┐
         │          │          │            │
    ┌────▼────┐ ┌──▼───┐ ┌────▼─────┐ ┌────▼─────┐
    │Prometheus│ │Loki  │ │ Jaeger   │ │  Redis   │
    └────┬────┘ └──┬───┘ └────┬─────┘ └────┬─────┘
         │         │           │            │
         └─────────┴───────────┴────────────┘
                        │
                   ┌────▼────┐
                   │ Grafana │
                   └─────────┘
```

## 🎯 Key Metrics

### Workflow Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `workflow_executions_total` | Counter | Total workflow executions |
| `workflow_execution_duration_seconds` | Histogram | Execution time |
| `workflow_errors_total` | Counter | Failed executions |
| `workflow_queue_size` | Gauge | Pending executions |
| `workflow_active_executions` | Gauge | Currently running |

### System Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `n8n_memory_usage_bytes` | Gauge | Memory consumption |
| `n8n_cpu_usage_percent` | Gauge | CPU utilization |
| `redis_connected_clients` | Gauge | Redis connections |
| `postgres_connections` | Gauge | Database connections |

### Integration Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `ai_brain_requests_total` | Counter | AI Brain API calls |
| `ai_brain_request_duration_seconds` | Histogram | AI Brain latency |
| `ai_brain_errors_total` | Counter | AI Brain failures |
| `redis_operations_total` | Counter | Redis operations |
| `deadletter_queue_size` | Gauge | Failed items in DLQ |

## 📈 Prometheus Setup

### 1. Install Prometheus

```bash
# Docker Compose (add to docker-compose.yml)
prometheus:
  image: prom/prometheus:latest
  container_name: prometheus
  ports:
    - "9090:9090"
  volumes:
    - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    - prometheus_data:/prometheus
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.path=/prometheus'
  networks:
    - flamevault-network
```

### 2. Configure Prometheus

```yaml
# prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'flamevault-production'
    environment: 'production'

scrape_configs:
  # n8n metrics
  - job_name: 'n8n'
    static_configs:
      - targets: ['n8n:5678']
    metrics_path: '/metrics'
    scrape_interval: 30s

  # Redis metrics
  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']

  # PostgreSQL metrics
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  # Custom workflow metrics
  - job_name: 'workflow-metrics'
    static_configs:
      - targets: ['prometheus-pushgateway:9091']
    honor_labels: true

# Alerting rules
rule_files:
  - 'alerts.yml'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']
```

### 3. Define Alert Rules

```yaml
# prometheus/alerts.yml
groups:
  - name: n8n_workflows
    interval: 30s
    rules:
      # High error rate
      - alert: HighWorkflowErrorRate
        expr: |
          rate(workflow_errors_total[5m]) / rate(workflow_executions_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
          component: n8n
        annotations:
          summary: "High workflow error rate ({{ $value | humanizePercentage }})"
          description: "Workflow {{ $labels.workflow }} has error rate above 5%"

      # Long execution time
      - alert: SlowWorkflowExecution
        expr: |
          histogram_quantile(0.95, 
            rate(workflow_execution_duration_seconds_bucket[5m])
          ) > 30
        for: 10m
        labels:
          severity: warning
          component: n8n
        annotations:
          summary: "Slow workflow execution (P95: {{ $value }}s)"
          description: "Workflow execution taking longer than 30 seconds"

      # Queue backlog
      - alert: WorkflowQueueBacklog
        expr: workflow_queue_size > 1000
        for: 5m
        labels:
          severity: critical
          component: n8n
        annotations:
          summary: "Large workflow queue ({{ $value }} items)"
          description: "Workflow queue has more than 1000 pending executions"

      # Dead letter queue growing
      - alert: DeadLetterQueueGrowing
        expr: deadletter_queue_size > 100
        for: 5m
        labels:
          severity: warning
          component: n8n
        annotations:
          summary: "Dead letter queue growing ({{ $value }} items)"
          description: "Check failed workflow executions"

      # n8n instance down
      - alert: N8nDown
        expr: up{job="n8n"} == 0
        for: 2m
        labels:
          severity: critical
          component: n8n
        annotations:
          summary: "n8n instance is down"
          description: "n8n has been unreachable for 2 minutes"

      # High memory usage
      - alert: HighMemoryUsage
        expr: n8n_memory_usage_bytes / n8n_memory_limit_bytes > 0.9
        for: 5m
        labels:
          severity: warning
          component: n8n
        annotations:
          summary: "High memory usage ({{ $value | humanizePercentage }})"
          description: "n8n using more than 90% of available memory"

      # AI Brain issues
      - alert: AIBrainHighErrorRate
        expr: |
          rate(ai_brain_errors_total[5m]) / rate(ai_brain_requests_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
          component: ai-brain
        annotations:
          summary: "AI Brain high error rate ({{ $value | humanizePercentage }})"
          description: "AI Brain error rate above 10%"

      - alert: AIBrainSlow
        expr: |
          histogram_quantile(0.95,
            rate(ai_brain_request_duration_seconds_bucket[5m])
          ) > 10
        for: 5m
        labels:
          severity: warning
          component: ai-brain
        annotations:
          summary: "AI Brain slow responses (P95: {{ $value }}s)"
          description: "AI Brain taking longer than 10 seconds to respond"
```

## 📝 Logging Setup

### 1. Structured Logging in Workflows

Add to Function nodes:

```javascript
// Structured logging function
function logEvent(level, message, data = {}) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    level: level,
    workflow: $workflow.name,
    execution_id: $execution.id,
    message: message,
    data: data
  };
  console.log(JSON.stringify(logEntry));
}

// Usage
logEvent('info', 'Starting AI Brain request', {
  requestId: $json.requestId,
  message_length: $json.message.length
});

try {
  // Your logic
  logEvent('info', 'AI Brain request successful', {
    duration_ms: Date.now() - startTime
  });
} catch (error) {
  logEvent('error', 'AI Brain request failed', {
    error: error.message,
    stack: error.stack
  });
}
```

### 2. Centralized Logging with Loki

```yaml
# docker-compose.yml
loki:
  image: grafana/loki:latest
  container_name: loki
  ports:
    - "3100:3100"
  volumes:
    - ./loki/loki-config.yml:/etc/loki/local-config.yaml
    - loki_data:/loki
  command: -config.file=/etc/loki/local-config.yaml
  networks:
    - flamevault-network

promtail:
  image: grafana/promtail:latest
  container_name: promtail
  volumes:
    - ./loki/promtail-config.yml:/etc/promtail/config.yml
    - /var/log:/var/log
    - /var/lib/docker/containers:/var/lib/docker/containers:ro
  command: -config.file=/etc/promtail/config.yml
  networks:
    - flamevault-network
```

```yaml
# loki/loki-config.yml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h
```

```yaml
# loki/promtail-config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # n8n container logs
  - job_name: n8n
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/n8n'
        action: keep
      - source_labels: ['__meta_docker_container_name']
        target_label: container
      - source_labels: ['__meta_docker_container_log_stream']
        target_label: stream
    pipeline_stages:
      - json:
          expressions:
            timestamp: timestamp
            level: level
            workflow: workflow
            message: message
      - labels:
          level:
          workflow:
```

## 📊 Grafana Dashboards

### 1. Install Grafana

```yaml
# docker-compose.yml
grafana:
  image: grafana/grafana:latest
  container_name: grafana
  ports:
    - "3000:3000"
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    - GF_INSTALL_PLUGINS=redis-datasource
  volumes:
    - grafana_data:/var/lib/grafana
    - ./grafana/provisioning:/etc/grafana/provisioning
  networks:
    - flamevault-network
```

### 2. Provision Data Sources

```yaml
# grafana/provisioning/datasources/datasources.yml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: false

  - name: Redis
    type: redis-datasource
    access: proxy
    url: redis:6379
    jsonData:
      client: standalone
    secureJsonData:
      password: ${REDIS_PASSWORD}
```

### 3. Create Dashboard

```json
{
  "dashboard": {
    "title": "n8n Workflows Overview",
    "panels": [
      {
        "title": "Workflow Executions",
        "targets": [
          {
            "expr": "rate(workflow_executions_total[5m])",
            "legendFormat": "{{workflow}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Error Rate",
        "targets": [
          {
            "expr": "rate(workflow_errors_total[5m]) / rate(workflow_executions_total[5m])",
            "legendFormat": "{{workflow}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Execution Duration (P95)",
        "targets": [
          {
            "expr": "histogram_quantile(0.95, rate(workflow_execution_duration_seconds_bucket[5m]))",
            "legendFormat": "{{workflow}}"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Queue Size",
        "targets": [
          {
            "expr": "workflow_queue_size"
          }
        ],
        "type": "graph"
      },
      {
        "title": "Dead Letter Queue",
        "targets": [
          {
            "expr": "deadletter_queue_size"
          }
        ],
        "type": "stat"
      },
      {
        "title": "Recent Errors",
        "targets": [
          {
            "expr": "{container=\"n8n\"} |= \"error\" | json | level=\"error\""
          }
        ],
        "type": "logs",
        "datasource": "Loki"
      }
    ]
  }
}
```

## 🔔 Alerting

### 1. Alertmanager Configuration

```yaml
# alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
  slack_api_url: '${SLACK_WEBHOOK_URL}'

route:
  group_by: ['alertname', 'cluster']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'
      continue: true
    - match:
        severity: warning
      receiver: 'slack'

receivers:
  - name: 'default'
    slack_configs:
      - channel: '#n8n-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: 'slack'
    slack_configs:
      - channel: '#n8n-alerts'
        title: '⚠️ {{ .GroupLabels.alertname }}'
        text: |
          *Summary:* {{ .CommonAnnotations.summary }}
          *Description:* {{ .CommonAnnotations.description }}
          *Details:*
          {{ range .Alerts }}
          • {{ .Labels.instance }}: {{ .Annotations.description }}
          {{ end }}

  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
        description: '{{ .CommonAnnotations.summary }}'
```

### 2. Slack Integration

```javascript
// In workflow error handler
const slackMessage = {
  channel: '#n8n-alerts',
  username: 'n8n Alert Bot',
  icon_emoji: ':warning:',
  attachments: [{
    color: 'danger',
    title: `Workflow Failed: ${$workflow.name}`,
    fields: [
      {
        title: 'Execution ID',
        value: $execution.id,
        short: true
      },
      {
        title: 'Error',
        value: $json.error.message,
        short: false
      },
      {
        title: 'Request ID',
        value: $json.requestId,
        short: true
      },
      {
        title: 'Timestamp',
        value: new Date().toISOString(),
        short: true
      }
    ],
    footer: 'n8n Monitoring',
    ts: Date.now() / 1000
  }]
};

return { json: slackMessage };
```

## 🔍 Distributed Tracing

### Jaeger Setup

```yaml
# docker-compose.yml
jaeger:
  image: jaegertracing/all-in-one:latest
  container_name: jaeger
  ports:
    - "5775:5775/udp"
    - "6831:6831/udp"
    - "6832:6832/udp"
    - "5778:5778"
    - "16686:16686"
    - "14268:14268"
    - "14250:14250"
  environment:
    - COLLECTOR_ZIPKIN_HTTP_PORT=9411
  networks:
    - flamevault-network
```

### Add Tracing to Workflows

```javascript
// Initialize tracer
const opentracing = require('opentracing');
const { initTracer } = require('jaeger-client');

const config = {
  serviceName: 'n8n-workflows',
  sampler: {
    type: 'const',
    param: 1
  },
  reporter: {
    agentHost: 'jaeger',
    agentPort: 6831
  }
};

const tracer = initTracer(config, {});

// Create span
const span = tracer.startSpan('ai-brain-request');
span.setTag('requestId', $json.requestId);

try {
  // Your workflow logic
  span.setTag('status', 'success');
} catch (error) {
  span.setTag('error', true);
  span.log({ event: 'error', message: error.message });
  throw error;
} finally {
  span.finish();
}
```

## 📊 Custom Metrics

### Emit Metrics from Workflows

```javascript
// Function to push metrics to Prometheus
async function pushMetric(metric) {
  const pushgateway = $env('PROMETHEUS_PUSHGATEWAY');
  
  const metricText = `
# TYPE ${metric.name} ${metric.type}
${metric.name}{workflow="${$workflow.name}",${metric.labels}} ${metric.value}
`;

  await $http.request({
    method: 'POST',
    url: `${pushgateway}/metrics/job/n8n/instance/${$execution.id}`,
    body: metricText,
    headers: {
      'Content-Type': 'text/plain'
    }
  });
}

// Example usage
await pushMetric({
  name: 'workflow_custom_counter',
  type: 'counter',
  labels: 'step="ai_brain_call",status="success"',
  value: 1
});

await pushMetric({
  name: 'workflow_processing_duration_seconds',
  type: 'gauge',
  labels: 'step="data_processing"',
  value: (Date.now() - startTime) / 1000
});
```

## 📋 Monitoring Checklist

- [ ] Prometheus installed and scraping metrics
- [ ] Alert rules configured
- [ ] Alertmanager routing alerts to Slack/PagerDuty
- [ ] Grafana dashboards created
- [ ] Loki collecting logs
- [ ] Log retention policy set
- [ ] Distributed tracing (optional)
- [ ] Custom metrics from workflows
- [ ] Runbooks linked to alerts
- [ ] On-call rotation defined
- [ ] Regular review of alert thresholds

## 🔗 References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [n8n Monitoring Guide](https://docs.n8n.io/hosting/monitoring/)
