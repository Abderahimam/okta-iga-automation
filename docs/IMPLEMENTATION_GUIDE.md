# Implementation Guide

Step-by-step instructions for deploying the Okta IGA Automation toolkit in your enterprise environment.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Configuration](#configuration)
4. [PowerShell Scripts Setup](#powershell-scripts-setup)
5. [Python Scripts Setup](#python-scripts-setup)
6. [Event Hook Deployment](#event-hook-deployment)
7. [Testing & Validation](#testing--validation)
8. [Production Deployment](#production-deployment)

---

## Prerequisites

### Okta Requirements
- Okta Workforce Identity Cloud (WIC) or Customer Identity Cloud (CIC) tenant
- Okta Administrator account with the following permissions:
  - **Super Administrator** or
  - **Org Administrator** + **Application Administrator** + **Group Administrator**
- Okta API token (Settings → API → Tokens → Create Token)

### System Requirements

| Component | Minimum Version |
|-----------|----------------|
| PowerShell | 7.2+ |
| Python | 3.10+ |
| pip | 23+ |
| Docker (optional) | 24+ |

### Network Requirements
- Outbound HTTPS (443) access to `*.okta.com`
- Inbound HTTPS access to your event hook endpoint (for Event Hooks)

---

## Environment Setup

### 1. Clone the Repository

```bash
git clone https://github.com/Abderahimam/okta-iga-automation.git
cd okta-iga-automation
```

### 2. Create Required Directories

```bash
mkdir -p logs reports data
```

### 3. Install Python Dependencies

```bash
python -m venv .venv
source .venv/bin/activate          # Linux/macOS
# .venv\Scripts\Activate.ps1       # Windows
pip install --upgrade pip
pip install -r config/requirements.txt
```

### 4. Configure Environment Variables

Create a `.env` file (never commit this file):

```bash
cp config/config-example.json config/config.json
```

Set the following environment variables:

```bash
# Okta API credentials
export OKTA_DOMAIN="your-org.okta.com"
export OKTA_API_TOKEN="your-api-token-here"

# Event Hook security
export OKTA_HOOK_SECRET="your-hmac-secret-here"

# Optional: SCIM endpoint
export SCIM_BASE_URL="https://your-org.okta.com/scim/v2"
export SCIM_BEARER_TOKEN="your-scim-token"
```

On Windows (PowerShell):

```powershell
$env:OKTA_DOMAIN    = "your-org.okta.com"
$env:OKTA_API_TOKEN = "your-api-token-here"
```

---

## Configuration

### config/config.json

Copy and edit `config/config-example.json`:

```json
{
  "okta": {
    "domain": "your-org.okta.com",
    "api_token_env": "OKTA_API_TOKEN"
  },
  "provisioning": {
    "default_groups": ["Everyone", "New Hires"],
    "temp_password_length": 16,
    "send_welcome_email": true
  },
  "mfa": {
    "required_factors": ["okta_verify"],
    "grace_period_days": 7
  },
  "reporting": {
    "output_dir": "./reports",
    "retention_days": 90,
    "format": "CSV"
  }
}
```

---

## PowerShell Scripts Setup

### Install the Okta PowerShell Module (optional)

```powershell
Install-Module -Name Microsoft.PowerShell.SecretManagement -Scope CurrentUser
Install-Module -Name Microsoft.PowerShell.SecretStore -Scope CurrentUser
Register-SecretVault -Name OktaVault -ModuleName Microsoft.PowerShell.SecretStore
Set-Secret -Vault OktaVault -Name OktaApiToken -Secret "your-token"
```

### Create a User

```powershell
$token = Get-Secret -Vault OktaVault -Name OktaApiToken -AsPlainText | ConvertTo-SecureString -AsPlainText -Force

.\powershell-scripts\user-provisioning.ps1 `
    -Action Create `
    -OktaDomain "your-org.okta.com" `
    -ApiToken $token `
    -UserData @{
        login       = "jdoe@company.com"
        firstName   = "John"
        lastName    = "Doe"
        email       = "jdoe@company.com"
        department  = "Engineering"
        title       = "Software Engineer"
    }
```

### Deactivate a User

```powershell
.\powershell-scripts\user-provisioning.ps1 `
    -Action Deactivate `
    -OktaDomain "your-org.okta.com" `
    -ApiToken $token `
    -UserId "00u1abcdefGHIJKLMNOP"
```

### Run MFA Compliance Check

```powershell
.\powershell-scripts\mfa-policy-enforcement.ps1 `
    -Action EnforceCompliance `
    -OktaDomain "your-org.okta.com" `
    -ApiToken $token
```

### Generate Audit Report

```powershell
.\powershell-scripts\okta-audit-reporting.ps1 `
    -OktaDomain "your-org.okta.com" `
    -ApiToken $token `
    -StartDate (Get-Date).AddDays(-30) `
    -OutputPath ".\reports" `
    -OutputFormat CSV
```

---

## Python Scripts Setup

### Using the Okta API Client

```python
import os
from python_scripts.okta_api_client import OktaClient

client = OktaClient(
    domain=os.environ["OKTA_DOMAIN"],
    api_token=os.environ["OKTA_API_TOKEN"],
)

# Check connectivity
assert client.ping(), "Cannot reach Okta API"

# Create a user
user = client.create_user(
    profile={
        "login":      "jsmith@company.com",
        "firstName":  "Jane",
        "lastName":   "Smith",
        "email":      "jsmith@company.com",
        "department": "Finance",
    }
)
print(f"Created user: {user['id']}")
```

### SCIM Provisioning

```python
from python_scripts.scim_provisioning import ScimProvisioner

provisioner = ScimProvisioner(
    scim_base_url=os.environ["SCIM_BASE_URL"],
    bearer_token=os.environ["SCIM_BEARER_TOKEN"],
)

# Sync users from a source list
results = provisioner.sync_users_from_source([
    {
        "userName":  "alice@company.com",
        "name":      {"givenName": "Alice", "familyName": "Williams"},
        "emails":    [{"value": "alice@company.com", "primary": True}],
        "department": "HR",
    }
])
print(results)
```

---

## Event Hook Deployment

### Local Testing

```bash
cd python-scripts
export OKTA_HOOK_SECRET="test-secret"
python event_hook_handler.py
# Server starts on http://localhost:8080
```

Use [ngrok](https://ngrok.com) or [localtunnel](https://localtunnel.me) to expose locally for Okta verification:

```bash
ngrok http 8080
```

### Register the Hook in Okta

1. Navigate to **Workflow → Event Hooks** in the Okta Admin Console
2. Click **Create Event Hook**
3. Enter the public URL: `https://your-ngrok-url.ngrok.io/okta/events`
4. Add the authentication header: `x-okta-signature: <your-shared-secret>`
5. Subscribe to events: `user.lifecycle.create`, `user.lifecycle.deactivate`, etc.
6. Click **Verify** – Okta will send a GET request to your endpoint
7. Click **Save & Activate**

### Docker Deployment

```bash
docker build -t okta-event-hooks ./python-scripts
docker run -d \
  -p 8080:8080 \
  -e OKTA_HOOK_SECRET="your-secret" \
  -e OKTA_DOMAIN="your-org.okta.com" \
  -e OKTA_API_TOKEN="your-token" \
  --name okta-hooks \
  okta-event-hooks
```

---

## Testing & Validation

### Validate PowerShell Connectivity

```powershell
# Test API token is valid
$headers = @{ Authorization = "SSWS $env:OKTA_API_TOKEN"; Accept = "application/json" }
Invoke-RestMethod -Uri "https://$env:OKTA_DOMAIN/api/v1/users/me" -Headers $headers
```

### Validate Python Connectivity

```python
from python_scripts.okta_api_client import OktaClient
client = OktaClient(domain=os.environ["OKTA_DOMAIN"], api_token=os.environ["OKTA_API_TOKEN"])
print("Connected:", client.ping())
```

### Test Event Hook

```bash
curl -X POST http://localhost:8080/okta/events \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "events": [{
        "eventType": "user.lifecycle.create",
        "actor": {"alternateId": "admin@company.com"},
        "target": [{"alternateId": "newuser@company.com"}]
      }]
    }
  }'
```

---

## Production Deployment

See [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md) for full production deployment instructions including:

- Azure/AWS hosting options
- TLS certificate management
- Secret management (Azure Key Vault, AWS Secrets Manager, HashiCorp Vault)
- Monitoring and alerting
- High-availability configuration
- CI/CD pipeline integration

---

## Next Steps

- Review [SECURITY_HARDENING.md](SECURITY_HARDENING.md) before deploying to production
- Complete the [COMPLIANCE_CHECKLIST.md](COMPLIANCE_CHECKLIST.md) for your regulatory requirements
- Consult the [API_REFERENCE.md](API_REFERENCE.md) for available endpoints
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if you encounter issues
