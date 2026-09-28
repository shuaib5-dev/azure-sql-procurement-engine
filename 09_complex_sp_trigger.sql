-- ============================================================
-- DAY 9: COMPLEX STORED PROCEDURE + AFTER INSERT TRIGGER
-- Database: ProcurementDB
-- ============================================================

USE ProcurementDB;
GO

-- ============================================================
-- SECTION 1: COMPLEX STORED PROCEDURE
-- ============================================================
-- Features:
--   - Multi-input validation before transaction
--   - Single transaction wrapping 3 inserts
--   - JSON parsing via OPENJSON
--   - TRY/CATCH with rollback + re-throw
--   - OUTPUT parameter for new POID
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.usp_CreatePurchaseOrder
    @VendorID      INT,
    @OrderAmount   DECIMAL(18,2),
    @Region        NVARCHAR(20),
    @LineItemsJSON NVARCHAR(MAX),
    @NewPOID       INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        -- VALIDATION
        IF NOT EXISTS (SELECT 1 FROM dbo.Vendors 
                       WHERE VendorID = @VendorID AND IsActive = 1)
            THROW 50001, 'Vendor does not exist or is inactive', 1;

        IF @OrderAmount <= 0
            THROW 50002, 'OrderAmount must be positive', 1;

        IF @Region NOT IN ('North', 'South', 'East', 'West')
            THROW 50003, 'Invalid region', 1;

        -- TRANSACTION
        BEGIN TRANSACTION;

        INSERT INTO dbo.PurchaseOrders (VendorID, OrderAmount, Status, Region)
        VALUES (@VendorID, @OrderAmount, 'Pending', @Region);

        SET @NewPOID = SCOPE_IDENTITY();

        INSERT INTO dbo.LineItems (POID, ItemName, Quantity, UnitCost)
        SELECT 
            @NewPOID,
            JSON_VALUE(item.value, '$.ItemName'),
            JSON_VALUE(item.value, '$.Quantity'),
            JSON_VALUE(item.value, '$.UnitCost')
        FROM OPENJSON(@LineItemsJSON) AS item;

        INSERT INTO dbo.ApprovalLogs (POID, ApproverEmail, Action, Comments)
        VALUES (@NewPOID, 'system@procurement', 'Created', 
                'PO created via usp_CreatePurchaseOrder');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH;
END;
GO


-- ============================================================
-- SECTION 2: TEST — SUCCESS CASE
-- ============================================================
DECLARE @NewID INT;

EXEC dbo.usp_CreatePurchaseOrder
    @VendorID      = 1,
    @OrderAmount   = 5000.00,
    @Region        = 'North',
    @LineItemsJSON = N'[
        {"ItemName":"Laptop Stand","Quantity":2,"UnitCost":1500.00},
        {"ItemName":"USB-C Hub","Quantity":3,"UnitCost":750.00}
    ]',
    @NewPOID       = @NewID OUTPUT;

SELECT @NewID AS NewPOID;
SELECT * FROM dbo.PurchaseOrders WHERE POID = @NewID;
SELECT * FROM dbo.LineItems WHERE POID = @NewID;
SELECT * FROM dbo.ApprovalLogs WHERE POID = @NewID;
-- Expected: 1 PO + 2 LineItems + 1 Log


-- ============================================================
-- SECTION 3: TEST — FAILURE CASE (PROVES ROLLBACK)
-- ============================================================
BEGIN TRY
    DECLARE @ID INT;
    EXEC dbo.usp_CreatePurchaseOrder
        @VendorID = 9999, @OrderAmount = 100, @Region = 'North',
        @LineItemsJSON = '[]', @NewPOID = @ID OUTPUT;
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE() AS ErrorMsg;
END CATCH;
-- Expected: Error 'Vendor does not exist or is inactive'. Zero rows inserted.


-- ============================================================
-- SECTION 4: AFTER INSERT TRIGGER
-- ============================================================
CREATE OR ALTER TRIGGER trg_PurchaseOrders_AuditInsert
ON dbo.PurchaseOrders
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.ApprovalLogs (POID, ApproverEmail, Action, Comments)
    SELECT 
        i.POID,
        'trigger@procurement',
        'AutoLogged',
        'Auto-audit: new PO inserted for amount ' + CAST(i.OrderAmount AS NVARCHAR(20))
    FROM inserted i;
END;
GO


-- ============================================================
-- SECTION 5: TEST — DIRECT INSERT TRIGGERS AUDIT
-- ============================================================
INSERT INTO dbo.PurchaseOrders (VendorID, OrderAmount, Status, Region)
VALUES (2, 999.99, 'Pending', 'South');

SELECT TOP 3 * FROM dbo.ApprovalLogs ORDER BY LogID DESC;
-- Expected: New row with ApproverEmail = 'trigger@procurement'


-- ============================================================
-- SECTION 6: TEST — TRIGGER ROLLS BACK WITH PARENT TRANSACTION
-- ============================================================
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO dbo.PurchaseOrders (VendorID, OrderAmount, Status, Region)
        VALUES (3, 1234.00, 'Pending', 'East');
        THROW 50099, 'Simulating failure after insert', 1;
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT ERROR_MESSAGE() AS ErrMsg;
END CATCH;

SELECT TOP 3 * FROM dbo.ApprovalLogs ORDER BY LogID DESC;
-- Expected: No new audit log row — rolled back with parent


-- ============================================================
-- LESSONS LEARNED
-- ============================================================
-- 1. Validation runs BEFORE BEGIN TRANSACTION — no locks wasted on bad input.
-- 2. SET XACT_ABORT ON + TRY/CATCH gives automatic rollback + error visibility.
-- 3. THROW in CATCH re-raises so the caller sees the original error code/message.
-- 4. SCOPE_IDENTITY() is safer than @@IDENTITY (avoids trigger-generated IDs).
-- 5. OPENJSON turns JSON arrays into rows — clean way to bulk-insert structured input.
-- 6. Triggers run INSIDE the caller's transaction. If the transaction rolls back,
--    the trigger's side effects are also rolled back (no orphan log entries).
-- 7. AFTER INSERT triggers use the `inserted` pseudo-table — always available inside
--    the trigger body. For an INSERT trigger, `deleted` is empty.
-- 8. Triggers should be used for AUDIT LOGGING, not business logic.


-- ============================================================
-- CLEANUP (do not run now)
-- ============================================================
-- DROP TRIGGER trg_PurchaseOrders_AuditInsert;
-- DROP PROCEDURE dbo.usp_CreatePurchaseOrder;