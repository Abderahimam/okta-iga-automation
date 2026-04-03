# Security Hardening Guide

Security best practices and hardening checklist for the Okta IGA Automation toolkit in enterprise environments.

---

## Table of Contents

1. [API Token Security](#api-token-security)
2. [Network Security](#network-security)
3. [Event Hook Security](#event-hook-security)
4. [Secrets Management](#secrets-management)
5. [Access Control](#access-control)
6. [Monitoring & Alerting](#monitoring--alerting)
7. [Hardening Checklist](#hardening-checklist)

---

## API Token Security

### Never Store Tokens in Code

```bash
# BAD – never do this
$token = "00TkL1xAbCdEfGhIjKlMnOpQ"

# GOOD – load from environment or secret manager
$token = $env:OKTA_API_TOKEN
```

### Use Dedicated Service Accounts

- Create a dedicated Okta admin account for automation (e.g., `svc-iga-automation@company.com`)
- Assign only the minimum required permissions (Principle of Least Privilege)
- Enable MFA on the service account
- Rotate API tokens every 90 days

### Token Rotation

```powershell
# Revoke and regenerate the API token on schedule
# Use a CI/CD secret rotation workflow or AWS/Azure secret rotation
```

### Recommended Okta Permissions

| Script | Minimum Okta Permission |
|--------|------------------------|
| user-provisioning.ps1 | User Administrator |
| mfa-policy-enforcement.ps1 | Policy Administrator |
| okta-audit-reporting.ps1 | Read-Only Administrator |
| access-request-automation.ps1 | Group Administrator |

---

## Network Security

### IP Allowlisting

Restrict Okta API access to known IP ranges in the Okta Admin Console:

1. Navigate to **Security → Networks**
2. Add your automation server IP ranges to the allow-list
3. Configure IP-based access restrictions on the API token

### TLS Requirements

- Enforce TLS 1.2+ for all HTTPS connections
- Pin certificates where possible
- Validate server certificates (never set `verify=False` in Python requests)

```python
# GOOD – always verify TLS
response = requests.get(url, verify=True)

# BAD – never disable TLS verification
response = requests.get(url, verify=False)
```

### Firewall Rules

```
# Allow outbound HTTPS to Okta
ALLOW  TCP  0.0.0.0/0 → *.okta.com:443
ALLOW  TCP  0.0.0.0/0 → *.oktacdn.com:443

# Allow inbound HTTPS to event hook endpoint only
ALLOW  TCP  Okta-IP-Ranges → your-hook-endpoint:443
DENY   ALL  0.0.0.0/0 → your-hook-endpoint:*
```

---

## Event Hook Security

### HMAC Signature Verification

Always verify the Okta signature on incoming event hooks:

```python
import hashlib
import hmac

def verify_signature(payload: bytes, secret: str, header_sig: str) -> bool:
    expected = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header_sig)
```

### HTTPS Only

- Deploy your event hook endpoint behind HTTPS with a valid TLS certificate
- Redirect all HTTP traffic to HTTPS
- Enable HTTP Strict Transport Security (HSTS)

### Request Rate Limiting

Implement rate limiting on your event hook endpoint to prevent abuse:

```python
from flask_limiter import Limiter
limiter = Limiter(app, default_limits=["100/minute", "1000/hour"])
```

---

## Secrets Management

### Azure Key Vault

```powershell
# Store and retrieve secrets from Azure Key Vault
$secret = Get-AzKeyVaultSecret -VaultName "iga-keyvault" -Name "OktaApiToken" -AsPlainText
$token  = ConvertTo-SecureString $secret -AsPlainText -Force
```

### AWS Secrets Manager

```python
import boto3
import json

def get_secret(secret_name: str, region: str = "us-east-1") -> str:
    client  = boto3.client("secretsmanager", region_name=region)
    resp    = client.get_secret_value(SecretId=secret_name)
    secrets = json.loads(resp["SecretString"])
    return secrets["okta_api_token"]
```

### HashiCorp Vault

```bash
# Retrieve secret at runtime
export OKTA_API_TOKEN=$(vault kv get -field=api_token secret/okta/iga)
```

### Environment Variables in CI/CD

- Store secrets as encrypted GitHub Actions secrets / Azure DevOps variable groups
- Never echo secrets in CI/CD logs
- Use masked variables

```yaml
# GitHub Actions example
- name: Run Okta Audit Report
  env:
    OKTA_API_TOKEN: ${{ secrets.OKTA_API_TOKEN }}
    OKTA_DOMAIN:    ${{ secrets.OKTA_DOMAIN }}
  run: |
    pwsh powershell-scripts/okta-audit-reporting.ps1 \
      -OktaDomain $env:OKTA_DOMAIN \
      -ApiToken (ConvertTo-SecureString $env:OKTA_API_TOKEN -AsPlainText -Force)
```

---

## Access Control

### Principle of Least Privilege

- Grant automation scripts only the permissions they need
- Use separate API tokens per script/function
- Regularly review and audit access

### Okta Admin Roles Assignment

```
svc-user-provisioning    → User Administrator
svc-mfa-enforcement      → Policy Administrator (Read-Only)
svc-audit-reporting      → Read-Only Administrator
svc-access-requests      → Group Administrator
```

### Service Account Lifecycle

- Disable automation accounts during maintenance windows
- Audit service account activity monthly
- Remove unused service accounts immediately

---

## Monitoring & Alerting

### Key Events to Monitor

| Event Type | Severity | Response |
|-----------|----------|----------|
| `user.account.privilege.escalate` | CRITICAL | Immediate alert |
| `policy.lifecycle.update` | HIGH | Security team review |
| `user.mfa.factor.deactivate` | HIGH | User notification |
| `system.api_token.create` | MEDIUM | Audit log |
| `user.session.start` (off-hours) | MEDIUM | Risk review |
| `user.authentication.sso` (geo-anomaly) | HIGH | Block + alert |

### Okta System Log Alerts

Configure Okta system log streaming to your SIEM:

1. Navigate to **Reports → System Log**
2. Configure **Log Streaming** to send to Splunk/Sentinel/Datadog
3. Create alert rules for the events listed above

### Audit Script Scheduling

```bash
# Run audit report daily at 06:00 UTC via cron
0 6 * * * pwsh /opt/iga/okta-audit-reporting.ps1 \
    -OktaDomain $OKTA_DOMAIN \
    -ApiToken (ConvertTo-SecureString $OKTA_API_TOKEN -AsPlainText -Force) \
    -StartDate (Get-Date).AddDays(-1) \
    -OutputPath /var/reports/okta
```

---

## Hardening Checklist

### Infrastructure

- [ ] API tokens stored in a secret manager (Vault/Key Vault/Secrets Manager)
- [ ] No secrets in source code, configuration files, or CI/CD logs
- [ ] API token rotation scheduled every 90 days
- [ ] Dedicated low-privilege service accounts per automation function
- [ ] Network egress restricted to Okta IP ranges only
- [ ] Event hook endpoint accessible only over HTTPS
- [ ] Event hook endpoint IP-restricted to Okta IP ranges
- [ ] HMAC signature verification enabled on event hook endpoint
- [ ] Rate limiting enabled on event hook endpoint

### Application

- [ ] TLS 1.2+ enforced for all outbound connections
- [ ] Certificate validation enabled (no `verify=False`)
- [ ] Retry logic with exponential back-off implemented
- [ ] Sensitive data redacted from logs (tokens, passwords, PII)
- [ ] Input validation on all external data sources
- [ ] Error handling prevents information leakage in API responses

### Okta Configuration

- [ ] Admin console protected with MFA
- [ ] API tokens have expiry configured
- [ ] Network zones configured to restrict admin console access
- [ ] Admin roles follow least-privilege model
- [ ] System log streaming enabled to SIEM
- [ ] Session policies enforce short token lifetimes for admin roles
- [ ] Okta ThreatInsight enabled
- [ ] Okta Identity Threat Protection (ITP) configured if licensed

### Compliance & Audit

- [ ] Audit logging enabled for all automation actions
- [ ] Log retention meets regulatory requirements (90+ days for SOX)
- [ ] Change management process followed for policy modifications
- [ ] Access reviews scheduled quarterly
- [ ] Incident response runbook documented
- [ ] Disaster recovery plan tested annually
