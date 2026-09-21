-- ============================================
-- DAY 3: ADVANCED T-SQL
-- Window functions, CTEs, error handling, SP, UDF, view
-- ============================================

-- ---------- BLOCK 1: WINDOW FUNCTIONS ----------

-- Rank Vendors by Total Spend
SELECT 
    V.VendorName,
    V.Region,
    SUM(PO.OrderAmount) AS TotalSpend,
    ROW_NUMBER() OVER (ORDER BY SUM(PO.OrderAmount) DESC) AS SpendRank,
    RANK()       OVER (ORDER BY SUM(PO.OrderAmount) DESC) AS SpendRankWithTies,
    DENSE_RANK() OVER (ORDER BY SUM(PO.OrderAmount) DESC) AS SpendDenseRank
FROM dbo.Vendors V
INNER JOIN dbo.PurchaseOrders PO ON V.VendorID = PO.VendorID
GROUP BY V.VendorName, V.Region
ORDER BY TotalSpend DESC;

-- Rank within Regions (Partition By)
SELECT 
    V.Region,
    V.VendorName,
    SUM(PO.OrderAmount) AS TotalSpend,
    RANK() OVER (PARTITION BY V.Region 
                 ORDER BY SUM(PO.OrderAmount) DESC) AS RegionRank
FROM dbo.Vendors V
INNER JOIN dbo.PurchaseOrders PO ON V.VendorID = PO.VendorID
GROUP BY V.Region, V.VendorName
ORDER BY V.Region, RegionRank;

-- Running Total + LEAD/LAG
SELECT 
    POID,
    OrderDate,
    OrderAmount,
    SUM(OrderAmount) OVER (ORDER BY OrderDate, POID 
                           ROWS UNBOUNDED PRECEDING) AS RunningTotal,
    LAG(OrderAmount, 1)  OVER (ORDER BY OrderDate, POID) AS PreviousOrder,
    LEAD(OrderAmount, 1) OVER (ORDER BY OrderDate, POID) AS NextOrder
FROM dbo.PurchaseOrders
ORDER BY OrderDate, POID;

-- ---------- BLOCK 2: CTEs ----------
-- vendors above average spend
WITH VendorSpend AS (
    SELECT VendorID, SUM(OrderAmount) AS TotalSpend
    FROM dbo.PurchaseOrders
    GROUP BY VendorID
)
SELECT 
    V.VendorName,
    V.Region,
    VS.TotalSpend
FROM VendorSpend VS
INNER JOIN dbo.Vendors V ON VS.VendorID = V.VendorID
WHERE VS.TotalSpend > (SELECT AVG(TotalSpend) FROM VendorSpend)
ORDER BY VS.TotalSpend DESC;

-- Chained CTE
WITH OrderStats AS (
    SELECT VendorID, COUNT(*) AS OrderCount, SUM(OrderAmount) AS TotalSpend
    FROM dbo.PurchaseOrders
    GROUP BY VendorID
),
Ranked AS (
    SELECT 
        VendorID,
        OrderCount,
        TotalSpend,
        TotalSpend / OrderCount AS AvgOrderValue
    FROM OrderStats
)
SELECT 
    V.VendorName,
    R.OrderCount,
    R.TotalSpend,
    R.AvgOrderValue
FROM Ranked R
INNER JOIN dbo.Vendors V ON R.VendorID = V.VendorID
ORDER BY R.AvgOrderValue DESC;

-- Recursive CTE : ORG Hierarchy
WITH OrgChart AS (
    -- Anchor: top of hierarchy
    SELECT 
        1 AS Level,
        CAST('CEO' AS NVARCHAR(50)) AS Title,
        CAST(NULL AS NVARCHAR(50)) AS Manager
    UNION ALL
    -- Recursive: each row produces children
    SELECT 
        Level + 1,
        CAST(CASE Level + 1
            WHEN 2 THEN 'VP Operations'
            WHEN 3 THEN 'Regional Manager'
            WHEN 4 THEN 'Buyer'
        END AS NVARCHAR(50)),
        CAST(CASE Level
            WHEN 1 THEN 'CEO'
            WHEN 2 THEN 'VP Operations'
            WHEN 3 THEN 'Regional Manager'
        END AS NVARCHAR(50))
    FROM OrgChart
    WHERE Level < 4
)
SELECT * FROM OrgChart;

-- ---------- BLOCK 3: ERROR HANDLING ----------
-- Basic TRY/CATCH
BEGIN TRY
    DECLARE @x INT = 1 / 0;
END TRY
BEGIN CATCH
    SELECT 
        ERROR_NUMBER()  AS ErrNum,
        ERROR_MESSAGE() AS ErrMsg,
        ERROR_LINE()    AS ErrLine,
        ERROR_SEVERITY() AS Severity;
END CATCH;

-- Transaction with ROLLBACK
BEGIN TRY
    BEGIN TRANSACTION;
    
    INSERT INTO dbo.Vendors (VendorName, VendorEmail, BankAccount, TaxID, Region)
    VALUES ('Rollback Test', 'rb@test.com', 'IN9999999999999999', 'TAXR001', 'North');
    
    -- Force an error mid-transaction
    THROW 50001, 'Simulated failure for practice', 1;
    
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    
    SELECT 
        ERROR_NUMBER()   AS ErrNum,
        ERROR_MESSAGE()  AS ErrMsg,
        @@TRANCOUNT      AS OpenTransactions;
END CATCH;

-- Verify nothing was inserted
SELECT COUNT(*) AS RollbackTestCount 
FROM dbo.Vendors 
WHERE VendorName = 'Rollback Test';

-- TRY/CATCH inside stored procedure (Dummy)
CREATE PROCEDURE dbo.usp_TestErrorFlow
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
            -- do work
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW; -- re-raise the original error
    END CATCH;
END;

-- ---------- BLOCK 4: SP + UDF + VIEW ----------
-- Basic Scalar UDF
CREATE OR ALTER FUNCTION dbo.fn_CalculateLineItemTotal(
    @Quantity INT,
    @UnitCost DECIMAL(18,2)
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    RETURN @Quantity * @UnitCost;
END;
GO

-- Test it
SELECT TOP 10
    LineItemID,
    ItemName,
    Quantity,
    UnitCost,
    dbo.fn_CalculateLineItemTotal(Quantity, UnitCost) AS LineTotal
FROM dbo.LineItems
ORDER BY LineItemID;


-- Stored Procedure
CREATE OR ALTER PROCEDURE dbo.usp_GetVendorOrders
    @VendorID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        PO.POID,
        PO.OrderAmount,
        PO.OrderDate,
        PO.Status,
        PO.Region
    FROM dbo.PurchaseOrders PO
    WHERE PO.VendorID = @VendorID
    ORDER BY PO.OrderDate DESC;
END;
GO

-- Test with VendorID 1
EXEC dbo.usp_GetVendorOrders @VendorID = 1;

-- Test with VendorID 5
EXEC dbo.usp_GetVendorOrders @VendorID = 5;

-- Basic View
CREATE OR ALTER VIEW dbo.vw_ActiveVendors AS
SELECT 
    V.VendorID,
    V.VendorName,
    V.Region,
    V.VendorEmail,
    COUNT(PO.POID)      AS OrderCount,
    SUM(PO.OrderAmount) AS TotalSpend
FROM dbo.Vendors V
LEFT JOIN dbo.PurchaseOrders PO ON V.VendorID = PO.VendorID
WHERE V.IsActive = 1
GROUP BY V.VendorID, V.VendorName, V.Region, V.VendorEmail;
GO

-- Query it like a table
SELECT * FROM dbo.vw_ActiveVendors ORDER BY TotalSpend DESCify all a

-- Verify all objects
SELECT 
    o.type_desc,
    o.name
FROM sys.objects o
WHERE o.type IN ('U', 'V', 'P', 'FN', 'IF', 'TF', 'TR')
  AND o.is_ms_shipped = 0
ORDER BY o.type_desc, o.name;

SELECT DB_NAME() AS CurrentDB, COUNT(*) AS VendorCount FROM dbo.Vendors;
