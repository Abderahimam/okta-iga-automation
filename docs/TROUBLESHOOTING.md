# Troubleshooting Guide

Common issues, error messages, and solutions for the Okta IGA Automation toolkit.

---

## Table of Contents

1. [Authentication Issues](#authentication-issues)
2. [PowerShell Script Issues](#powershell-script-issues)
3. [Python Script Issues](#python-script-issues)
4. [Event Hook Issues](#event-hook-issues)
5. [SCIM Provisioning Issues](#scim-provisioning-issues)
6. [Rate Limiting Issues](#rate-limiting-issues)
7. [Audit Reporting Issues](#audit-reporting-issues)
8. [Getting Help](#getting-help)

---

## Authentication Issues

### Error: `HTTP 401 – Invalid token`

**Symptoms:**
```
OktaApiError: [GET /api/v1/users/me] HTTP 401: Invalid token provided
```

**Causes & Fixes:**
1. **Expired token** – API tokens do not expire by default, but can be manually revoked.  
   _Fix_: Generate a new token in Okta Admin → Settings → API → Tokens.

2. **Wrong domain** – Token is from a different Okta organisation.  
   _Fix_: Verify `OKTA_DOMAIN` matches the org the token was created in.

3. **Token truncated** – Secret was copied with leading/trailing whitespace.  
   _Fix_: Trim the token value before storing.

```powershell
# Verify token is valid
$headers = @{ Authorization = "SSWS $env:OKTA_API_TOKEN"; Accept = "application/json" }
Invoke-RestMethod -Uri "https://$env:OKTA_DOMAIN/api/v1/users/me" -Headers $headers
```

---

### Error: `HTTP 403 – Access denied`

**Symptoms:**
```
OktaApiError: [POST /api/v1/users] HTTP 403: You do not have permission to perform the requested action
```

**Causes & Fixes:**
1. **Insufficient admin role** – The service account lacks required permissions.  
   _Fix_: Assign the correct Okta admin role (see [SECURITY_HARDENING.md](SECURITY_HARDENING.md)).

2. **IP restriction** – The source IP is not in the allowed network zone.  
   _Fix_: Add the automation server IP to the Okta Network Zone allow-list.

---

## PowerShell Script Issues

### Error: `Could not load file or assembly`

**Symptoms:**
```
Could not load file or assembly 'System.Web, Version=4.0.0.0'
```

**Fix:** This script requires PowerShell 7.2+.

```powershell
$PSVersionTable.PSVersion  # Verify version
# Install PowerShell 7 from https://aka.ms/powershell
```

---

### Error: `Invoke-RestMethod: The underlying connection was closed`

**Symptoms:**
```
Invoke-RestMethod : The underlying connection was closed: Could not establish trust relationship for the SSL/TLS secure channel.
```

**Fix:** Enforce TLS 1.2 at the start of your script:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```

---

### Error: `Cannot convert SecureString`

**Symptoms:**
```
Cannot bind parameter 'ApiToken'. Cannot convert the "plain-text" value of type "String" to type "System.Security.SecureString".
```

**Fix:** Always pass the API token as a `SecureString`:

```powershell
# Convert a plain-text token to SecureString
$token = ConvertTo-SecureString $env:OKTA_API_TOKEN -AsPlainText -Force

.\user-provisioning.ps1 -ApiToken $token ...
```

---

### Script Runs with `-WhatIf` But Makes No Changes

**Expected behaviour** – The scripts use `SupportsShouldProcess`. Use `-WhatIf` to preview actions and omit it for real execution.

```powershell
# Preview only
.\user-provisioning.ps1 -Action Create ... -WhatIf

# Execute for real
.\user-provisioning.ps1 -Action Create ...
```

---

## Python Script Issues

### `ModuleNotFoundError: No module named 'requests'`

**Fix:**

```bash
pip install -r config/requirements.txt
# Or install manually
pip install requests flask
```

---

### `OktaApiError: [GET /api/v1/users] HTTP 400: The filter expression is invalid`

**Causes & Fixes:**

1. **Unencoded filter** – The filter must be URL-encoded when passed as a query parameter.  
   The `OktaClient` handles this automatically. If you're constructing URLs manually, use `urllib.parse.quote`.

2. **Invalid filter syntax** – Check the [Okta filter syntax](https://developer.okta.com/docs/reference/core-okta-api/#filter).

```python
# Correct filter syntax
users = client.list_users(filter_expr='status eq "ACTIVE"')
# NOT: filter_expr='status="ACTIVE"'
```

---

### `SSLError: HTTPSConnectionPool ... certificate verify failed`

**Fix:** Never disable SSL verification. Install up-to-date CA certificates:

```bash
pip install --upgrade certifi
# On RHEL/CentOS:
sudo update-ca-trust
# On Ubuntu/Debian:
sudo update-ca-certificates
```

---

### `ConnectionError: Failed to establish a new connection`

**Causes:**
1. Wrong `OKTA_DOMAIN` – should be `your-org.okta.com`, not `https://your-org.okta.com`
2. Firewall blocking outbound HTTPS to Okta

```python
# Correct
client = OktaClient(domain="your-org.okta.com", api_token="...")
# Wrong
client = OktaClient(domain="https://your-org.okta.com", api_token="...")
```

---

## Event Hook Issues

### Okta Verification Fails During Registration

**Symptoms:** Okta reports "Verification failed" when registering the event hook.

**Checklist:**
1. Endpoint is publicly accessible (use `curl` from an external machine to verify)
2. Endpoint responds to `GET /okta/events?challenge=xxx` with `{"verification": "xxx"}`
3. TLS certificate is valid (use [SSL Labs](https://www.ssllabs.com/ssltest/) to check)
4. Firewall allows inbound traffic from [Okta IP ranges](https://help.okta.com/en-us/content/topics/security/ip-address-allow-listing.htm)

```bash
# Test verification endpoint
curl "https://your-hook-endpoint/okta/events?challenge=test123"
# Expected: {"verification": "test123"}
```

---

### Events Not Being Received

**Checklist:**
1. Hook is in **ACTIVE** status in Okta Admin → Workflow → Event Hooks
2. Subscribed to the correct event types
3. Check hook delivery history in Okta Admin Console
4. Verify your endpoint logs are showing incoming requests
5. Check for 5xx errors in the hook delivery log

---

### Signature Verification Failures

**Symptoms:**
```
WARNING: Signature mismatch. Rejecting request.
```

**Fix:**
1. Verify `OKTA_HOOK_SECRET` matches the secret configured in Okta
2. Ensure you're hashing the **raw request body bytes**, not a decoded string
3. Verify the correct header name is being read (`x-okta-signature` or as configured)

```python
# Read raw bytes for HMAC – do NOT decode first
payload = request.get_data()  # bytes
sig     = request.headers.get("x-okta-signature", "")
```

---

## SCIM Provisioning Issues

### User Already Exists (409 Conflict)

**Symptoms:**
```
ScimError: HTTP 409: User already exists in the target application
```

**Fix:** Use `find_user_by_username` before creating to check for existing users:

```python
existing = provisioner.find_user_by_username("user@company.com")
if existing:
    provisioner.update_user(existing["id"], new_data)
else:
    provisioner.create_user(new_data)
```

---

### SCIM PATCH Not Applying

**Symptoms:** PATCH request returns 200 but attribute is not updated.

**Fix:** Verify the PATCH operation path matches the SCIM schema attribute name:

```python
# Correct SCIM attribute paths
{"op": "replace", "path": "active",           "value": False}
{"op": "replace", "path": "name.givenName",   "value": "John"}
{"op": "replace", "path": "emails[type eq \"work\"].value", "value": "new@co.com"}
```

---

## Rate Limiting Issues

### Frequent `HTTP 429 – Rate limit exceeded`

**Symptoms:**
```
OktaRateLimitError: Rate limit exceeded after 3 retries.
```

**Solutions:**
1. Add delays between bulk operations
2. Reduce batch size
3. Spread bulk operations across multiple time windows
4. Use Okta's bulk API endpoints where available

```python
import time

users = client.list_users()
for i, user in enumerate(users):
    # process user...
    if i % 50 == 0:
        time.sleep(1)  # Small delay every 50 operations
```

---

## Audit Reporting Issues

### Report Contains No Events

**Causes:**
1. Date range outside of Okta's log retention window (90 days by default)
2. Event type filter too restrictive
3. Okta system log indexing delay (up to 30 minutes)

**Fix:**

```powershell
# Check with a broader date range and no event filter
.\okta-audit-reporting.ps1 `
    -OktaDomain $domain `
    -ApiToken $token `
    -StartDate (Get-Date).AddHours(-1) `
    -EventTypes @()  # No filter = all events
```

---

### Large Report Times Out

**Fix:** Reduce the date range and run reports incrementally:

```powershell
# Run daily reports instead of monthly
for ($day = 30; $day -ge 1; $day--) {
    $start = (Get-Date).AddDays(-$day).Date
    $end   = $start.AddDays(1)
    .\okta-audit-reporting.ps1 -StartDate $start -EndDate $end -OutputPath ".\reports\daily"
}
```

---

## Getting Help

1. Check the [Okta Developer Community](https://devforum.okta.com)
2. Review [Okta Status Page](https://status.okta.com) for outages
3. Search [Okta Help Center](https://help.okta.com)
4. Open an issue in this repository with:
   - Script name and version
   - Full error message (redact any tokens/secrets)
   - Steps to reproduce
   - Okta tenant type (Classic Engine / Identity Engine)
