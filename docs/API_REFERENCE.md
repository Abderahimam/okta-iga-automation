# Okta API Reference

Quick reference for Okta Management API endpoints used by the IGA Automation toolkit.

---

## Table of Contents

1. [Authentication](#authentication)
2. [Users API](#users-api)
3. [Groups API](#groups-api)
4. [Applications API](#applications-api)
5. [Policies API](#policies-api)
6. [System Logs API](#system-logs-api)
7. [SCIM API](#scim-api)
8. [Rate Limits](#rate-limits)
9. [Error Codes](#error-codes)

---

## Authentication

All Okta Management API requests require an `Authorization` header:

```http
Authorization: SSWS {api_token}
```

For OAuth 2.0 service-to-service flows:

```http
Authorization: Bearer {access_token}
```

### Base URL

```
https://{yourOktaDomain}/api/v1
```

---

## Users API

### List Users

```http
GET /api/v1/users
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `filter` | string | [Filter expression](https://developer.okta.com/docs/reference/core-okta-api/#filter) |
| `search` | string | SCIM-filter search across profile attributes |
| `limit` | integer | Number of results (1–200, default 200) |
| `after` | string | Cursor for pagination |

**Filter Examples:**

```
status eq "ACTIVE"
profile.department eq "Engineering"
lastUpdated gt "2024-01-01T00:00:00.000Z"
```

### Get User

```http
GET /api/v1/users/{userId}
GET /api/v1/users/{login}         (login or email)
GET /api/v1/users/me              (current user)
```

### Create User

```http
POST /api/v1/users?activate=true
Content-Type: application/json

{
  "profile": {
    "firstName":   "John",
    "lastName":    "Doe",
    "email":       "jdoe@company.com",
    "login":       "jdoe@company.com",
    "department":  "Engineering",
    "title":       "Software Engineer",
    "mobilePhone": "+1-555-000-1234"
  },
  "credentials": {
    "password": { "value": "TempP@ss123!" }
  }
}
```

### Update User Profile

```http
POST /api/v1/users/{userId}
Content-Type: application/json

{
  "profile": {
    "title":      "Senior Software Engineer",
    "department": "Platform Engineering"
  }
}
```

### Lifecycle Operations

| Action | Method | Endpoint |
|--------|--------|----------|
| Activate | POST | `/api/v1/users/{id}/lifecycle/activate` |
| Reactivate | POST | `/api/v1/users/{id}/lifecycle/reactivate` |
| Deactivate | POST | `/api/v1/users/{id}/lifecycle/deactivate` |
| Suspend | POST | `/api/v1/users/{id}/lifecycle/suspend` |
| Unsuspend | POST | `/api/v1/users/{id}/lifecycle/unsuspend` |
| Reset Password | POST | `/api/v1/users/{id}/lifecycle/reset_password` |
| Expire Password | POST | `/api/v1/users/{id}/lifecycle/expire_password` |
| Delete | DELETE | `/api/v1/users/{id}` |

### User Factors (MFA)

```http
GET    /api/v1/users/{userId}/factors
POST   /api/v1/users/{userId}/factors
DELETE /api/v1/users/{userId}/factors/{factorId}
```

---

## Groups API

### List Groups

```http
GET /api/v1/groups?search=Engineering&limit=200
```

### Create Group

```http
POST /api/v1/groups
Content-Type: application/json

{
  "profile": {
    "name":        "Engineering Team",
    "description": "All engineering department members"
  }
}
```

### Group Membership

```http
# List members
GET    /api/v1/groups/{groupId}/users

# Add member
PUT    /api/v1/groups/{groupId}/users/{userId}

# Remove member
DELETE /api/v1/groups/{groupId}/users/{userId}

# List assigned apps
GET    /api/v1/groups/{groupId}/apps
```

---

## Applications API

### List Applications

```http
GET /api/v1/apps?filter=status eq "ACTIVE"
```

### Application User Management

```http
# Assign user to app
POST /api/v1/apps/{appId}/users
{
  "id":    "{userId}",
  "scope": "USER"
}

# List app users
GET /api/v1/apps/{appId}/users

# Get specific app user
GET /api/v1/apps/{appId}/users/{userId}

# Update app user profile
POST /api/v1/apps/{appId}/users/{userId}

# Remove user from app
DELETE /api/v1/apps/{appId}/users/{userId}
```

### Application Group Assignment

```http
# Assign group to app
PUT /api/v1/apps/{appId}/groups/{groupId}

# List app groups
GET /api/v1/apps/{appId}/groups

# Remove group from app
DELETE /api/v1/apps/{appId}/groups/{groupId}
```

---

## Policies API

### List Policies

```http
GET /api/v1/policies?type={policyType}
```

**Policy Types:**

| Type | Description |
|------|-------------|
| `OKTA_SIGN_ON` | Sign-on policy |
| `MFA_ENROLL` | MFA enrollment policy |
| `PASSWORD` | Password policy |
| `OAUTH_AUTHORIZATION_POLICY` | OAuth authorization policy |

### Create Policy

```http
POST /api/v1/policies
Content-Type: application/json

{
  "type":   "MFA_ENROLL",
  "name":   "Corporate MFA Policy",
  "status": "ACTIVE",
  "settings": {
    "authenticators": [
      { "key": "okta_verify",  "enroll": { "self": "REQUIRED" } },
      { "key": "okta_email",   "enroll": { "self": "OPTIONAL" } }
    ]
  }
}
```

### Policy Rules

```http
GET    /api/v1/policies/{policyId}/rules
POST   /api/v1/policies/{policyId}/rules
GET    /api/v1/policies/{policyId}/rules/{ruleId}
PUT    /api/v1/policies/{policyId}/rules/{ruleId}
DELETE /api/v1/policies/{policyId}/rules/{ruleId}
```

---

## System Logs API

### Query Logs

```http
GET /api/v1/logs?since={iso8601}&until={iso8601}&filter={filterExpr}&limit=1000
```

| Parameter | Description |
|-----------|-------------|
| `since` | Start time (ISO 8601, e.g. `2024-01-01T00:00:00.000Z`) |
| `until` | End time (ISO 8601) |
| `filter` | Event type filter, e.g. `eventType eq "user.lifecycle.create"` |
| `q` | URL-encoded search query |
| `limit` | Max results per page (1–1000, default 100) |
| `sortOrder` | `ASCENDING` or `DESCENDING` |

**Common Event Types:**

| Event Type | Description |
|-----------|-------------|
| `user.lifecycle.create` | User account created |
| `user.lifecycle.activate` | User account activated |
| `user.lifecycle.deactivate` | User account deactivated |
| `user.lifecycle.delete.completed` | User account deleted |
| `user.session.start` | User login |
| `user.session.end` | User logout |
| `user.authentication.sso` | SSO authentication |
| `user.mfa.factor.activate` | MFA factor enrolled |
| `user.account.privilege.escalate` | Privilege escalation |
| `policy.lifecycle.create` | Policy created |
| `policy.lifecycle.update` | Policy updated |
| `policy.lifecycle.delete` | Policy deleted |
| `system.api_token.create` | API token created |
| `system.api_token.revoke` | API token revoked |

---

## SCIM API

### SCIM 2.0 Base URL

```
https://{yourOktaDomain}/scim/v2
```

### User Endpoints

```http
GET    /scim/v2/Users
GET    /scim/v2/Users/{id}
POST   /scim/v2/Users
PUT    /scim/v2/Users/{id}
PATCH  /scim/v2/Users/{id}
DELETE /scim/v2/Users/{id}
```

### SCIM Filter Examples

```
userName eq "jdoe@company.com"
active eq true
emails.value co "@company.com"
```

### SCIM PATCH Operations

```json
{
  "schemas": ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
  "Operations": [
    { "op": "replace", "path": "active",           "value": false        },
    { "op": "replace", "path": "name.givenName",   "value": "Jonathan"   },
    { "op": "add",     "path": "emails",            "value": [{"value":"new@co.com","primary":true}] }
  ]
}
```

---

## Rate Limits

Okta enforces rate limits per API endpoint tier. Key limits:

| Endpoint Category | Rate Limit | Window |
|------------------|------------|--------|
| Users API (read) | 600 | 1 min |
| Users API (write) | 300 | 1 min |
| Groups API | 600 | 1 min |
| System Logs API | 120 | 1 min |
| Policies API | 600 | 1 min |

When rate limited, Okta returns `HTTP 429` with a `Retry-After` header.

All scripts in this toolkit implement automatic back-off and retry.

---

## Error Codes

| HTTP Status | Error Code | Description | Resolution |
|------------|------------|-------------|------------|
| 400 | `E0000001` | Bad request / validation error | Check request payload |
| 401 | `E0000011` | Invalid token | Verify API token is valid and not expired |
| 403 | `E0000006` | Access denied | Check admin permissions |
| 404 | `E0000007` | Not found | Verify resource ID |
| 409 | `E0000001` | Conflict (e.g. duplicate login) | Use unique login |
| 429 | `E0000047` | Rate limit exceeded | Implement back-off retry |
| 500 | `E0000009` | Internal server error | Retry with back-off |

---

## Useful Links

- [Okta Developer Portal](https://developer.okta.com)
- [Okta API Reference](https://developer.okta.com/docs/reference/core-okta-api/)
- [Okta SCIM Protocol](https://developer.okta.com/docs/concepts/scim/)
- [Okta System Log API](https://developer.okta.com/docs/reference/api/system-log/)
- [Okta Rate Limits](https://developer.okta.com/docs/reference/rate-limits/)
- [Okta Error Codes](https://developer.okta.com/docs/reference/error-codes/)
