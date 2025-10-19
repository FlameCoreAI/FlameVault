# Secrets Management Guide

This guide covers best practices for managing secrets, credentials, and sensitive data in n8n workflows.

## 🔐 Security Principles

1. **Never commit secrets to version control**
2. **Use environment variables for sensitive data**
3. **Rotate credentials regularly**
4. **Use least privilege access**
5. **Audit access to secrets**
6. **Encrypt secrets at rest and in transit**

## 🎯 Secret Categories

### 1. n8n System Secrets
- n8n encryption key
- Database passwords
- Redis passwords
- Basic auth credentials

### 2. Integration Credentials
- AI Brain API keys
- Ollama access tokens
- FlameVault credentials
- Third-party API keys

### 3. Webhook Security
- HMAC secrets
- JWT signing keys
- OAuth client secrets

### 4. Monitoring & Alerting
- Slack webhook URLs
- PagerDuty API keys
- Prometheus credentials

## 📦 Secret Storage Options

### Option 1: Environment Variables (Basic)

**Pros:**
- Simple to implement
- No additional infrastructure
- Works with Docker/K8s

**Cons:**
- Visible in process lists
- Not centrally managed
- Manual rotation

**Setup:**

```bash
# .env file (DO NOT COMMIT)
AI_BRAIN_API_KEY=sk-abc123xyz789
REDIS_PASSWORD=super-secret-password
N8N_ENCRYPTION_KEY=0123456789abcdef
```

**Usage in n8n:**
```javascript
// In Function node
const apiKey = $env('AI_BRAIN_API_KEY');
```

### Option 2: HashiCorp Vault (Recommended)

**Pros:**
- Centralized secret management
- Automatic rotation
- Audit logging
- Dynamic secrets
- Access control

**Cons:**
- Additional infrastructure
- Learning curve
- Operational overhead

**Setup:**

```bash
# Install Vault
docker run -d --name vault \
  -p 8200:8200 \
  -e VAULT_DEV_ROOT_TOKEN_ID=dev-token \
  vault:latest

# Initialize
export VAULT_ADDR='http://localhost:8200'
export VAULT_TOKEN='dev-token'

# Store secrets
vault kv put secret/n8n/ai-brain \
  api_key=sk-abc123xyz789 \
  url=https://ai-brain.example.com

vault kv put secret/n8n/redis \
  password=super-secret-password
```

**Integration with n8n:**

1. **Using Vault Agent:**

```yaml
# vault-agent.hcl
vault {
  address = "http://vault:8200"
}

auto_auth {
  method {
    type = "kubernetes"
    config = {
      role = "n8n"
    }
  }
}

template {
  source      = "/config/n8n.env.tmpl"
  destination = "/config/n8n.env"
}
```

2. **Using init container:**

```yaml
initContainers:
- name: vault-init
  image: vault:latest
  command:
  - sh
  - -c
  - |
    vault kv get -field=api_key secret/n8n/ai-brain > /secrets/ai_brain_key
    vault kv get -field=password secret/n8n/redis > /secrets/redis_password
  volumeMounts:
  - name: secrets
    mountPath: /secrets
```

### Option 3: AWS Secrets Manager

**Pros:**
- Managed service
- Automatic rotation
- IAM integration
- Encryption

**Cons:**
- AWS-specific
- Cost
- API rate limits

**Setup:**

```bash
# Create secret
aws secretsmanager create-secret \
  --name n8n/ai-brain \
  --secret-string '{"api_key":"sk-abc123xyz789","url":"https://ai-brain.example.com"}'

# Create IAM role for n8n
aws iam create-role \
  --role-name n8n-secrets-access \
  --assume-role-policy-document file://trust-policy.json

# Attach policy
aws iam attach-role-policy \
  --role-name n8n-secrets-access \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

**Integration:**

```javascript
// In n8n Function node
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager();

const secret = await secretsManager.getSecretValue({
  SecretId: 'n8n/ai-brain'
}).promise();

const { api_key, url } = JSON.parse(secret.SecretString);
```

### Option 4: Kubernetes Secrets

**Pros:**
- Native to K8s
- No additional infra
- RBAC integration

**Cons:**
- Base64 encoded (not encrypted by default)
- Manual rotation
- Kubernetes-only

**Setup:**

```bash
# Create secret
kubectl create secret generic n8n-credentials \
  --from-literal=ai-brain-key=sk-abc123xyz789 \
  --from-literal=redis-password=super-secret \
  -n n8n-production

# Or from file
kubectl create secret generic n8n-credentials \
  --from-env-file=.env \
  -n n8n-production
```

**Usage in pod:**

```yaml
env:
- name: AI_BRAIN_API_KEY
  valueFrom:
    secretKeyRef:
      name: n8n-credentials
      key: ai-brain-key
```

## 🔑 n8n Credential System

### Built-in Credential Types

n8n provides credential management for common services:

1. **HTTP Auth:**
   - Basic Auth
   - Digest Auth
   - Header Auth
   - OAuth1/OAuth2

2. **Database:**
   - PostgreSQL
   - MySQL
   - MongoDB
   - Redis

3. **Cloud Services:**
   - AWS
   - Google Cloud
   - Azure

### Creating Credentials

**Via UI:**
1. Go to Settings → Credentials
2. Click "New"
3. Select credential type
4. Enter values using environment variables:
   ```
   ${AI_BRAIN_API_KEY}
   ```

**Via Environment Variables:**

```bash
# n8n automatically loads credentials from env vars
N8N_CREDENTIALS_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# Custom credential mapping
N8N_CUSTOM_CREDENTIALS_AI_BRAIN='{"type":"httpHeaderAuth","name":"AI Brain API Key","data":{"name":"Authorization","value":"Bearer ${AI_BRAIN_API_KEY}"}}'
```

### Credential Sharing

Control which workflows can access credentials:

```json
{
  "name": "AI Brain API Key",
  "type": "httpHeaderAuth",
  "data": {
    "name": "Authorization",
    "value": "Bearer ${AI_BRAIN_API_KEY}"
  },
  "nodesAccess": [
    {
      "nodeType": "n8n-nodes-base.httpRequest"
    }
  ]
}
```

## 🔄 Credential Rotation

### Manual Rotation

1. **Generate new credential**
2. **Update in secret store**
3. **Update n8n credentials**
4. **Test workflows**
5. **Deactivate old credential**

```bash
# Rotation script
#!/bin/bash

# Generate new API key (example)
NEW_KEY=$(openssl rand -hex 32)

# Update in Vault
vault kv put secret/n8n/ai-brain \
  api_key=$NEW_KEY \
  url=https://ai-brain.example.com

# Restart n8n to pick up new value
kubectl rollout restart deployment/n8n -n n8n-production

# Wait for rollout
kubectl rollout status deployment/n8n -n n8n-production

# Test
curl -H "Authorization: Bearer $NEW_KEY" https://ai-brain.example.com/health

echo "Credential rotated successfully"
```

### Automated Rotation

**Using Vault Dynamic Secrets:**

```hcl
# Enable database secrets engine
vault secrets enable database

# Configure PostgreSQL
vault write database/config/n8n-postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="n8n" \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/n8n" \
  username="vault" \
  password="vault-password"

# Create role
vault write database/roles/n8n \
  db_name=n8n-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE n8n_user;" \
  default_ttl="1h" \
  max_ttl="24h"

# n8n will fetch new credentials automatically
```

**Using AWS Secrets Manager:**

```json
{
  "RotationLambdaARN": "arn:aws:lambda:region:account:function:rotate-secret",
  "RotationRules": {
    "AutomaticallyAfterDays": 30
  }
}
```

## 🛡️ Security Best Practices

### 1. Principle of Least Privilege

```yaml
# IAM policy example - minimal permissions
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:n8n/*"
    }
  ]
}
```

### 2. Network Segmentation

```yaml
# Only allow n8n to access secrets
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: n8n-secrets-access
spec:
  podSelector:
    matchLabels:
      app: n8n
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: vault
    ports:
    - protocol: TCP
      port: 8200
```

### 3. Audit Logging

```bash
# Enable Vault audit logging
vault audit enable file file_path=/vault/logs/audit.log

# Monitor access
tail -f /vault/logs/audit.log | jq 'select(.request.path | contains("n8n"))'
```

### 4. Secret Scanning

**Pre-commit hook:**

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Check for secrets in staged files
if git diff --cached --name-only | xargs grep -E '(api[_-]?key|password|secret|token).*[:=].*["\'][^$]' > /dev/null; then
  echo "Error: Potential secret found in commit"
  echo "Use environment variables instead"
  exit 1
fi
```

**CI/CD scanning:**

```yaml
# .github/workflows/secret-scan.yml
- name: Run secret scan
  uses: trufflesecurity/trufflehog@main
  with:
    path: ./
    base: ${{ github.event.repository.default_branch }}
    head: HEAD
```

## 📋 Secret Inventory

Maintain an inventory of all secrets:

```markdown
# secrets-inventory.md

| Secret Name | Type | Storage | Rotation Schedule | Owner |
|-------------|------|---------|-------------------|-------|
| AI Brain API Key | API Key | Vault | 90 days | DevOps |
| Redis Password | Password | K8s Secret | 30 days | DevOps |
| n8n Encryption Key | Encryption | Environment | Yearly | Security |
| Webhook Secret | HMAC | Vault | 90 days | DevOps |
| Slack Webhook | Webhook URL | Vault | On-demand | DevOps |
```

## 🔍 Troubleshooting

### Secret Not Found

```bash
# Check environment variable
docker exec n8n printenv | grep AI_BRAIN_API_KEY

# Check Vault
vault kv get secret/n8n/ai-brain

# Check K8s secret
kubectl get secret n8n-credentials -o json | jq '.data | map_values(@base64d)'
```

### Permission Denied

```bash
# Check Vault token
vault token lookup

# Check K8s RBAC
kubectl auth can-i get secrets --as=system:serviceaccount:n8n-production:n8n

# Check IAM role
aws sts get-caller-identity
```

### Credential Mismatch

```bash
# Test credential directly
curl -H "Authorization: Bearer $API_KEY" $API_URL/health

# Check n8n credential configuration
# (use n8n UI to test credential)

# Review logs
docker logs n8n | grep credential
```

## 📚 References

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)
- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [n8n Credential Documentation](https://docs.n8n.io/credentials/)

## 🔄 Secret Lifecycle

```mermaid
graph LR
    A[Create Secret] --> B[Store in Vault]
    B --> C[Configure n8n]
    C --> D[Use in Workflow]
    D --> E{Rotation Due?}
    E -->|Yes| F[Generate New]
    F --> B
    E -->|No| D
    D --> G{Compromised?}
    G -->|Yes| H[Revoke]
    H --> F
    G -->|No| D
```

## ✅ Checklist

- [ ] All secrets stored securely (Vault/AWS/K8s)
- [ ] No secrets in git repository
- [ ] Environment variables configured
- [ ] n8n credentials created and tested
- [ ] Rotation schedule defined
- [ ] Audit logging enabled
- [ ] Secret scanning in CI/CD
- [ ] Access controls configured
- [ ] Documentation updated
- [ ] Team trained on procedures
