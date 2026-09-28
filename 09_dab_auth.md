# Day 9 — DAB Entra ID Authentication

**Date:** 2026-09-28
**Database:** ProcurementDB
**Objective:** Secure DAB REST/GraphQL endpoints with Microsoft Entra ID tokens.

---

## What Was Built

| Component | Value |
| :--- | :--- |
| API app registration | dab-procurement-api |
| API Client ID | 71b03d63-6566-4576-bf73-7722de203e73 |
| Test client app | dab-test-client |
| Test client ID | af13c6d5-ca02-4b33-b559-c8979f39ae70 |
| Tenant ID | 40cba398-9515-4123-b8d6-7ed4127b8ef9 |
| Exposed scope | api://71b03d63-6566-4576-bf73-7722de203e73/access_as_user |
| DAB provider | EntraID |
| Entity permissions | authenticated:* |

---

## Authentication Flow

1. Client requests token from Entra ID for the API scope
2. Entra ID returns a signed JWT
3. Client sends request to DAB with `Authorization: Bearer <token>`
4. DAB validates the JWT against configured issuer + audience
5. DAB checks entity permissions for the authenticated role
6. If valid, request proceeds; if not, DAB returns 401/403

---

## Test Results

| Test | Result |
| :--- | :--- |
| Request without token | 403 AuthorizationCheckFailed |
| Request with valid token | 200 OK with JSON payload |
| Token length (Azure CLI) | 1983 characters |

---

## Key Learnings

### 1. Issuer Format Mismatch (v1.0 vs v2.0)

Azure CLI issues tokens with the v1.0 issuer format:
  https://sts.windows.net/{tenant-id}/

Modern MSAL apps use v2.0 format:
  https://login.microsoftonline.com/{tenant-id}/v2.0

DAB's JWT validation was configured for v2.0, causing every token to fail
with IDX10205 (Issuer validation failed). Fix: change DAB config to accept
the v1.0 issuer format matching Azure CLI.

Lesson: Always verify the token issuer format matches the API's validation
config. Mismatch = 401 on every request.

### 2. Client Application Authorization (AADSTS65001)

Azure CLI is a public client with its own client ID
(04b07795-8ddb-461a-bbee-02f9e1bf7b46). To request tokens for a custom API,
the API must pre-authorize the CLI as an allowed client application.

Fix: In the API's Expose an API → Authorized client applications, add the
Azure CLI client ID with the access_as_user scope.

Lesson: Public clients must be pre-authorized by the API to acquire tokens.

### 3. Auto-Pause Affects DAB Startup

Azure SQL auto-pause makes the first connection take 30+ seconds.
DAB's default connection timeout (30s) can fail during a cold start.

Workaround: Wake the DB with any SSMS query before starting DAB.
Production fix: Increase `Connect Timeout` in the connection string.

### 4. DAB Returns 403, Not 401, for Anonymous Access

When no Authorization header is present and only the authenticated role
is allowed, DAB returns 403 AuthorizationCheckFailed. This is because
DAB treats the request as anonymous — the role check fails, not the
authentication check.

Lesson: 401 = no credentials provided to a scheme expecting them.
403 = credentials provided (or anonymous) but access denied.

---

## Interview Talking Points

- "DAB supports Entra ID JWT validation. Config specifies issuer + audience;
  roles map to Entra app roles or the built-in authenticated role."
- "I hit a v1.0 vs v2.0 issuer mismatch — Azure CLI uses sts.windows.net,
  modern MSAL uses login.microsoftonline.com. Fixed by aligning DAB config
  with the client's token format."
- "Public clients like Azure CLI must be pre-authorized by the API to
  acquire tokens for custom scopes (AADSTS65001)."