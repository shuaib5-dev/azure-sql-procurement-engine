SELECT @@VERSION AS EngineVersion,
       DB_NAME() AS DatabaseName,
       CURRENT_USER AS CurrentUser,
       SUSER_SNAME() AS LoginName,
       SYSDATETIME() AS ServerTime;

SELECT DB_NAME() AS CurrentDatabase;



-- Try to insert an order with a non-existent VendorID
INSERT INTO dbo.PurchaseOrders (VendorID, OrderAmount, Region)
VALUES (9999, 500.00, 'North');