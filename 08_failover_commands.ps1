# ============================================
# DAY 8: Auto-Failover Group - Reproducible Setup
# ============================================

$RESOURCE_GROUP = "rg-sql-sprint-2026"
$PRIMARY_SERVER = "sql-sprint-shu-2026"
$SECONDARY_SERVER = "sql-sprint-shu-2026-secondary"
$SECONDARY_LOCATION = "eastus2"
$FAILOVER_GROUP = "procurement-failover-group"
$ADMIN_PASSWORD = "Str0ngP@ss!2026"

# ---------- Verify login ----------
az account show

# ---------- Create secondary server ----------
az sql server create `
    --name $SECONDARY_SERVER `
    --resource-group $RESOURCE_GROUP `
    --location $SECONDARY_LOCATION `
    --admin-user "sqladmin" `
    --admin-password $ADMIN_PASSWORD

# ---------- Firewall ----------
az sql server firewall-rule create `
    --resource-group $RESOURCE_GROUP `
    --server $SECONDARY_SERVER `
    --name "AllowAllAzure" `
    --start-ip-address 0.0.0.0 `
    --end-ip-address 0.0.0.0

# ---------- Create failover group ----------
az sql failover-group create `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER `
    --partner-server $SECONDARY_SERVER `
    --failover-policy Automatic `
    --grace-period 1 `
    --add-db ProcurementDB

# ---------- Verify replication ----------
az sql failover-group show `
    --name $FAILOVER_GROUP `
    --resource-group $RESOURCE_GROUP `
    --server $PRIMARY_SERVER