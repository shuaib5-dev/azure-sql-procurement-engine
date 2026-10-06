# Day 11 — Native REST Ingestion via `sp_invoke_external_rest_endpoint`

**Date:** 2026-10-06
**Database:** ProcurementDB
**Assessment Focus:** Task 4 — Import data using an external REST endpoint

---

## 📖 PART 1 — What Is `sp_invoke_external_rest_endpoint`?

### Definition

`sp_invoke_external_rest_endpoint` is a **system stored procedure** built into Azure SQL Database that allows T-SQL to call **any HTTPS REST API directly from within the database engine**.

It is Microsoft's native answer to the question: *"How do I fetch data from an external API without writing C#, Python, or an Azure Function?"*

### The Problem It Solves

Traditionally, getting REST data into a database required:
- Writing custom .NET/Python code
- Deploying a middleware service
- Managing credentials in code
- Handling retries and timeouts manually

With `sp_invoke_external_rest_endpoint`, a **single T-SQL statement** does all of that.

### When to Use It

| Scenario | Best Tool |
| :--- | :--- |
| Fetch exchange rates daily from a public API | ✅ `sp_invoke_external_rest_endpoint` |
| Pull customer data from SaaS tools (Salesforce, HubSpot) | ✅ `sp_invoke_external_rest_endpoint` |
| Fire a webhook from a stored procedure | ✅ `sp_invoke_external_rest_endpoint` |
| Move millions of rows hourly between systems | ❌ Use ADF |
| Complex transformations after fetch | ❌ Use ADF or Azure Functions |

### Where It Works

| Environment | Supported? | Notes |
| :--- | :--- | :--- |
| **Azure SQL Database** | ✅ Yes | Enabled by default |
| **Azure SQL Managed Instance** | ✅ Yes | Requires SQL Server 2025 or Always-up-to-date policy |
| **SQL Server 2025 (17.x)** | ✅ Yes | **Disabled by default** — enable with `sp_configure 'external rest endpoint enabled', 1` |
| SQL Server 2022 | ✅ Yes | First version with this feature |
| SQL Server on Azure VM (2025) | ✅ Yes | Same as SQL Server 2025 |
| On-premises SQL Server (2019 or earlier) | ❌ No | Not available |
| SQL database in Microsoft Fabric | ✅ Yes | Per Microsoft documentation |

**Key point:** In SQL Server 2025, this procedure is **disabled by default** for security. On Azure SQL Database, it's already enabled.

**Enable on SQL Server 2025 (requires sysadmin):**

```sql
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
GO

EXEC sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE;
GO

---

## 🔒 PART 2 — The Allow-List (Critical Constraint)

**Azure SQL does NOT allow calls to arbitrary URLs.** Only domains on Microsoft's official allow-list are reachable.

### The Allowed Domains

| Service | Allowed Domain Pattern |
| :--- | :--- |
| Azure Functions | `*.azurewebsites.net` |
| Azure App Service | `*.azurewebsites.net` |
| Azure Static Web Apps | `*.azurestaticapps.net` |
| Azure Logic Apps | `*.logic.azure.com` |
| Microsoft Graph | `graph.microsoft.com` |
| Power BI | `api.powerbi.com` |
| Azure Key Vault | `*.vault.azure.net` |
| Azure Blob Storage | `*.blob.core.windows.net` |
| Azure API Management | `*.azure-api.net` |
| Azure Monitor | `*.monitoring.azure.com` |

### Why This Exists

Without an allow-list, an attacker who finds SQL injection could do:

```sql
EXEC sp_invoke_external_rest_endpoint
    @url = 'http://internal-payment-service.company.local/steal-data';
```

This is called **SSRF (Server-Side Request Forgery)** — the database server becomes a proxy to attack internal systems.

### What Happens When You Call a Non-Allowed Domain

```
Msg 31612, Level 16, State 1
Connections to the domain <domain.com> are not allowed.
```

**This is a security feature, not a bug.**

### Production Workaround

For real production calls to non-allowed APIs:

1. **Azure Functions proxy** — your Function (on `*.azurewebsites.net`) fetches the external API and returns the data. Azure SQL calls your Function.
2. **Azure API Management** — expose the external API through APIM (`*.azure-api.net`), then call APIM from Azure SQL.
3. **Managed Identity** — use Azure SQL's managed identity to call Azure services (Key Vault, Blob Storage) directly.

---

## 🔧 PART 3 — The Syntax (Memorize This)

```sql
DECLARE @ret INT, @response NVARCHAR(MAX);

EXEC @ret = sp_invoke_external_rest_endpoint
    @url         = 'https://endpoint.example.com/api/data',
    @method      = 'GET',
    @headers     = '{"Content-Type":"application/json"}',
    @payload     = '{"key":"value"}',
    @credential  = 'https://endpoint.example.com',
    @timeout     = 30,
    @response    = @response OUTPUT;
```

### The 7 Parameters

| Parameter | Required? | Purpose | Notes |
| :--- | :--- | :--- | :--- |
| `@url` | ✅ Yes | Full HTTPS endpoint | Must be on allow-list |
| `@method` | ✅ Yes | HTTP verb | GET, POST, PUT, PATCH, DELETE |
| `@headers` | Optional | Custom HTTP headers | JSON string |
| `@payload` | Optional | Request body | For POST/PUT/PATCH, max 100 KB |
| `@credential` | Optional | Auth credential name | Scheme + host only |
| `@timeout` | Optional | Timeout in seconds | Default 30, max ~230 |
| `@response` | ✅ Yes (OUTPUT) | Response envelope | JSON-wrapped response |

### Return Code (`@ret`)

**The `EXEC @ret = ...` captures the return code — NOT the HTTP status code.**

| `@ret` Value | Meaning |
| :--- | :--- |
| **0** | Success (HTTP 2xx) |
| **1** | HTTP error returned (4xx, 5xx) |
| **2** | Could not connect (DNS, network, timeout) |
| Other | Specific system errors (see error 31612, 10928, 10936) |

### Size and Timeout Limits

| Limit | Value |
| :--- | :--- |
| `@payload` size | Max **100 KB** |
| Response returned to client | Max **2 MB** |
| Timeout | Max **~230 seconds** |
| Protocol | HTTPS only, port 443, no redirects |

---

## 📦 PART 4 — The Response Envelope

Every response is wrapped in a **JSON envelope**. This is the #1 source of confusion.

### The Structure

```json
{
  "response": {
    "status": {
      "http": {
        "code": 200,
        "description": "OK"
      }
    },
    "headers": {
      "content-type": "application/json",
      "date": "Mon, 06 Oct 2026 12:00:00 GMT"
    },
    "body": {
      // ← The actual API payload lives HERE
    }
  }
}
```

### The Three Key Paths

| Path | What It Contains |
| :--- | :--- |
| `$.response.status.http.code` | The **real HTTP status code** (200, 404, 500...) |
| `$.response.headers` | Response headers as key-value pairs |
| `$.response.body` | **The actual data payload from the API** |

### ⚠️ Common Mistake

Candidates often write `OPENJSON(@response)` — **this fails** because the payload isn't at the top level.

**Correct:** `OPENJSON(@response, '$.response.body')`

---

## 🔐 PART 5 — Authentication

### Option 1 — No Auth (Public APIs)

```sql
EXEC @ret = sp_invoke_external_rest_endpoint
    @url      = 'https://endpoint.example.com/api/public',
    @method   = 'GET',
    @timeout  = 30,
    @response = @response OUTPUT;
```

### Option 2 — Bearer Token / API Key

**Step 1 — Create a Database Scoped Credential:**

```sql
CREATE DATABASE SCOPED CREDENTIAL [https://endpoint.example.com]
WITH IDENTITY = 'HTTPEndpointHeaders',
     SECRET = '{"Authorization":"Bearer YOUR_TOKEN_HERE"}';
GO
```

**Step 2 — Call with credential:**

```sql
EXEC @ret = sp_invoke_external_rest_endpoint
    @url        = 'https://endpoint.example.com/api/data',
    @method     = 'GET',
    @credential = 'https://endpoint.example.com',
    @response   = @response OUTPUT;
```

### Option 3 — Managed Identity (Azure Services)

For calling Azure Key Vault, Blob Storage, etc.:

```sql
CREATE DATABASE SCOPED CREDENTIAL [https://yourvault.vault.azure.net]
WITH IDENTITY = 'Managed Identity';
GO

EXEC @ret = sp_invoke_external_rest_endpoint
    @url        = 'https://yourvault.vault.azure.net/secrets/mysecret',
    @method     = 'GET',
    @credential = 'https://yourvault.vault.azure.net',
    @response   = @response OUTPUT;
```

### The Credential Name Rule (Interview Favorite)

**The credential NAME must match the URL's scheme + host only.**

| URL | Correct Credential Name |
| :--- | :--- |
| `https://api.example.com/v1/data` | `https://api.example.com` ✅ |
| `https://api.example.com:443/data` | `https://api.example.com` ✅ |
| `https://api.example.com/v1/data` | `https://api.example.com/v1/data` ❌ too specific |
| `https://api.example.com/v1` | `https://api.example.com/v1` ❌ too specific |

**Rules:**
- ✅ Scheme + host only
- ✅ Case-sensitive path
- ❌ No query strings
- ❌ No deeper paths

### IDENTITY Types

| IDENTITY Value | Purpose |
| :--- | :--- |
| `HTTPEndpointHeaders` | Send custom headers (Bearer, API key) |
| `HTTPEndpointQueryString` | Send auth via query string |
| `Managed Identity` | Use Azure SQL's managed identity |
| `Shared Access Signature` | Use a SAS token |

---

## 🎯 PART 6 — The Assessment Pattern

The Microsoft Applied Skills lab (Task 4) tests **this exact pattern**:

### The 5 Steps the Lab Evaluates

1. **Create a database object** that calls the external REST endpoint
2. **Convert the JSON response** to tabular form
3. **Insert the results** into a target table
4. **Handle the response** using the envelope structure
5. **Handle errors** using `@ret`

### The Assessment-Ready Pattern

```sql
-- ============================================================
-- STEP 1: Create target table
-- ============================================================
CREATE TABLE dbo.StagingData (
    ItemId      INT PRIMARY KEY,
    ItemName    NVARCHAR(200),
    Value       DECIMAL(18,2),
    LoadedAt    DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO

-- ============================================================
-- STEP 2: Call the API and capture the response
-- ============================================================
DECLARE @ret INT, @response NVARCHAR(MAX);

EXEC @ret = sp_invoke_external_rest_endpoint
    @url         = 'https://your-allowed-endpoint.example.com/api/items',
    @method      = 'GET',
    @timeout     = 30,
    @credential  = 'https://your-allowed-endpoint.example.com',
    @response    = @response OUTPUT;

-- ============================================================
-- STEP 3: Check for success
-- ============================================================
IF @ret <> 0
BEGIN
    DECLARE @httpCode INT = JSON_VALUE(@response, '$.response.status.http.code');
    DECLARE @errMsg   NVARCHAR(500) = CONCAT('REST call failed. @ret=', @ret, ', HTTP=', @httpCode);
    THROW 50000, @errMsg, 1;
END

-- ============================================================
-- STEP 4: Parse the response and insert into table
-- ============================================================
INSERT INTO dbo.StagingData (ItemId, ItemName, Value)
SELECT 
    JSON_VALUE(item.value, '$.id'),
    JSON_VALUE(item.value, '$.name'),
    JSON_VALUE(item.value, '$.value')
FROM OPENJSON(@response, '$.response.body') AS item;

-- ============================================================
-- STEP 5: Verify
-- ============================================================
SELECT COUNT(*) AS RowsLoaded FROM dbo.StagingData;
```

### Line-by-Line Explanation

| Line | What It Does |
| :--- | :--- |
| `DECLARE @ret INT, @response NVARCHAR(MAX);` | `@ret` captures return code, `@response` captures envelope |
| `EXEC @ret = sp_invoke_external_rest_endpoint ...` | Calls the API, captures both outputs |
| `@response = @response OUTPUT` | The `OUTPUT` keyword is **required** |
| `IF @ret <> 0` | Early failure — don't attempt parse on failure |
| `JSON_VALUE(@response, '$.response.status.http.code')` | Extracts real HTTP code from envelope |
| `FROM OPENJSON(@response, '$.response.body')` | Parses the array inside the envelope |
| `JSON_VALUE(item.value, '$.id')` | Extracts individual fields from each row |

### What Could Go Wrong in the Lab

| Error | Cause | Fix |
| :--- | :--- | :--- |
| `@ret = 1` | HTTP error (4xx/5xx) | Check URL, headers, payload |
| `@ret = 2` | Connection failed | Check allow-list, timeout |
| `OPENJSON` returns 0 rows | Wrong path | Try `$.response.body.data` or `$.response.body.items` |
| `JSON_VALUE` returns NULL | Wrong field name | Case-sensitive. Inspect `@response` first |
| Credential not found | Wrong name | Name = scheme + host only |

---

## 🌍 PART 7 — Real-World Use Cases

### Use Case 1 — Daily Currency Rates

A finance team needs daily USD-INR exchange rates. Instead of a nightly cron job:

```sql
CREATE PROCEDURE dbo.usp_FetchDailyRates
AS
BEGIN
    DECLARE @ret INT, @response NVARCHAR(MAX);
    
    EXEC @ret = sp_invoke_external_rest_endpoint
        @url        = 'https://api.exchangerate.host/latest?base=USD',
        @method     = 'GET',
        @credential = 'https://api.exchangerate.host',
        @response   = @response OUTPUT;
    
    IF @ret = 0
    BEGIN
        INSERT INTO dbo.ExchangeRates (Currency, Rate, FetchedAt)
        SELECT 
            [key],
            CAST([value] AS DECIMAL(18,6)),
            SYSUTCDATETIME()
        FROM OPENJSON(@response, '$.response.body.rates')
        WHERE [key] IN ('INR', 'AED', 'EUR');
    END
END;
GO
```

### Use Case 2 — Webhook Trigger on Order Insert

Fire a Slack/Teams notification when a purchase order is approved:

```sql
CREATE PROCEDURE dbo.usp_NotifyOrderApproved
    @POID INT
AS
BEGIN
    DECLARE @ret INT, @response NVARCHAR(MAX);
    DECLARE @payload NVARCHAR(MAX) = 
        CONCAT('{"text":"PO ', @POID, ' has been approved."}');
    
    EXEC @ret = sp_invoke_external_rest_endpoint
        @url        = 'https://hooks.slack.com/services/XXX/YYY/ZZZ',
        @method     = 'POST',
        @headers    = '{"Content-Type":"application/json"}',
        @payload    = @payload,
        @credential = 'https://hooks.slack.com',
        @response   = @response OUTPUT;
END;
GO
```

### Use Case 3 — Sync from SaaS (via Azure Function Proxy)

Since the SaaS API isn't on the allow-list, proxy through a Function:

```
Azure SQL → Azure Function (allowed) → External SaaS API
```

SQL calls the Function, Function calls the SaaS, response flows back through the same envelope.

---

## 🎓 PART 8 — Interview Talking Points

### Opening Statement

> *"Azure SQL has a built-in stored procedure called `sp_invoke_external_rest_endpoint` that lets T-SQL call any allowed HTTPS REST API. I use it for moderate-volume REST integrations where I don't want to spin up external orchestration like ADF or a Function App."*

### Key Facts to Have Ready

1. **Syntax:** `EXEC @ret = sp_invoke_external_rest_endpoint @url=..., @method=..., @response=@response OUTPUT;`
2. **Return codes:** 0 = success, 1 = HTTP error, 2 = connect failure
3. **Envelope:** The payload lives at `$.response.body`, not the top level
4. **Parsing:** `OPENJSON(@response, '$.response.body')` for arrays
5. **Extraction:** `JSON_VALUE(item.value, '$.field')` for individual fields
6. **Credential name rule:** scheme + host only, no path
7. **Allow-list:** Only `*.azurewebsites.net`, `*.vault.azure.net`, `graph.microsoft.com`, etc.
8. **Size limits:** Payload 100 KB, response 2 MB, timeout ~230 sec

### Handling Follow-Up Questions

**"What if the API isn't on the allow-list?"**
> *"I proxy through an Azure Function (on `*.azurewebsites.net`) or Azure API Management (`*.azure-api.net`). Both are on the allow-list. This is the standard production pattern."*

**"How do you handle auth?"**
> *"I create a Database Scoped Credential with IDENTITY = 'HTTPEndpointHeaders' and the Authorization header in the SECRET. The credential name matches the URL's scheme + host."*

**"What about large responses?"**
> *"The response returned to the client is capped at 2 MB. For larger payloads I use ADF or fetch in batches with pagination."*

**"Is this safe?"**
> *"Yes. The allow-list prevents SSRF attacks. Credentials are stored as database objects and never exposed in code. I can also use Managed Identity for Azure-to-Azure calls — no passwords at all."*

---

## 📋 PART 9 — Assessment-Ready Checklist

Before taking the Applied Skills lab, you should answer these cold:

- [ ] What are the 7 parameters of `sp_invoke_external_rest_endpoint`?
- [ ] What does `@ret` return? (0, 1, 2 or other)
- [ ] Where does the payload live in the envelope? (`$.response.body`)
- [ ] How do you parse an array response? (`OPENJSON(@response, '$.response.body')`)
- [ ] How do you extract a single field? (`JSON_VALUE(item.value, '$.field')`)
- [ ] How do you authenticate? (Database Scoped Credential + `@credential` parameter)
- [ ] What's the credential naming rule? (scheme + host only)
- [ ] What are the allowed domain patterns? (*.azurewebsites.net, *.vault.azure.net, etc.)
- [ ] What are the size limits? (payload 100 KB, response 2 MB, timeout ~230 sec)
- [ ] What are the error codes? (31612 = domain not allowed, 10928 = outbound connection limit)

---

## 💰 PART 10 — Cost Impact

| Aspect | Cost |
| :--- | :--- |
| The stored procedure itself | Free |
| Each call | Free (Azure SQL doesn't charge per invocation) |
| Outbound bandwidth | ~₹0 for portfolio-scale usage |
| Credential storage | Free |

**Total: ₹0** for this feature.

---

## 🐛 PART 11 — Common Errors and Fixes

| Error | Cause | Fix |
| :--- | :--- | :--- |
| `31612 - Connections to the domain X are not allowed` | Domain not on allow-list | Use a proxy (Function, APIM) or an allowed domain |
| `@ret = 1` with HTTP code 401 | Auth failed | Check credential name and SECRET |
| `@ret = 1` with HTTP code 404 | Wrong URL path | Verify endpoint spelling |
| `@ret = 2` | DNS failure or timeout | Verify domain, increase `@timeout` |
| `10928 - Outbound connection limit reached` | Too many concurrent calls | Batch requests, reduce parallelism |
| `OPENJSON` returns 0 rows | Wrong JSON path | `SELECT @response` and inspect structure |
| `Cannot find the credential` | Wrong credential name | Name = scheme + host only |

---

## 🔗 PART 12 — Related Resources

| Topic | Link |
| :--- | :--- |
| Official documentation | [sp_invoke_external_rest_endpoint](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-invoke-external-rest-endpoint-transact-sql) |
| Allow-list reference | See "Allowed domains" section in official docs |
| Database Scoped Credentials | [CREATE DATABASE SCOPED CREDENTIAL](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-scoped-credential-transact-sql) |
| OPENJSON | [OPENJSON documentation](https://learn.microsoft.com/en-us/sql/t-sql/functions/openjson-transact-sql) |
| JSON_VALUE | [JSON_VALUE documentation](https://learn.microsoft.com/en-us/sql/t-sql/functions/json-value-transact-sql) |


**Status:** Complete — 2026-10-06
**Assessment Task 4:** Ready ✅