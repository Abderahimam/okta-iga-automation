# Okta IGA Automation

> **Production-ready Identity Governance & Administration (IGA) automation toolkit for Okta Workforce Identity Cloud.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-7.2%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue.svg)](https://www.python.org/)

Automate user lifecycle management (Joiner-Mover-Leaver), MFA policy enforcement, access request workflows, SCIM 2.0 provisioning, and compliance audit reporting using the Okta Management API.

---

## ✨ Features

- **User Lifecycle Automation** – Create, update, deactivate, suspend, and reactivate Okta user accounts
- **MFA Policy Enforcement** – Manage MFA enrollment policies and run compliance checks
- **Access Request Workflows** – Multi-stage approval workflows for group and application access
- **Audit & Compliance Reporting** – Export system logs in CSV/JSON for SOX, GDPR, and NIST
- **SCIM 2.0 Provisioning** – Bi-directional synchronisation with HR systems and identity sources
- **Event Hook Processing** – Real-time automation triggered by Okta identity events
- **Retry Logic & Rate Limiting** – Production-grade error handling with exponential back-off

---

## 📁 Repository Structure

```
okta-iga-automation/
├── powershell-scripts/
│   ├── user-provisioning.ps1          # User lifecycle management (JML)
│   ├── mfa-policy-enforcement.ps1     # MFA policies & compliance checks
│   ├── okta-audit-reporting.ps1       # Audit log export & reporting
│   └── access-request-automation.ps1 # Access request workflow automation
│
├── python-scripts/
│   ├── okta_api_client.py             # Okta Management API client library
│   ├── scim_provisioning.py           # SCIM 2.0 provisioning automation
│   └── event_hook_handler.py          # Event hook processing (Flask)
│
├── docs/
│   ├── IMPLEMENTATION_GUIDE.md        # Step-by-step setup instructions
│   ├── SECURITY_HARDENING.md          # Security best practices & checklist
│   ├── COMPLIANCE_CHECKLIST.md        # SOX, GDPR, NIST requirements
│   ├── API_REFERENCE.md               # Okta API endpoints reference
│   └── TROUBLESHOOTING.md             # Common issues & solutions
│
├── config/
│   ├── config-example.json            # Sample configuration (copy to config.json)
│   ├── access-request-workflow.json   # Access request workflow template
│   ├── lifecycle-automation.json      # JML workflow template
│   ├── mfa-policy.json                # MFA policy example
│   └── requirements.txt               # Python dependencies
│
├── .gitignore
├── CONTRIBUTING.md
├── DEPLOYMENT_GUIDE.md
├── LICENSE
└── README.md
```

---

## 🚀 Quick Start

### Prerequisites

| Tool | Version |
|------|---------|
| PowerShell | 7.2+ |
| Python | 3.10+ |
| Okta API Token | Admin scope |

### 1. Clone & Install

```bash
git clone https://github.com/Abderahimam/okta-iga-automation.git
cd okta-iga-automation
python -m venv .venv && source .venv/bin/activate
pip install -r config/requirements.txt
```

### 2. Configure

```bash
cp config/config-example.json config/config.json
export OKTA_DOMAIN="your-org.okta.com"
export OKTA_API_TOKEN="your-api-token"
```

### 3. Create a User (PowerShell)

```powershell
$token = ConvertTo-SecureString $env:OKTA_API_TOKEN -AsPlainText -Force

.\powershell-scripts\user-provisioning.ps1 `
    -Action Create `
    -OktaDomain $env:OKTA_DOMAIN `
    -ApiToken $token `
    -UserData @{
        login      = "jdoe@company.com"
        firstName  = "John"
        lastName   = "Doe"
        department = "Engineering"
    }
```

### 4. Use the Python API Client

```python
from python_scripts.okta_api_client import OktaClient
import os

client = OktaClient(
    domain=os.environ["OKTA_DOMAIN"],
    api_token=os.environ["OKTA_API_TOKEN"],
)
users = client.list_users(filter_expr='status eq "ACTIVE"')
print(f"Active users: {len(users)}")
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md) | Step-by-step setup and deployment |
| [Security Hardening](docs/SECURITY_HARDENING.md) | Security best practices & checklist |
| [Compliance Checklist](docs/COMPLIANCE_CHECKLIST.md) | SOX, GDPR, NIST requirements |
| [API Reference](docs/API_REFERENCE.md) | Okta API endpoints & examples |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Common issues & solutions |
| [Deployment Guide](DEPLOYMENT_GUIDE.md) | Azure, AWS, on-premises deployment |
| [Contributing](CONTRIBUTING.md) | Contribution guidelines |

---

## 🔐 Security

- API tokens are loaded from environment variables or a secret manager — **never hardcoded**
- All scripts use `SecureString` for sensitive parameters
- HMAC-SHA256 signature verification on event hooks
- TLS 1.2+ enforced for all API calls
- See [SECURITY_HARDENING.md](docs/SECURITY_HARDENING.md) for the full checklist

**Found a security vulnerability?** Please report it privately — see [CONTRIBUTING.md](CONTRIBUTING.md#security-vulnerabilities).

---

## 📋 Compliance

This toolkit supports compliance with:

| Framework | Coverage |
|-----------|---------|
| **SOX** | Access certification, change management, audit trails |
| **GDPR** | Right to erasure, data minimisation, breach notification |
| **NIST CSF** | Identify, Protect, Detect, Respond, Recover functions |
| **ISO 27001** | Access control (Annex A.9), audit logging (A.12.4) |

---

## 🤝 Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) and open a Pull Request.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
