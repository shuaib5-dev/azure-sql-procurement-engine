-- ============================================
-- SEED DATA — Vendors (10 rows)
-- ============================================
INSERT INTO dbo.Vendors (VendorName, VendorEmail, BankAccount, TaxID, Region) VALUES
('Acme Supplies',     'contact@acme.com',        'IN1234567890123456', 'TAX1001', 'North'),
('Global Traders',    'sales@globaltraders.com', 'IN2345678901234567', 'TAX1002', 'South'),
('Prime Materials',   'info@primematerials.com', 'IN3456789012345678', 'TAX1003', 'East'),
('Quality Parts Co',  'orders@qualityparts.com', 'IN4567890123456789', 'TAX1004', 'West'),
('TechSource Ltd',    'hello@techsource.com',    'IN5678901234567890', 'TAX1005', 'North'),
('Industrial Hub',    'purchase@indhub.com',     'IN6789012345678901', 'TAX1006', 'South'),
('Metro Vendors',     'contact@metrov.com',      'IN7890123456789012', 'TAX1007', 'East'),
('Elite Suppliers',   'sales@elitesup.com',      'IN8901234567890123', 'TAX1008', 'West'),
('Rapid Logistics',   'info@rapidlog.com',       'IN9012345678901234', 'TAX1009', 'North'),
('Brightway Trading', 'orders@brightway.com',    'IN0123456789012345', 'TAX1010', 'South');

SELECT COUNT(*) ct FROM dbo.Vendors;
-- Expected: 10

-- ============================================
-- SEED DATA — PurchaseOrders (100 rows)
-- ============================================
DECLARE @i INT = 1;
WHILE @i <= 100
BEGIN
    INSERT INTO dbo.PurchaseOrders (VendorID, OrderAmount, Status, Region)
    VALUES (
        ((@i - 1) % 10) + 1,
        CAST(1000 + (RAND() * 49000) AS DECIMAL(18,2)),
        CASE (@i % 4)
            WHEN 0 THEN 'Pending'
            WHEN 1 THEN 'Approved'
            WHEN 2 THEN 'Rejected'
            ELSE 'Completed'
        END,
        CASE (@i % 4)
            WHEN 0 THEN 'North'
            WHEN 1 THEN 'South'
            WHEN 2 THEN 'East'
            ELSE 'West'
        END
    );
    SET @i = @i + 1;
END;

SELECT COUNT(*) ct FROM dbo.PurchaseOrders;
-- Expected: 100

-- ============================================
-- SEED DATA — LineItems (300 rows)
-- ============================================
DECLARE @i INT = 1;
WHILE @i <= 300
BEGIN
    INSERT INTO dbo.LineItems (POID, ItemName, Quantity, UnitCost)
    VALUES (
        999 + ((@i - 1) % 100) + 1,
        'Item-' + CAST(((@i - 1) % 20) + 1 AS NVARCHAR(10)),
        ((@i - 1) % 50) + 1,
        CAST(50 + (RAND() * 950) AS DECIMAL(18,2))
    );
    SET @i = @i + 1;
END;

SELECT COUNT(*) ct FROM dbo.LineItems;
-- Expected: 300

-- ============================================
-- SEED DATA — ApprovalLogs (150 rows)
-- ============================================
DECLARE @i INT = 1;
WHILE @i <= 150
BEGIN
    INSERT INTO dbo.ApprovalLogs (POID, ApproverEmail, Action, Comments)
    VALUES (
        999 + ((@i - 1) % 100) + 1,
        'approver' + CAST(((@i - 1) % 5) + 1 AS NVARCHAR(2)) + '@company.com',
        CASE (@i % 3)
            WHEN 0 THEN 'Approved'
            WHEN 1 THEN 'Reviewed'
            ELSE 'Escalated'
        END,
        'Batch approval log entry #' + CAST(@i AS NVARCHAR(10))
    );
    SET @i = @i + 1;
END;

SELECT COUNT(*) FROM dbo.ApprovalLogs;
-- Expected: 150

SELECT MIN(POID) AS MinPOID, 
       MAX(POID) AS MaxPOID, 
       COUNT(*) AS Total 
FROM dbo.PurchaseOrders;

-- ============================================
-- FIX: Insert 3 missing LineItems for POID 1000
-- ============================================
INSERT INTO dbo.LineItems (POID, ItemName, Quantity, UnitCost) VALUES
(1001, 'Item-1', 10, 150.00),
(1001, 'Item-2', 25, 320.00),
(1001, 'Item-3', 5,  890.00);

-- ============================================
-- FIX: Insert 2 missing ApprovalLogs for POID 1000
-- ============================================
INSERT INTO dbo.ApprovalLogs (POID, ApproverEmail, Action, Comments) VALUES
(1001, 'approver1@company.com', 'Reviewed',  'Fixed POID reference'),
(1001, 'approver2@company.com', 'Approved',  'Fixed POID reference');

SELECT 'Vendors'       AS TableName, COUNT(*) AS RwCount FROM dbo.Vendors
UNION ALL
SELECT 'PurchaseOrders', COUNT(*) FROM dbo.PurchaseOrders
UNION ALL
SELECT 'LineItems',      COUNT(*) FROM dbo.LineItems
UNION ALL
SELECT 'ApprovalLogs',   COUNT(*) FROM dbo.ApprovalLogs
ORDER BY TableName;

SELECT TOP 10
    V.VendorName,
    V.Region,
    PO.POID,
    PO.OrderAmount,
    PO.Status
FROM dbo.Vendors V
INNER JOIN dbo.PurchaseOrders PO ON V.VendorID = PO.VendorID
ORDER BY PO.OrderAmount DESC;