# Day 8 — Auto-Failover Group Drill

**Date:** 2026-09-27
**Database:** ProcurementDB
**Objective:** Configure geo-disaster recovery and validate failover.

---

## What Was Built

| Component | Value |
| :--- | :--- |
| Primary server | sql-sprint-shu-2026 (Central US) |
| Secondary server | sql-sprint-shu-2026-secondary (West US 3) |
| Failover group | procurement-failover-group |
| Database in group | ProcurementDB |
| Failover policy | Automatic |
| Grace period | 60 minutes |
| Replication state (initial) | CATCH_UP |

### Listener Endpoints

- Read-write: procurement-failover-group.database.windows.net
- Read-only: procurement-failover-group-secondary.database.windows.net

---

## What Is an Auto-Failover Group?

A failover group is Azure SQL's geo-disaster recovery mechanism. It:

1. Links two servers in different regions
2. Continuously replicates databases from primary to secondary
3. Exposes a stable listener endpoint that automatically redirects during failover
4. Can fail over automatically (after grace period) or manually

### Target SLAs

- RTO (Recovery Time Objective): less than 1 hour
- RPO (Recovery Point Objective): approximately 5 seconds

---

## Drill Performed

### Step 1 — Verify Initial State

Command:

    az sql failover-group show --name procurement-failover-group --resource-group rg-sql-sprint-2026 --server sql-sprint-shu-2026

Result: Primary = Central US, Secondary = West US 3, State = CATCH_UP

### Step 2 — Trigger Failover

Command:

    az sql failover-group set-primary --name procurement-failover-group --resource-group rg-sql-sprint-2026 --server sql-sprint-shu-2026-secondary

Result: Roles swapped. New primary = West US 3. Old primary became secondary.

### Step 3 — Test Listener from SSMS

Connected to procurement-failover-group.database.windows.net and ran:

    SELECT @@SERVERNAME;

Result: Returned sql-sprint-shu-2026 — the ORIGINAL primary, even after the swap.

This was the most important learning: The control plane updates immediately, but DNS propagation takes 5–15 minutes. Existing client connections may still route to the old primary during the transition.

### Step 4 — Fail Back

Command:

    az sql failover-group set-primary --name procurement-failover-group --resource-group rg-sql-sprint-2026 --server sql-sprint-shu-2026

Result: Original topology restored. Primary = Central US, Secondary = West US 3.

---

## Key Learnings

### 1. Free Offer Is Incompatible With Failover Groups

Databases with the free offer enabled cannot be added to failover groups. The error was:

    Parameter "Source database can't have free limit enabled." is invalid.

The trap: Disabling the free offer is a one-way change. Once you select "Continue using database for additional charges", you cannot restore auto-pause on that database. The database must be deleted and recreated.

Lesson: Always plan the failover group drill BEFORE your database contains critical data, OR be prepared to recreate the database afterward.

### 2. DNS Propagation Delay Is Real

Failover groups are DNS-based. Azure updates the control plane instantly, but clients see the new primary only after their local DNS cache refreshes (5–15 min).

Production implication: Applications need retry logic with exponential backoff. Without it, users see connection errors during the failover window even though the database is technically available.

### 3. The Listener Endpoint Is the Whole Point

Applications connect to procurement-failover-group.database.windows.net — never to the physical server name. During a failover, no connection string change is needed.

Without a failover group: Your app connects to sql-sprint-shu-2026.database.windows.net. On failover, you would have to update the connection string in every app, restart all services, and risk human error.

With a failover group: The endpoint stays the same. DNS routes to whichever server is currently primary.

### 4. Replication States

| State | Meaning |
| :--- | :--- |
| SEEDING | Initial copy in progress (can take minutes to hours) |
| CATCH_UP | Secondary is close behind primary — ready for failover |
| SYNCHRONIZED | Fully in sync — no lag |
| SUSPENDED | Replication stopped — investigate immediately |

### 5. Cost Awareness

The secondary replica is billed for compute and storage. For a small dev DB, that is still several hundred rupees per month if left running.

The drill: Created the group, ran the failover test, deleted everything. Total cost approximately 10–50 INR for a 45-minute exercise.

Production scenario: You keep the secondary running for real DR. Cost is a business decision, not a technical one.

---

## Cleanup Performed

1. Failover group deleted
2. Secondary server deleted
3. Resource group contains only the primary server and database
4. Database deleted and recreated to restore free offer and auto-pause
5. All scripts re-run to restore schema, data, security

Cost impact: Small, one-time charge for the drill window. Zero ongoing cost.

---

## Interview Answer — "Have You Set Up Geo-DR?"

Yes — I configured an auto-failover group for an Azure SQL database with primary in Central US and secondary in West US 3. I set Automatic failover policy with a 1-hour grace period, verified replication state reached CATCH_UP, and performed a live failover drill — promoting the secondary to primary. I learned two things in production: first, the control plane updates instantly but DNS takes 5–15 minutes to propagate, so apps need retry logic; second, the Azure free offer cannot coexist with failover groups, so I had to recreate the database afterward.

This is a real story with real lessons. Interviewers will remember it.

---

## Files Referenced

- 08_azure_cli_reference.ps1 — full CLI command reference
- day08_failover_swapped_cli.png — CLI output after failover
- day08_failover_failedback.png — CLI output after failback
- day08_failover_group_portal.png — Azure Portal screenshot