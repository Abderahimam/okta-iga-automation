# Deployment Guide

Production deployment procedures for the Okta IGA Automation toolkit.

---

## Table of Contents

1. [Deployment Architecture](#deployment-architecture)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Azure Deployment](#azure-deployment)
4. [AWS Deployment](#aws-deployment)
5. [On-Premises Deployment](#on-premises-deployment)
6. [CI/CD Pipeline](#cicd-pipeline)
7. [Monitoring & Alerting](#monitoring--alerting)
8. [Rollback Procedures](#rollback-procedures)

---

## Deployment Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Production Environment                       │
│                                                                     │
│  ┌─────────────┐     ┌──────────────┐     ┌──────────────────────┐ │
│  │  Scheduler  │────▶│  PowerShell  │────▶│     Okta API         │ │
│  │  (Cron/     │     │  Scripts     │     │  (Management API)    │ │
│  │   Azure     │     │  Container   │     └──────────────────────┘ │
│  │   Functions)│     └──────────────┘                              │
│  └─────────────┘                                                   │
│                                                                     │
│  ┌─────────────┐     ┌──────────────┐     ┌──────────────────────┐ │
│  │  API        │────▶│  Python      │────▶│     Okta SCIM /      │ │
│  │  Gateway    │     │  Event Hook  │     │     Event Hooks      │ │
│  │  (HTTPS)    │     │  Service     │     └──────────────────────┘ │
│  └─────────────┘     └──────────────┘                              │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                   Secrets Management                         │   │
│  │      Azure Key Vault / AWS Secrets Manager / Vault          │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Pre-Deployment Checklist

- [ ] Dedicated Okta service account created with minimum permissions
- [ ] API token stored in secret manager (not in environment files or code)
- [ ] TLS certificate obtained for event hook endpoint
- [ ] Network firewall rules configured (see [SECURITY_HARDENING.md](docs/SECURITY_HARDENING.md))
- [ ] Log storage and retention configured (90+ days)
- [ ] Alerting configured for failed automations
- [ ] Rollback plan documented and tested
- [ ] Change management ticket approved
- [ ] Stakeholder sign-off obtained

---

## Azure Deployment

### Event Hook Service (Azure Container Apps)

```bash
# Variables
RESOURCE_GROUP="iga-automation-rg"
LOCATION="eastus"
ACR_NAME="igaautomationacr"
APP_NAME="okta-event-hooks"
KEY_VAULT_NAME="iga-keyvault"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create Azure Container Registry
az acr create --name $ACR_NAME --resource-group $RESOURCE_GROUP --sku Basic --admin-enabled true

# Build and push Docker image
az acr build --registry $ACR_NAME --image $APP_NAME:latest ./python-scripts

# Store secrets in Key Vault
az keyvault create --name $KEY_VAULT_NAME --resource-group $RESOURCE_GROUP --location $LOCATION
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "OktaApiToken"  --value "$OKTA_API_TOKEN"
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "OktaHookSecret" --value "$OKTA_HOOK_SECRET"

# Deploy Container App
az containerapp create \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --image "$ACR_NAME.azurecr.io/$APP_NAME:latest" \
  --target-port 8080 \
  --ingress external \
  --env-vars \
    "OKTA_DOMAIN=$OKTA_DOMAIN" \
    "OKTA_API_TOKEN=secretref:okta-api-token" \
    "OKTA_HOOK_SECRET=secretref:okta-hook-secret"
```

### Scheduled Scripts (Azure Functions)

```powershell
# Deploy audit reporting as a scheduled Azure Function (Timer Trigger)
# See: https://docs.microsoft.com/azure/azure-functions/functions-bindings-timer

# Function runs daily at 06:00 UTC
# Schedule: "0 0 6 * * *" (cron expression)
```

---

## AWS Deployment

### Event Hook Service (ECS Fargate)

```bash
# Create ECR repository
aws ecr create-repository --repository-name okta-event-hooks

# Build and push image
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"
ECR_URI="$AWS_ACCOUNT.dkr.ecr.$AWS_REGION.amazonaws.com/okta-event-hooks"

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URI
docker build -t okta-event-hooks ./python-scripts
docker tag okta-event-hooks:latest $ECR_URI:latest
docker push $ECR_URI:latest

# Store secrets
aws secretsmanager create-secret --name "okta/api-token" --secret-string "$OKTA_API_TOKEN"
aws secretsmanager create-secret --name "okta/hook-secret" --secret-string "$OKTA_HOOK_SECRET"

# Deploy to ECS (use the task definition in config/)
aws ecs create-service \
  --cluster iga-automation \
  --service-name okta-event-hooks \
  --task-definition okta-event-hooks:1 \
  --desired-count 2 \
  --launch-type FARGATE
```

### Scheduled Scripts (AWS Lambda / EventBridge)

```python
# Lambda function for scheduled audit reporting
import subprocess
import os

def lambda_handler(event, context):
    result = subprocess.run(
        ["pwsh", "-File", "/var/task/okta-audit-reporting.ps1",
         "-OktaDomain", os.environ["OKTA_DOMAIN"],
         "-OutputPath", "/tmp/reports"],
        capture_output=True, text=True
    )
    return {"statusCode": 200, "body": result.stdout}
```

---

## On-Premises Deployment

### Docker Compose

```yaml
# docker-compose.yml
version: "3.9"
services:
  event-hooks:
    build:
      context: ./python-scripts
    ports:
      - "8080:8080"
    environment:
      - OKTA_DOMAIN=${OKTA_DOMAIN}
      - OKTA_API_TOKEN=${OKTA_API_TOKEN}
      - OKTA_HOOK_SECRET=${OKTA_HOOK_SECRET}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "10"
```

### Scheduled Tasks (Windows Server)

```powershell
# Create a scheduled task for daily audit reporting
$trigger = New-ScheduledTaskTrigger -Daily -At "06:00AM"
$action  = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-NonInteractive -File C:\iga\okta-audit-reporting.ps1"
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask -TaskName "Okta-Audit-Report" `
    -Trigger $trigger -Action $action -Settings $settings `
    -RunLevel Highest -User "SYSTEM"
```

### Linux Cron (systemd timer)

```ini
# /etc/systemd/system/okta-audit.service
[Unit]
Description=Okta Daily Audit Report
After=network.target

[Service]
Type=oneshot
User=iga-service
EnvironmentFile=/etc/iga/env
ExecStart=/usr/bin/pwsh /opt/iga/okta-audit-reporting.ps1 \
    -OktaDomain $OKTA_DOMAIN \
    -OutputPath /var/reports/okta

# /etc/systemd/system/okta-audit.timer
[Unit]
Description=Run Okta Audit Report daily

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl enable --now okta-audit.timer
```

---

## CI/CD Pipeline

### GitHub Actions

```yaml
# .github/workflows/okta-iga.yml
name: Okta IGA Automation

on:
  schedule:
    - cron: "0 6 * * *"  # Daily at 06:00 UTC
  workflow_dispatch:

jobs:
  audit-report:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up PowerShell
        uses: actions/setup-dotnet@v4

      - name: Run Audit Report
        env:
          OKTA_DOMAIN:    ${{ secrets.OKTA_DOMAIN }}
          OKTA_API_TOKEN: ${{ secrets.OKTA_API_TOKEN }}
        run: |
          pwsh powershell-scripts/okta-audit-reporting.ps1 \
            -OktaDomain $env:OKTA_DOMAIN \
            -ApiToken (ConvertTo-SecureString $env:OKTA_API_TOKEN -AsPlainText -Force) \
            -OutputPath ./reports

      - name: Upload Report
        uses: actions/upload-artifact@v4
        with:
          name: okta-audit-report
          path: reports/
          retention-days: 90
```

---

## Monitoring & Alerting

### Health Check Endpoint

The event hook service exposes `/healthz` for load balancer health checks:

```bash
curl https://your-endpoint/healthz
# {"status": "ok", "timestamp": "2024-01-15T06:00:00+00:00"}
```

### Key Metrics to Monitor

| Metric | Alert Threshold | Action |
|--------|----------------|--------|
| Event hook response time | > 5s | Page on-call |
| Event hook error rate | > 5% | Alert team |
| Failed user provisioning | Any | Ticket + alert |
| Failed de-provisioning | Any | Critical alert |
| Rate limit hits | > 10/hour | Tune throttling |
| Audit report failures | Any | Alert team |

---

## Rollback Procedures

### Event Hook Service

```bash
# Roll back to previous container version
docker pull your-registry/okta-event-hooks:previous-version
docker stop okta-hooks
docker run -d --name okta-hooks okta-event-hooks:previous-version
```

### Policy Changes

```powershell
# Policy changes are reversible via the Okta Admin Console or API
# Always capture the previous policy state before updating:
$previous = Get-OktaPolicy -PolicyId $policyId
$previous | ConvertTo-Json | Out-File ".\backup\policy-$policyId-$(Get-Date -Format yyyyMMdd).json"
```

### Emergency Access Restoration

If automated de-provisioning incorrectly deactivates users:

```powershell
# Bulk reactivation from a list
$affectedUsers = Import-Csv ".\data\incorrectly-deactivated.csv"
foreach ($user in $affectedUsers) {
    .\powershell-scripts\user-provisioning.ps1 `
        -Action Reactivate -OktaDomain $domain -ApiToken $token -UserId $user.OktaId
}
```
