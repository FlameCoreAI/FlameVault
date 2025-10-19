# n8n Workflow Failure Runbook

This runbook provides step-by-step procedures for diagnosing and resolving common n8n workflow failures.

## 🚨 Quick Reference

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Webhook not triggering | Network/firewall issue | Check network connectivity and firewall rules |
| 401/403 errors | Credential/auth failure | Verify credentials in n8n UI |
| 500 errors from AI Brain | Backend service down | Check AI Brain service status |
| Timeouts | Long-running operation | Increase timeout, check service performance |
| Redis connection errors | Redis unavailable | Check Redis service health |
| Duplicate processing | Idempotency check failed | Verify Redis connectivity |

## 📋 General Troubleshooting Process

1. **Identify the failure**: Check workflow execution history
2. **Review logs**: Examine n8n logs and specific execution logs
3. **Check dependencies**: Verify all external services are available
4. **Isolate the issue**: Determine which node/step is failing
5. **Apply fix**: Follow specific runbook for the issue type
6. **Verify resolution**: Test the workflow end-to-end
7. **Document**: Update this runbook if new issue discovered

## 🔧 Common Issues and Solutions

### 1. Webhook Not Receiving Requests

**Symptoms:**
- Workflow never triggers
- No executions appear in history
- External system reports successful send

**Diagnostic Steps:**

```bash
# Check if n8n is running
docker ps | grep n8n

# Check n8n logs
docker logs n8n -f

# Test webhook endpoint
curl -X POST https://your-n8n-domain/webhook/test \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}'

# Check firewall rules
sudo ufw status
```

**Resolution:**

1. **Verify n8n is accessible:**
   ```bash
   # Test from external source
   curl -I https://your-n8n-domain/healthz
   ```

2. **Check webhook URL configuration:**
   - Open workflow in n8n UI
   - Verify webhook path matches what caller is using
   - Check if webhook is in "production" mode

3. **Review security settings:**
   - Check if HMAC signature validation is too strict
   - Temporarily disable signature check for testing
   - Verify WEBHOOK_SECRET environment variable

4. **Check network/firewall:**
   ```bash
   # Check if port is open
   netstat -tuln | grep 5678
   
   # Check firewall rules
   sudo iptables -L -n | grep 5678
   ```

5. **Restart n8n if needed:**
   ```bash
   docker-compose restart n8n
   ```

### 2. Credential/Authentication Errors

**Symptoms:**
- 401 Unauthorized errors
- 403 Forbidden errors
- "Invalid credentials" messages

**Diagnostic Steps:**

```bash
# Check environment variables
docker exec n8n env | grep API_KEY

# Test credential manually
curl -H "Authorization: Bearer $API_KEY" $API_URL/health
```

**Resolution:**

1. **Verify credentials in n8n UI:**
   - Go to Settings → Credentials
   - Find the affected credential
   - Test the credential connection
   - Update if expired/invalid

2. **Check environment variables:**
   ```bash
   # View current environment
   docker exec n8n printenv | grep -E '(API_KEY|PASSWORD|SECRET)'
   
   # Update .env file if needed
   nano .env
   
   # Restart to pick up changes
   docker-compose restart n8n
   ```

3. **Rotate credentials if compromised:**
   - Generate new API key in external service
   - Update credential in n8n UI
   - Update environment variables
   - Test workflow execution

4. **Check credential permissions:**
   - Verify API key has required scopes
   - Check if IP allowlist needs updating
   - Ensure service account is not disabled

### 3. AI Brain Service Failures

**Symptoms:**
- 500 Internal Server Error
- Timeouts from AI Brain
- "Service unavailable" messages

**Diagnostic Steps:**

```bash
# Check AI Brain health
curl -f $AI_BRAIN_URL/health

# Check AI Brain logs
kubectl logs -n ai-brain deployment/ai-brain --tail=100

# Monitor response times
curl -w "@curl-format.txt" -o /dev/null -s $AI_BRAIN_URL/api/v1/test
```

**Resolution:**

1. **Verify AI Brain is running:**
   ```bash
   # For Kubernetes
   kubectl get pods -n ai-brain
   kubectl describe pod ai-brain-xxx
   
   # For Docker
   docker ps | grep ai-brain
   docker logs ai-brain
   ```

2. **Check resource usage:**
   ```bash
   # Check CPU/memory
   kubectl top pods -n ai-brain
   
   # Check if OOMKilled
   kubectl get pods -n ai-brain -o json | jq '.items[].status.containerStatuses[].lastState'
   ```

3. **Scale up if needed:**
   ```bash
   # Kubernetes
   kubectl scale deployment ai-brain --replicas=3 -n ai-brain
   
   # Docker Compose
   docker-compose up -d --scale ai-brain=3
   ```

4. **Check for rate limiting:**
   - Review AI Brain rate limit policies
   - Implement backoff in workflow
   - Consider request batching

5. **Fallback options:**
   - Configure secondary AI Brain endpoint
   - Use Ollama as fallback
   - Queue requests for retry

### 4. Redis Connection Failures

**Symptoms:**
- "ECONNREFUSED" errors
- Idempotency checks failing
- Queue not processing

**Diagnostic Steps:**

```bash
# Check Redis status
docker ps | grep redis

# Test Redis connection
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD ping

# Check Redis memory
redis-cli -a $REDIS_PASSWORD info memory

# Monitor Redis operations
redis-cli -a $REDIS_PASSWORD monitor
```

**Resolution:**

1. **Restart Redis if needed:**
   ```bash
   docker-compose restart redis
   ```

2. **Check Redis logs:**
   ```bash
   docker logs redis --tail=100
   ```

3. **Verify Redis configuration:**
   ```bash
   # Check Redis config
   redis-cli -a $REDIS_PASSWORD config get maxmemory
   redis-cli -a $REDIS_PASSWORD config get maxmemory-policy
   ```

4. **Clear Redis if memory full:**
   ```bash
   # Flush specific keys
   redis-cli -a $REDIS_PASSWORD --scan --pattern "request:*" | xargs redis-cli -a $REDIS_PASSWORD del
   
   # Or flush all (CAUTION!)
   redis-cli -a $REDIS_PASSWORD flushall
   ```

5. **Increase Redis memory:**
   ```yaml
   # docker-compose.yml
   redis:
     command: redis-server --maxmemory 1gb
   ```

### 5. Timeout Errors

**Symptoms:**
- "Request timeout" errors
- Workflows hanging
- Long execution times

**Diagnostic Steps:**

```bash
# Check workflow execution time
# (view in n8n UI execution history)

# Monitor network latency
ping -c 10 ai-brain.example.com

# Check for blocking operations
docker stats n8n
```

**Resolution:**

1. **Increase timeout in workflow:**
   - Open HTTP Request node
   - Go to Options → Timeout
   - Set appropriate value (e.g., 60000 ms = 1 minute)

2. **Implement proper retry logic:**
   ```javascript
   // In Function node
   const maxRetries = 3;
   const retryDelay = 1000; // ms
   
   for (let i = 0; i < maxRetries; i++) {
     try {
       // Your operation
       break;
     } catch (error) {
       if (i === maxRetries - 1) throw error;
       await new Promise(resolve => setTimeout(resolve, retryDelay * (i + 1)));
     }
   }
   ```

3. **Use async/queue pattern:**
   - Move long-running operations to separate workflow
   - Use webhook callbacks for completion
   - Implement job queue with Redis

4. **Optimize performance:**
   - Cache frequent lookups
   - Batch API requests
   - Use streaming for large data
   - Profile slow nodes

### 6. Dead Letter Queue Backlog

**Symptoms:**
- Many failed requests in DLQ
- Redis memory growing
- Alert notifications flooding

**Diagnostic Steps:**

```bash
# Count DLQ items
redis-cli -a $REDIS_PASSWORD --scan --pattern "dlq:*" | wc -l

# View sample DLQ items
redis-cli -a $REDIS_PASSWORD --scan --pattern "dlq:*" | head -5 | xargs -I {} redis-cli -a $REDIS_PASSWORD get {}

# Check DLQ age
redis-cli -a $REDIS_PASSWORD --scan --pattern "dlq:*" | head -1 | xargs redis-cli -a $REDIS_PASSWORD ttl
```

**Resolution:**

1. **Analyze failure patterns:**
   ```bash
   # Export DLQ items for analysis
   redis-cli -a $REDIS_PASSWORD --scan --pattern "dlq:*" | \
     xargs -I {} redis-cli -a $REDIS_PASSWORD get {} > /tmp/dlq-items.json
   
   # Analyze common errors
   jq -r '.error.message' /tmp/dlq-items.json | sort | uniq -c | sort -rn
   ```

2. **Fix root cause:**
   - Address the most common error
   - Update workflow if needed
   - Fix external service issues

3. **Retry failed items:**
   ```javascript
   // Create retry workflow
   // 1. Read from DLQ
   // 2. Reprocess with original data
   // 3. Remove from DLQ if successful
   ```

4. **Manual cleanup if needed:**
   ```bash
   # Remove old failed items (older than 7 days)
   redis-cli -a $REDIS_PASSWORD --scan --pattern "dlq:*" | \
     while read key; do
       ttl=$(redis-cli -a $REDIS_PASSWORD ttl "$key")
       if [ $ttl -lt 604800 ]; then
         redis-cli -a $REDIS_PASSWORD del "$key"
       fi
     done
   ```

5. **Implement DLQ monitoring:**
   - Alert on DLQ size > threshold
   - Dashboard showing DLQ trends
   - Automated retry with exponential backoff

### 7. Duplicate Processing (Idempotency Failure)

**Symptoms:**
- Same request processed multiple times
- Duplicate records in database
- Users receiving duplicate notifications

**Diagnostic Steps:**

```bash
# Check for duplicate request IDs
redis-cli -a $REDIS_PASSWORD --scan --pattern "request:*" | sort | uniq -d

# Review execution history
# (check n8n UI for multiple executions with same requestId)
```

**Resolution:**

1. **Verify idempotency check is working:**
   - Check Redis connection in workflow
   - Ensure requestId is properly generated
   - Verify Redis key format

2. **Extend TTL if needed:**
   ```javascript
   // Increase TTL in Redis set operation
   {
     "operation": "set",
     "key": "={{\"request:\" + $json.requestId}}",
     "expire": true,
     "ttl": 7200  // 2 hours instead of 1
   }
   ```

3. **Use stronger uniqueness:**
   ```javascript
   // Generate better request ID
   const crypto = require('crypto');
   const payload = JSON.stringify($input.item.json.body);
   const requestId = crypto.createHash('sha256').update(payload).digest('hex');
   ```

4. **Implement distributed locking:**
   ```javascript
   // Use Redis SETNX for distributed lock
   const lockKey = `lock:${requestId}`;
   const lockAcquired = await redis.setnx(lockKey, '1');
   if (!lockAcquired) {
     throw new Error('Request already being processed');
   }
   await redis.expire(lockKey, 300); // 5 minute lock
   ```

### 8. Workflow Not Updating After Changes

**Symptoms:**
- Changes in git not reflected in n8n
- Old version still executing
- Import appears successful but no change

**Diagnostic Steps:**

```bash
# Check workflow version
docker exec n8n n8n list:workflow

# Check last modified date in n8n
# (view in n8n UI)

# Compare with git version
git log -1 --format="%ai" workflows/my-workflow.json
```

**Resolution:**

1. **Re-import workflow:**
   ```bash
   # Export current version first (backup)
   docker exec n8n n8n export:workflow --id=<workflow-id> --output=/backup/workflow-backup.json
   
   # Import updated version
   docker exec n8n n8n import:workflow --input=/workflows/my-workflow.json
   ```

2. **Check for name conflicts:**
   - n8n may create new workflow instead of updating
   - Delete old version if needed
   - Verify correct workflow ID

3. **Restart n8n:**
   ```bash
   docker-compose restart n8n
   ```

4. **Use API for updates:**
   ```bash
   # Update via n8n API
   curl -X PUT http://localhost:5678/api/v1/workflows/<id> \
     -H "Content-Type: application/json" \
     -H "X-N8N-API-KEY: $N8N_API_KEY" \
     -d @workflows/my-workflow.json
   ```

## 🔍 Advanced Debugging

### Enable Debug Logging

```bash
# Set log level
docker exec n8n sh -c 'export N8N_LOG_LEVEL=debug'

# Restart to apply
docker-compose restart n8n

# View debug logs
docker logs n8n -f | grep DEBUG
```

### Inspect Workflow Execution

1. Open workflow in n8n UI
2. Click "Executions" tab
3. Select failed execution
4. Review each node's input/output
5. Check error messages

### Use n8n CLI

```bash
# List all workflows
docker exec n8n n8n list:workflow

# Execute workflow manually
docker exec n8n n8n execute --id=<workflow-id>

# Test webhook endpoint
docker exec n8n n8n webhook --id=<workflow-id>
```

### Monitor Network Traffic

```bash
# Capture traffic to AI Brain
tcpdump -i any -A 'host ai-brain.example.com and port 443' -w /tmp/ai-brain.pcap

# Analyze with Wireshark or tcpdump
tcpdump -r /tmp/ai-brain.pcap -A
```

## 📊 Monitoring and Alerts

### Key Metrics to Monitor

1. **Workflow execution rate** (executions/minute)
2. **Error rate** (errors/total executions)
3. **Execution duration** (p50, p95, p99)
4. **Queue depth** (pending executions)
5. **DLQ size** (failed items)
6. **Resource usage** (CPU, memory, disk)

### Alert Thresholds

- Error rate > 5% for 5 minutes
- Execution time > 30 seconds (p95)
- Queue depth > 1000
- DLQ size > 100
- n8n container restarts > 3 in 1 hour

### Alerting Setup

```yaml
# Prometheus alert rules
groups:
  - name: n8n_workflows
    rules:
      - alert: HighErrorRate
        expr: rate(n8n_workflow_errors_total[5m]) > 0.05
        for: 5m
        annotations:
          summary: "High workflow error rate"
          description: "Error rate is {{ $value }} (>5%)"
      
      - alert: SlowWorkflowExecution
        expr: histogram_quantile(0.95, n8n_workflow_duration_seconds) > 30
        for: 10m
        annotations:
          summary: "Slow workflow execution"
          description: "P95 execution time is {{ $value }}s"
```

## 📞 Escalation

If issue cannot be resolved:

1. **Gather information:**
   - Workflow execution ID
   - Error messages
   - Relevant logs
   - Steps already attempted

2. **Create incident ticket** with:
   - Clear description
   - Impact assessment
   - Troubleshooting steps taken
   - Current status

3. **Escalate to:**
   - DevOps team for infrastructure issues
   - Backend team for service issues
   - n8n community for platform issues

4. **Emergency contacts:**
   - On-call DevOps: [Contact info]
   - Platform owner: [Contact info]
   - Incident commander: [Contact info]

## 📝 Post-Incident

After resolving an issue:

1. Document what happened
2. Update this runbook if needed
3. Identify root cause
4. Implement preventive measures
5. Share learnings with team

## 🔗 Additional Resources

- [n8n Documentation](https://docs.n8n.io/)
- [n8n Community Forum](https://community.n8n.io/)
- [Redis Documentation](https://redis.io/docs/)
- [Workflow Checklist](../WORKFLOW_CHECKLIST.md)
- [Workflow README](../workflows/README.md)
