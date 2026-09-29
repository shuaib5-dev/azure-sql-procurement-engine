# Day 10 — Azure Data Factory Copy Pipeline (Complete Walkthrough)

**Date:** 2026-09-29
**ADF Instance:** adf-procurement-2026
**Storage Account:** stprocurement2026
**Objective:** Build an ADF pipeline that copies data from Azure SQL (view) to Blob Storage (CSV) with full documentation of every step, choice, and error encountered.

---

## 📖 PART 1 — THEORY: What Azure Data Factory Is

### The Problem ADF Solves

Your ProcurementDB lives in Azure SQL. But data often needs to move:
- Daily backups of `PurchaseOrders` as CSV
- Denormalized data for Power BI / data lake
- Copying from external APIs into staging tables

**Without ADF:** Custom .NET/Python jobs + Windows Task Scheduler + manual error handling.

**With ADF:** Visual pipeline builder + 100+ built-in connectors + scheduling + monitoring + retry logic.

### What ADF Actually Is

ADF is a **cloud-based ETL/ELT orchestrator**. It moves and transforms data between systems.

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Azure SQL    │───▶│    ADF       │───▶│ Blob Storage │
│ (Source)     │    │  Pipeline    │    │ (Sink)       │
└──────────────┘    └──────────────┘    └──────────────┘
```

**ADF does not store data.** It's an orchestrator.

### Core Components (Memorize These)

| Component | What It Is | Analogy |
| :--- | :--- | :--- |
| **Pipeline** | A logical grouping of activities | A recipe |
| **Activity** | A single step in a pipeline | One step in the recipe |
| **Dataset** | A named reference to data | The ingredients |
| **Linked Service** | Connection info to a data store | The kitchen |
| **Integration Runtime** | The compute engine | The chef |
| **Trigger** | When the pipeline should run | The alarm clock |

### Hierarchy

```
Pipeline
  └── Activity (Copy, Data Flow, Stored Procedure)
        ├── Source Dataset → Linked Service → Azure SQL
        └── Sink Dataset   → Linked Service → Blob Storage
```

### Integration Runtime Types

| IR Type | Where It Runs | When to Use |
| :--- | :--- | :--- |
| **Azure IR** | Managed by Azure | Cloud-to-cloud (our case) |
| Self-Hosted IR | Your VM/on-prem | On-prem → cloud |
| Azure-SSIS IR | Managed by Azure | Lift-and-shift SSIS packages |

### Pricing (Critical for Free Sprint)

| Component | Cost | Free Allowance |
| :--- | :--- | :--- |
| Pipeline orchestration | $1 per 1,000 activity runs | **First 1,000 runs/month free** |
| Data movement (DIU-hours) | $0.25 per DIU-hour | No free tier |
| Data Flow execution | $0.268 per vCore-hour | No free tier |
| Azure IR | Included | — |

**Key point:** A Copy Activity = 1 activity run. 1,000 free runs/month. Data Flows use Spark clusters that bill even during warmup — **we skip Data Flows in this sprint.**

---

## 🛠️ PART 2 — STORAGE ACCOUNT PROVISIONING

### Why a Storage Account?

ADF needs a destination for copied data. Azure Blob Storage is the standard sink for file exports.

### Step-by-Step

**Step 1 — Navigate to Storage Accounts**

- Azure Portal → search **"Storage accounts"** → click **+ Create**

**Step 2 — Basics Tab**

| Field | Value Selected | Why This Choice |
| :--- | :--- | :--- |
| Subscription | Azure subscription 1 | Only subscription |
| Resource group | rg-sql-sprint-2026 | Same RG as all sprint resources |
| Storage account name | stprocurement2026 | Globally unique, meaningful |
| Region | **(US) Central US** | Same region as SQL server (low latency, no cross-region charges) |
| Primary service | **Azure Blob Storage or Azure Data Lake Storage** | We're storing files, not file shares |
| Performance | **Standard** | Cheap HDD — 10x cheaper than Premium SSD |
| Redundancy | **Locally-redundant storage (LRS)** | Cheapest option — 3 copies in 1 datacenter |

**Why LRS over GRS:** Portfolio data doesn't need geo-redundancy. If the datacenter fails, we regenerate from source SQL. LRS is ~50% cheaper than GRS.

**Step 3 — Advanced Tab**

| Field | Value | Purpose |
| :--- | :--- | :--- |
| Enable hierarchical namespace | Disabled | ADLS Gen2 feature — not needed for basic blobs |
| Enable SFTP | Disabled | File transfer protocol — not needed |
| Enable NFS v3 | Disabled | Network file system — not needed |
| Allow cross-tenant replication | Disabled | Security default |
| **Access tier** | **Hot** | Frequent access — optimal for our pattern |
| Require Encryption in Transit for SMB | Enabled | Default security |

**Why Hot tier:** We read the CSV immediately after pipeline runs. Cool/Cold tiers are cheaper per GB but have higher access costs.

**Step 4 — Remaining Tabs**

- Networking, Data protection, Encryption, Tags — **all left at defaults**

**Step 5 — Review + Create**

- Verified summary showed **LRS** in replication
- Clicked **Create**
- Deployment completed in ~1 minute

### Step 6 — Create Container

- Went to storage account → left menu → **Data storage → Containers** → **+ Container**
- Name: `procurement-data`
- Public access level: **Private (no anonymous access)** — security default
- Clicked **Create**

**Screenshot:** `day10_storage_container.png`

---

## 🛠️ PART 3 — ADF PROVISIONING

### Step-by-Step

**Step 1 — Navigate**

- Azure Portal → search **"Data factories"** → clicked **Data factories (V2)** — the FIRST option

**Why V2:** V1 is deprecated. All modern features (Azure IR, Data Flows, Git integration) are only in V2.

**Step 2 — Basics Tab**

| Field | Value | Purpose |
| :--- | :--- | :--- |
| Subscription | Azure subscription 1 | |
| Resource group | rg-sql-sprint-2026 | |
| Name | adf-procurement-2026 | Must be globally unique |
| Region | **Central US** | Same region as SQL + storage |
| Version | **V2** | Default in modern portal |

**Step 3 — Git Configuration Tab**

- Left as **"Configure Git later"**

**Why:** We don't need ADF's built-in Git integration for this sprint. Files go to our own repo.

**Step 4 — Networking**

- Left as **Public endpoint** (default)

**Step 5 — Review + Create**

- Clicked **Create** → deployment succeeded in ~1 min
- Clicked **Go to resource**

**Step 6 — Launch ADF Studio**

- Clicked **Launch Studio** → new browser tab opened at `adf.azure.com`

**Screenshot:** `day10_adf_resource_page.png` + `day10_adf_studio_home.png`

### ADF Studio Navigation

| Icon | Section | Purpose |
| :--- | :--- | :--- |
| 🏠 | Home | Overview, quick actions |
| ✏️ | Author | Build pipelines, datasets, linked services |
| 🗺️ | Monitor | View pipeline runs, trigger history |
| ⚙️ | Manage | Linked services, IR, triggers, integration |

---

## 🛠️ PART 4 — LINKED SERVICES

### What Is a Linked Service?

A Linked Service stores **connection information** to a data store. It's essentially a connection string stored securely in ADF, reusable across datasets.

### Linked Service 1 — Azure SQL Database

**Step 1 — Navigate**

- ADF Studio → **Manage** (⚙️) → **Linked services** → **+ New**

**Step 2 — Choose Connector**

- Searched **"Azure SQL Database"** → selected → **Continue**

**Step 3 — Fill Form**

| Field | Value |
| :--- | :--- |
| Name | `LS_AzureSQL_ProcurementDB` |
| Description | (left blank) |
| Connect via integration runtime | AutoResolveIntegrationRuntime |
| Version | 2.0 (Recommended) |
| Account selection method | From Azure subscription |
| Azure subscription | Azure subscription 1 |
| Server name | `sql-sprint-shu-2026` |
| Database name | `ProcurementDB` |

**Step 4 — Authentication Choice**

**Options available in dropdown:**
- SQL authentication
- **System-assigned managed identity** ✅ (chosen)
- Service principal
- User-assigned managed identity

**Why System-assigned managed identity:**

| Approach | Pros | Cons |
| :--- | :--- | :--- |
| SQL authentication | Simple | Password in config, must rotate, security risk |
| **Managed identity** | **No secrets, auto-rotated, Azure-native** | Requires one-time DB user setup |
| Service principal | Good for CI/CD | Requires secret management |

**There was no "Microsoft Entra ID" option** because ADF doesn't authenticate as a user — it authenticates as a **service identity**.

**Step 5 — Encryption Settings**

| Field | Value | Why |
| :--- | :--- | :--- |
| Always encrypted | Unchecked | Not needed for our data |
| **Encrypt** | **Mandatory** | Azure SQL requires encrypted connections |
| Trust server certificate | Unchecked | Azure SQL has a valid cert |
| Host name in certificate | (empty) | Auto-derived |

**Step 6 — Grant ADF Access to the Database**

**Error we would have hit:** Before running Test connection, the ADF managed identity has no database user. Must create it first.

**In SSMS:**

```sql
USE ProcurementDB;
GO

-- Create the ADF managed identity as a database user
CREATE USER [adf-procurement-2026] FROM EXTERNAL PROVIDER;
GO

-- Grant read access
ALTER ROLE db_datareader ADD MEMBER [adf-procurement-2026];
GO

-- Grant write access for future pipelines
ALTER ROLE db_datawriter ADD MEMBER [adf-procurement-2026];
GO
```

**What each statement does:**

| Statement | Purpose |
| :--- | :--- |
| `CREATE USER ... FROM EXTERNAL PROVIDER` | Creates a database user mapped to an Entra ID identity (the ADF managed identity) |
| `db_datareader` | Grants SELECT on all tables/views in the database |
| `db_datawriter` | Grants INSERT/UPDATE/DELETE (for future sink-to-SQL pipelines) |

**Step 7 — Test Connection**

- Clicked **Test connection** → returned **"Connection successful"**
- Clicked **Create**

**Screenshot:** `day10_linked_service_sql.png`

### Linked Service 2 — Azure Blob Storage

**Step 1 — Navigate**

- **+ New** → searched **"Azure Blob Storage"** → **Continue**

**Step 2 — Fill Form**

| Field | Value | Why |
| :--- | :--- | :--- |
| Name | `LS_BlobStorage_Procurement` | |
| Connect via integration runtime | AutoResolveIntegrationRuntime | Cloud-to-cloud |
| Authentication type | **Account key** | Simplest for sprint |
| Account selection method | From Azure subscription | Auto-discovers |
| Azure subscription | Azure subscription 1 | |
| Storage account name | `stprocurement2026` | |

**Alternative auth options (not chosen):**
- Managed identity — best practice, but requires granting ADF's identity Blob Data Contributor role
- Service principal — for CI/CD
- SAS token — time-limited access

**Step 3 — Test and Create**

- Clicked **Test connection** → **"Connection successful"**
- Clicked **Create**

**Screenshot:** `day10_linked_service_blob.png`

**Step 4 — Publish All Changes**

- Top toolbar → **Publish all** → confirmed

**Why publishing matters:** Until published, ADF items exist only as **drafts** in the studio session. Publishing persists them to the ADF resource.

---

## 🛠️ PART 5 — DATASETS

### What Is a Dataset?

A Dataset is a **named reference to specific data** within a linked service. It points to a table, view, or file path.

### Dataset 1 — Azure SQL Source

**Step 1 — Navigate**

- ADF Studio → **Author** (✏️) → **Datasets** → **+ → New dataset**

**Step 2 — Choose Connector**

- Searched **"Azure SQL Database"** → selected → **Continue**

**Step 3 — Fill Form**

| Field | Value |
| :--- | :--- |
| Name | `DS_AzureSQL_PurchaseOrderSummary` |
| Linked service | `LS_AzureSQL_ProcurementDB` |
| Table name | `dbo.vw_PurchaseOrderSummary` |
| Import schema | From connection/store |

**Step 4 — Preview Data (ERROR ENCOUNTERED)**

**Error:** Preview returned **0 rows** — schema loaded (VendorName, Region, TotalOrders, TotalSpend) but no data.

**Root Cause:** Row-Level Security from Day 6 filters rows based on `USER_NAME()`. The ADF managed identity (`adf-procurement-2026`) doesn't match the pattern `'buyer_' + LOWER(@Region)`, so the RLS predicate excludes all rows.

**The RLS predicate:**
```sql
WHERE 'buyer_' + LOWER(@Region) = USER_NAME()
   OR USER_NAME() = 'dbo'
   OR IS_ROLEMEMBER('db_owner') = 1
```

ADF's identity matched none of these → 0 rows.

**Fix — Grant db_owner to ADF identity:**

```sql
USE ProcurementDB;
GO
ALTER ROLE db_owner ADD MEMBER [adf-procurement-2026];
GO
```

**Why this works:** The `IS_ROLEMEMBER('db_owner') = 1` clause now evaluates to true for the ADF identity — bypassing the RLS filter.

**Retried preview** → all 10 vendors visible. **Success.**

**Screenshot:** `day10_dataset_preview_success.png`

**Production Best Practice (deferred to Day 16):** Create a dedicated `db_service_accounts` role, add service accounts to it, and modify the RLS predicate to include `OR IS_ROLEMEMBER('db_service_accounts') = 1`.

### Dataset 2 — Blob Storage Sink

**Step 1 — Navigate**

- **+ → New dataset** → searched **"Azure Blob Storage"** → **Continue**

**Step 2 — Fill Form**

| Field | Value |
| :--- | :--- |
| Name | `DS_Blob_PurchaseOrderSummary_CSV` |
| Linked service | `LS_BlobStorage_Procurement` |
| Container | `procurement-data` |
| Directory | `purchase-orders` |
| File name | `purchase-order-summary` |
| Format | **DelimitedText (CSV)** |
| First row as header | ✅ Checked |
| Import schema | **None** |

**Step 3 — ERROR ENCOUNTERED**

**Error:** With Import schema set to "From connection/store", ADF tried to read the schema from the CSV file — but the file doesn't exist yet. Error: `404 Not Found` for `purchase-order-summary.csv`.

**Root cause:** Sink dataset points to a file that hasn't been created. ADF's schema import tries to read the file at design time.

**Fix:** Changed **Import schema** to **None**.

**Why this works:** For sink datasets, the schema comes from the source dataset at runtime. Copy Activity Mapping handles column alignment.

**Screenshot:** `day10_dataset_blob.png`

**Step 4 — Publish All Changes**

- **Publish all** → confirmed

---

## 🛠️ PART 6 — COPY PIPELINE

### Step 1 — Create Pipeline

- ADF Studio → **Author** → **Pipelines** → **... → New pipeline**
- Renamed to: `PL_CopyPurchaseOrderSummary`

### Step 2 — Add Copy Activity

- Expanded **Move & transform** in the Activities panel
- Dragged **Copy data** onto the canvas
- Activity auto-named "Copy data1"

### Step 3 — Configure Source

| Field | Value |
| :--- | :--- |
| Source dataset | `DS_AzureSQL_PurchaseOrderSummary` |
| Use query | **Table** |

- Clicked **Preview data** → confirmed 10 rows appeared

**Why "Use query: Table":** Reads all rows from the view. Alternative options: Query (custom SQL), Stored procedure (for advanced scenarios).

### Step 4 — Configure Sink

| Field | Value |
| :--- | :--- |
| Sink dataset | `DS_Blob_PurchaseOrderSummary_CSV` |
| File name | `purchase-order-summary.csv` |

### Step 5 — Configure Mapping

**ERROR ENCOUNTERED:** Auto-mapping didn't check the columns — all 4 checkboxes appeared unchecked.

**Root cause:** The schema from source and sink needed manual confirmation. Auto-map can be strict about casing/spacing mismatches.

**Fix:** Manually checked each column pair:

| Source | Sink |
| :--- | :--- |
| VendorName | VendorName |
| Region | Region |
| TotalOrders | TotalOrders |
| TotalSpend | TotalSpend |

**Screenshot:** `day10_pipeline_mapping.png`

### Step 6 — Configure Settings

| Field | Value | Purpose |
| :--- | :--- | :--- |
| Fault tolerance | (empty) | Default — fails on any error |
| Enable logging | ✅ Checked | Records copy logs |
| Storage connection name | `LS_BlobStorage_Procurement` | Where logs are written |
| **Folder path** | `procurement-data/logs` | Log destination |
| Logging level | Warning | Only warnings/errors logged |
| Logging mode | Best effort | Doesn't fail pipeline on log failure |
| Enable staging | Unchecked | Saves cost — used for large copies |
| Maximum DIU | Auto | ADF decides |
| Degree of copy parallelism | Auto | ADF decides |
| Data consistency verification | Unchecked | Not needed for our data |

**Note on DIU warning:** The yellow banner "You will be charged..." is informational. For 4 DIUs × 30 seconds, the cost is ~$0.00008 — negligible.

### Step 7 — Validate and Debug

- Top toolbar → **Validate** → "No errors found"
- Top toolbar → **Debug** → pipeline ran

**Result:** Pipeline status: **Succeeded** in ~30 seconds.

**Screenshot:** `day10_adf_debug_success.png`

### Step 8 — Verify Output

- Azure Portal → storage account → Containers → `procurement-data` → `purchase-orders`
- Confirmed `purchase-order-summary.csv` exists
- Downloaded → opened in Notepad

**File contents (verified):**
```
VendorName,Region,TotalOrders,TotalSpend
"Metro Vendors","East",510,25407219.48
"Prime Materials","East",510,25306625.26
"Acme Supplies","North",511,26639724.61
"Rapid Logistics","North",510,25792599.01
"TechSource Ltd","North",510,26304531.72
"Brightway Trading","South",510,25704612.92
"Global Traders","South",511,25782297.39
"Industrial Hub","South",510,25960027.35
"Elite Suppliers","West",510,26103644.97
"Quality Parts Co","West",510,24850736.06
```

**Notice:** String values with spaces are auto-quoted — standard CSV convention.

**Screenshot:** `day10_blob_output_csv.png`

### Step 9 — Publish All Changes

- Top toolbar → **Publish all** → confirmed

All ADF items now persist.

---

## 🐛 ERRORS ENCOUNTERED & FIXES (Summary)

| # | Error | Cause | Fix |
| :--- | :--- | :--- | :--- |
| 1 | Preview returns 0 rows on SQL dataset | RLS blocks ADF service account | Granted `db_owner` to `adf-procurement-2026` |
| 2 | Sink dataset schema import fails with 404 | CSV file doesn't exist yet | Set Import schema to **None** |
| 3 | Mapping checkboxes unchecked | Auto-map strict on column matching | Manually checked all 4 column pairs |

---

## 📊 COST IMPACT

| Component | Charge |
| :--- | :--- |
| Storage account (LRS, Hot, ~500 bytes) | ₹0 |
| ADF activity run (1 run) | Free tier (1,000/month) |
| Data movement (4 DIU × 30 sec) | ~₹0.01 |
| Logging (~5 KB) | ₹0 |
| **Total Day 10** | **~₹1 or less** |

---

## 🎓 KEY LEARNINGS

1. **ADF is an orchestrator, not a data store.** Coordinates movement between systems.

2. **Linked Service = connection string.** Stored once, reused by datasets.

3. **Dataset = named reference.** Points to a table, view, or file.

4. **Azure IR handles cloud-to-cloud.** No setup, no cost.

5. **Managed identity is the modern auth pattern.** No passwords stored. Requires one-time `CREATE USER FROM EXTERNAL PROVIDER`.

6. **RLS blocks service accounts by default.** Grant a bypass role (`db_owner` or a custom role) so ADF can see data.

7. **Sink datasets use Import schema = None** when the target file doesn't exist yet.

8. **Auto-mapping isn't always reliable.** Verify column pairs in the Mapping tab.

9. **Free tier is generous.** 1,000 activity runs/month — enough for portfolio work.

10. **Data Flows are expensive.** Spark warmup is billed even for short jobs. Avoid in free tier.

---

## 🎯 INTERVIEW TALKING POINTS

- "I built an ADF Copy pipeline that exports Azure SQL view data to CSV in Blob Storage using a Copy Activity with Azure Integration Runtime."

- "ADF uses a managed identity for passwordless authentication. I created a database user via `CREATE USER ... FROM EXTERNAL PROVIDER` and granted it `db_datareader`."

- "When RLS is enabled, service accounts like ADF see zero rows by default — the predicate blocks them. I added the ADF identity to `db_owner` for the sprint. Production best practice is a dedicated `db_service_accounts` role referenced in the RLS predicate."

- "Sink datasets don't have schemas at design time — set Import schema to None and let the Copy Activity mapping handle column alignment at runtime."

- "ADF's free tier is 1,000 activity runs/month. Copy activities count as one run each. Data Flows are separate and much more expensive."

---

## 📁 FILES REFERENCED

- `day10_` 