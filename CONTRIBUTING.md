# Contributing to Okta IGA Automation

Thank you for your interest in contributing! This guide covers how to report issues, propose changes, and submit pull requests.

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Reporting Issues](#reporting-issues)
3. [Development Setup](#development-setup)
4. [Submitting Changes](#submitting-changes)
5. [Code Style](#code-style)
6. [Testing](#testing)
7. [Security Vulnerabilities](#security-vulnerabilities)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you agree to uphold this standard.

---

## Reporting Issues

1. **Search existing issues** before opening a new one
2. Use the appropriate issue template:
   - **Bug Report**: For unexpected behaviour or errors
   - **Feature Request**: For new functionality or improvements
   - **Security Vulnerability**: See [Security Vulnerabilities](#security-vulnerabilities) below

### Bug Report Checklist

- [ ] Include the script name and version
- [ ] Provide the full error message (redact any secrets or tokens)
- [ ] Include steps to reproduce
- [ ] Specify your environment (OS, PowerShell/Python version, Okta tenant type)

---

## Development Setup

### Prerequisites

- PowerShell 7.2+
- Python 3.10+
- Git

### Local Setup

```bash
# Fork and clone the repository
git clone https://github.com/YOUR_USERNAME/okta-iga-automation.git
cd okta-iga-automation

# Create a Python virtual environment
python -m venv .venv
source .venv/bin/activate   # Linux/macOS
# .venv\Scripts\Activate.ps1  # Windows

# Install dependencies
pip install -r config/requirements.txt

# Copy example config
cp config/config-example.json config/config.json
# Edit config.json with your Okta test tenant values
```

---

## Submitting Changes

### Workflow

1. **Fork** the repository
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-number-short-description
   ```
3. **Make your changes** following the [Code Style](#code-style) guidelines
4. **Test your changes** (see [Testing](#testing))
5. **Commit** with a descriptive message:
   ```bash
   git commit -m "feat: add bulk deprovisioning support to access-request script"
   ```
6. **Push** and open a Pull Request

### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `security`

**Examples:**
```
feat(user-provisioning): add support for Suspend action
fix(okta-api-client): handle 429 rate limit with exponential back-off
docs(security-hardening): add HashiCorp Vault secret retrieval example
security(event-hook): enforce HMAC signature verification
```

### Pull Request Checklist

- [ ] Branch is up to date with `main`
- [ ] Code follows project style guidelines
- [ ] Tests pass (see below)
- [ ] Documentation updated if needed
- [ ] No secrets or tokens committed
- [ ] Security review completed for authentication/authorisation changes

---

## Code Style

### Python

- Follow [PEP 8](https://pep8.org/) and [PEP 257](https://peps.python.org/pep-0257/) docstring conventions
- Use type annotations for all public functions
- Maximum line length: 100 characters
- Use `ruff` for linting:

```bash
pip install ruff
ruff check python-scripts/
```

### PowerShell

- Follow [PowerShell Best Practices and Style Guide](https://poshcode.gitbook.io/powershell-practice-and-style/)
- Use `[CmdletBinding()]` and `[Parameter()]` attributes
- Use `SupportsShouldProcess` for all state-changing operations
- Use `Write-Verbose` / `Write-Log` instead of `Write-Host` for non-interactive output
- Use `SecureString` for sensitive parameters

### JSON Configuration Files

- 2-space indentation
- Include `$schema` and `version` fields
- Comment fields using `_comment` keys (JSON does not support comments)

---

## Testing

### Python Tests

```bash
cd okta-iga-automation
python -m pytest --tb=short -v
```

### PowerShell Tests (Pester)

```powershell
Install-Module -Name Pester -Force
Invoke-Pester -Path .\tests\ -Output Detailed
```

### Testing Against a Real Okta Tenant

Use a **dedicated test Okta tenant** (never test against production):

1. Sign up for a free [Okta Developer tenant](https://developer.okta.com/signup/)
2. Create a test API token
3. Set environment variables:
   ```bash
   export OKTA_DOMAIN="dev-XXXXXXX.okta.com"
   export OKTA_API_TOKEN="your-dev-token"
   ```

### Test Coverage

- New features should include unit tests
- Bug fixes should include a regression test
- Target 80%+ code coverage for Python modules

---

## Security Vulnerabilities

**Do NOT open a public issue for security vulnerabilities.**

Please report security issues by emailing the maintainer directly (see the repository security policy) or using GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability) feature.

Include:
- Affected component
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We aim to respond within 48 hours and release a patch within 7 days for critical issues.
