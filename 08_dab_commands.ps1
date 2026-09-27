# ============================================
# DAY 8: Data API Builder - Reproducible Setup
# ============================================
# Run from: D:\Shuaib\azure-sql-procurement-engine

# ---------- STEP 1: Set connection env var ----------
$env:SQL_CONN = "Server=sql-sprint-shu-2026.database.windows.net;Database=ProcurementDB;Authentication=Active Directory Default;Encrypt=True;"

# ---------- STEP 2: Initialize DAB ----------
dab init --database-type mssql --connection-string "@env('SQL_CONN')" --host-mode Development

# ---------- STEP 3: Add views as entities ----------
dab add PurchaseOrderSummary `
    --source dbo.vw_PurchaseOrderSummary `
    --source.type view `
    --source.key-fields "VendorName,Region" `
    --permissions "anonymous:*" `
    --rest "purchase-orders" `
    --graphql "purchaseOrders"

dab add VendorRisk `
    --source dbo.vw_VendorRisk `
    --source.type view `
    --source.key-fields "VendorID" `
    --permissions "anonymous:*" `
    --rest "vendor-risk" `
    --graphql "vendorRisk"

# ---------- STEP 4: Start DAB ----------
dab start
# Keep this terminal open. Open a NEW terminal for testing.

# ============================================
# IN A SEPARATE TERMINAL — TEST ENDPOINTS
# ============================================

# REST: Purchase orders
Invoke-RestMethod -Uri "http://localhost:5000/api/purchase-orders" | ConvertTo-Json -Depth 3

# REST: Vendor risk
Invoke-RestMethod -Uri "http://localhost:5000/api/vendor-risk" | ConvertTo-Json -Depth 3

# GraphQL: open browser
Start-Process "http://localhost:5000/graphql"