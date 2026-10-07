# Day 12 — Azure Function for Data Export

**Date:** 2026-10-07
**Function App:** func-export-2026
**Assessment Task 5:** Export data using an Azure function

## What Was Built

An HTTP-triggered Azure Function that reads from `dbo.vw_VendorRisk` and returns JSON with 10 vendors.

| Component | Value |
| :--- | :--- |
| Function App | func-export-2026 |
| Runtime | .NET 8 (LTS), isolated worker |
| Function name | GetVendorRisk |
| Trigger | HTTP GET, Anonymous |
| Auth to SQL | Active Directory Default |
| Managed Identity | System-assigned |
| DB user | func-export-2026 (EXTERNAL_USER) |
| Role granted | db_datareader |

## Test Result

- Local test (VS Code F5): **Succeeded** — returned 10 vendors as JSON
- URL: http://localhost:7284/api/GetVendorRisk

## Errors Solved Today

| Error | Cause | Fix |
| :--- | :--- | :--- |
| AzureWebJobsStorage missing | Function runtime needs storage | Set to real storage account connection string in local.settings.json |
| Authentication provider not found | SqlClient 6.0+ split Azure auth | Install `Microsoft.Data.SqlClient.Extensions.Azure` |
| ManagedIdentityCredential failed (169.254.169.254) | Managed Identity endpoint only exists in Azure | Use `Active Directory Default` (portable mode) |
| Connection timeout | Azure SQL auto-paused | Wake DB via SSMS + add `Connect Timeout=120;` |

## Files

- `function-export/GetVendorRisk.cs` — Function code
- `function-export/local.settings.json` — Config (gitignored, contains storage key)
- `function-export/function-export.csproj` — Project with SqlClient + Extensions.Azure packages

**Status:** Local test passed. Deployment to Azure pending.