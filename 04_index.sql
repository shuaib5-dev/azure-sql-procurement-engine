-- ============================================
-- DAY 4: INDEXING & EXECUTION PLANS
-- ============================================

-- ---------- BULK INSERT 5000 ROWS ----------
DECLARE @i INT = 1;
WHILE @i <= 5000
BEGIN
    INSERT INTO dbo.PurchaseOrders (VendorID, OrderAmount, Status, Region)
    VALUES (
        ((@i - 1) % 10) + 1,
        CAST(500 + (RAND() * 99500) AS DECIMAL(18,2)),
        CASE (@i % 5)
            WHEN 0 THEN 'Pending'
            WHEN 1 THEN 'Approved'
            WHEN 2 THEN 'Rejected'
            WHEN 3 THEN 'Completed'
            ELSE 'Cancelled'
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

-- Verify
SELECT COUNT(*) AS TotalPOs FROM dbo.PurchaseOrders;


-- ---------- BASELINE (no index) ----------
SET STATISTICS IO ON;
SELECT POID, VendorID, OrderAmount, OrderDate, Status
FROM dbo.PurchaseOrders
WHERE Status = 'Cancelled';

-- Baseline: Clustered Index Scan | Logical Reads: 53 | Cost: 0.045929

-- ---------- FIRST INDEX (ignored by optimizer) ----------
CREATE NONCLUSTERED INDEX IX_PurchaseOrders_Status
ON dbo.PurchaseOrders (Status);

-- Lesson: Optimizer ignored this due to tipping point (~20% selectivity + key lookups)

-- ---------- COVERING INDEX ----------
DROP INDEX IX_PurchaseOrders_Status ON dbo.PurchaseOrders;

CREATE NONCLUSTERED INDEX IX_PurchaseOrders_Status_Covering
ON dbo.PurchaseOrders (Status)
INCLUDE (POID, VendorID, OrderAmount, OrderDate);

-- ---------- FINAL QUERY ----------
SELECT POID, VendorID, OrderAmount, OrderDate, Status
FROM dbo.PurchaseOrders
WHERE Status = 'Cancelled'
OPTION (RECOMPILE);

-- After covering index: Index Seek | Logical Reads: 10 | Cost: 0.0084343
-- Improvement: 81% fewer reads, 82% lower cost

SET STATISTICS IO OFF;
