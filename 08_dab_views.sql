USE ProcurementDB;
GO

-- Summary view: one row per vendor-region
CREATE OR ALTER VIEW dbo.vw_PurchaseOrderSummary AS
SELECT 
    V.VendorName,
    V.Region,
    COUNT(PO.POID)      AS TotalOrders,
    SUM(PO.OrderAmount) AS TotalSpend
FROM dbo.Vendors V
INNER JOIN dbo.PurchaseOrders PO ON V.VendorID = PO.VendorID
GROUP BY V.VendorName, V.Region;
GO

-- Risk view: one row per vendor
CREATE OR ALTER VIEW dbo.vw_VendorRisk AS
SELECT 
    V.VendorID,
    V.VendorName,
    ISNULL(SUM(PO.OrderAmount), 0) AS Exposure
FROM dbo.Vendors V
LEFT JOIN dbo.PurchaseOrders PO ON V.VendorID = PO.VendorID
GROUP BY V.VendorID, V.VendorName;
GO

-- Verify
SELECT TOP 5 * FROM dbo.vw_PurchaseOrderSummary;
SELECT TOP 5 * FROM dbo.vw_VendorRisk;