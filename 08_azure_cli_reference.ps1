# ============================================================
# AZURE SQL + FAILOVER GROUP - COMPLETE CLI REFERENCE
# Day 8 — Reproducible end-to-end setup
# Author: Shuaib Ahmed
# ============================================================
# This file documents EVERY Azure CLI command used across the sprint.
# Use it as a template to reproduce the entire environment from scratch.
# ============================================================


# ============================================================
# SECTION 1 — AUTHENTICATION
# ============================================================

# Login to Azure
az login

# Verify current subscription
az account show

# Set default subscription (if you have multiple)
az account set --subscription "b133e9bf-e9b1-489a-9d28-e43a2c88b990"


# ============================================================
# SECTION 2 — RESOURCE GROUP
# ============================================================

$RESOURCE_GROUP = "rg-sql-sprint-2026"
$LOCATION = "centralus"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Verify
az group show --name $RESOURCE_GROUP

# List all resource groups
az group list --output table

# Delete resource group (removes EVERYTHING inside it)
# az group delete --name $RESOURCE_GROUP --yes


# ============================================================
# SECTION 3 — PRIMARY SQL SERVER
# ============================================================

$PRIMARY_SERVER = "sql-sprint-shu-2026"
$ADMIN_USER = "sqladmin"
$ADMIN_PASSWORD = "Str0ngP@ss!2026"

# Create primary server
az sql server create `
    --name $PRIMARY_SERVER `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --admin-user $ADMIN_USER `
    --admin-password $ADMIN_PASSWORD

# Verify
az sql server show `
    --name $PRIMARY_SERVER `
    --resource-group $RESOURCE_GROUP

# List servers in resource group
az sql server list --resource-group $RESOURCE_GROUP --output table

# Firewall rule — allow current IP
$MY_IP = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
az sql server firewall-rule create `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --name "AllowMyIP" `
    --start-ip-address $MY_IP `
    --end-ip-address $MY_IP

# Firewall rule — allow all Azure services
az sql server firewall-rule create `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --name "AllowAllAzure" `
    --start-ip-address 0.0.0.0 `
    --end-ip-address 0.0.0.0

# List firewall rules
az sql server firewall-rule list `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --output table


# ============================================================
# SECTION 4 — DATABASE
# ============================================================

$DATABASE_NAME = "ProcurementDB"

# Create serverless database (free offer applied via portal)
az sql db create `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --name $DATABASE_NAME `
    --service-objective GP_S_Gen5_2 `
    --compute-model Serverless `
    --min-capacity 0.5 `
    --auto-pause-delay 60 `
    --max-size 32GB

# Verify
az sql db show `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --name $DATABASE_NAME

# List all databases on the server
az sql db list `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --output table

# Show compute + storage settings
az sql db show `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --name $DATABASE_NAME `
    --query "{name:name, tier:currentServiceObjectiveName, maxSize:maxSizeBytes, status:status}" `
    --output table

# Update auto-pause delay (if needed)
# az sql db update `
#     --resource-group $RESOURCE_GROUP `
#     --server $PRIMARY_SERVER `
#     --name $DATABASE_NAME `
#     --auto-pause-delay 60


# ============================================================
# SECTION 5 — SECONDARY SERVER (for Failover Group)
# ============================================================

$SECONDARY_SERVER = "sql-sprint-shu-2026-secondary"
$SECONDARY_LOCATION = "westus3"

# Create secondary server (different region for geo-DR)
az sql server create `
    --name $SECONDARY_SERVER `
    --resource-group $RESOURCE_GROUP `
    --location $SECONDARY_LOCATION `
    --admin-user $ADMIN_USER `
    --admin-password $ADMIN_PASSWORD

# Verify
az sql server show `
    --name $SECONDARY_SERVER `
    --resource-group $RESOURCE_GROUP

# Firewall rules for secondary
az sql server firewall-rule create `
    --resource-group $RESOURCE_GROUP `
    --server $SECONDARY_SERVER `
    --name "AllowAllAzure" `
    --start-ip-address 0.0.0.0 `
    --end-ip-address 0.0.0.0

az sql server firewall-rule create `
    --resource-group $RESOURCE_GROUP `
    --server $SECONDARY_SERVER `
    --name "AllowMyIP" `
    --start-ip-address $MY_IP `
    --end-ip-address $MY_IP


# ============================================================
# SECTION 6 — FAILOVER GROUP
# ============================================================

$FAILOVER_GROUP = "procurement-failover-group"

# PREREQUISITE: The database must NOT have the free offer enabled.
# If it does, disable it first:
# Portal → ProcurementDB → Compute + storage → 
#   "Continue using database for additional charges" → Apply

# Create failover group
az sql failover-group create `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --partner-server $SECONDARY_SERVER `
    --failover-policy Automatic `
    --grace-period 1 `
    --add-db $DATABASE_NAME

# Verify failover group
az sql failover-group show `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER

# Query just the replication state
az sql failover-group show `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --query "replicationState" `
    --output tsv

# List all failover groups
az sql failover-group list `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --output table


# ============================================================
# SECTION 7 — FAILOVER DRILL
# ============================================================

# Trigger failover — promote secondary to primary
az sql failover-group set-primary `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $SECONDARY_SERVER

# Verify new roles
az sql failover-group show `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $SECONDARY_SERVER

# Fail back — promote original primary
az sql failover-group set-primary `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER

# Verify restored topology
az sql failover-group show `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER


# ============================================================
# SECTION 8 — CLEANUP
# ============================================================

# Delete failover group FIRST (before deleting secondary server)
az sql failover-group delete `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER

# Verify deletion
az sql failover-group list `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER
# Expected: []

# Delete secondary server
az sql server delete `
    --name $SECONDARY_SERVER `
    --resource-group $RESOURCE_GROUP `
    --yes

# Verify only primary remains
az sql server list `
    --resource-group $RESOURCE_GROUP `
    --output table

# RE-ENABLE FREE OFFER
# Portal → ProcurementDB → Compute + storage → 
#   "Auto-pause the database until next month" → Apply
# ⚠️ NOTE: This setting CANNOT be restored once disabled.
#   You must delete + recreate the database if you need auto-pause back.

# Delete entire resource group (nuclear option — removes EVERYTHING)
# az group delete --name $RESOURCE_GROUP --yes --no-wait


# ============================================================
# SECTION 9 — COST MONITORING
# ============================================================

# Check current spend for the subscription
az consumption usage list `
    --start-date (Get-Date).AddDays(-7).ToString('yyyy-MM-dd') `
    --end-date (Get-Date).ToString('yyyy-MM-dd') `
    --output table

# List all resources in the resource group (to audit what's billing)
az resource list --resource-group $RESOURCE_GROUP --output table


# ============================================================
# SECTION 10 — TROUBLESHOOTING REFERENCE
# ============================================================

# Error: RegionDoesNotAllowProvisioning
# Cause: The chosen region isn't accepting new servers (common with free tier)
# Fix: Try a different region (westus3, southcentralus, northeurope, australiaeast)

# Error: InvalidResourceLocation — resource already exists
# Cause: A failed deployment reserved the name globally
# Fix: Delete the failed resource first, then retry

# Error: FailoverGroupUnableToPerformGroupOperationOnDatabases
# Cause: Database has free offer enabled
# Fix: Disable free offer temporarily (one-way — cannot re-enable)

# Error: Schema name "Security" does not exist
# Cause: You're connected to master, not ProcurementDB
# Fix: USE ProcurementDB; GO  — before running RLS scripts

# Error: Cannot ALTER function because it is referenced
# Cause: SCHEMABINDING + security policy dependency
# Fix: DROP SECURITY POLICY, ALTER FUNCTION, RECREATE POLICY