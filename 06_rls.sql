-- ============================================
-- DAY 6: ROW-LEVEL SECURITY (RLS)
-- Database: ProcurementDB
-- Objective: Restrict PurchaseOrders rows by user region
-- ============================================

-- ============================================
-- SECTION 1: CREATE TEST USERS
-- ============================================
-- Run these while connected to master:
-- CREATE LOGIN buyer_north WITH PASSWORD = 'Str0ngP@ss!2026';
-- CREATE LOGIN buyer_south WITH PASSWORD = 'Str0ngP@ss!2026';
-- CREATE LOGIN buyer_east  WITH PASSWORD = 'Str0ngP@ss!2026';
-- CREATE LOGIN buyer_west  WITH PASSWORD = 'Str0ngP@ss!2026';

-- Run these while connected to ProcurementDB:
-- CREATE USER buyer_north FOR LOGIN buyer_north;
-- CREATE USER buyer_south FOR LOGIN buyer_south;
-- CREATE USER buyer_east  FOR LOGIN buyer_east;
-- CREATE USER buyer_west  FOR LOGIN buyer_west;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.PurchaseOrders TO buyer_north;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.PurchaseOrders TO buyer_south;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.PurchaseOrders TO buyer_east;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.PurchaseOrders TO buyer_west;


-- ============================================
-- SECTION 2: SECURITY SCHEMA
-- ============================================
CREATE SCHEMA Security;
GO


-- ============================================
-- SECTION 3: PREDICATE FUNCTION
-- ============================================
CREATE FUNCTION Security.fn_RegionFilter(@Region NVARCHAR(20))
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT 1 AS fn_result
    WHERE 'buyer_' + LOWER(@Region) = USER_NAME()
       OR USER_NAME() = 'dbo'
       OR IS_ROLEMEMBER('db_owner') = 1
);
GO


-- ============================================
-- SECTION 4: SECURITY POLICY
-- ============================================
CREATE SECURITY POLICY Security.RegionSecurityPolicy
ADD FILTER PREDICATE Security.fn_RegionFilter(Region)
ON dbo.PurchaseOrders
WITH (STATE = ON);
GO


-- ============================================
-- SECTION 5: VERIFICATION QUERIES
-- ============================================
-- Confirm policy is active
SELECT name, is_enabled FROM sys.security_policies
WHERE name = 'RegionSecurityPolicy';
-- Expected: is_enabled = 1

-- Confirm predicate is bound
SELECT 
    sp.name AS PolicyName,
    sp.is_enabled,
    spp.predicate_type_desc,
    OBJECT_NAME(spp.target_object_id) AS TargetTable
FROM sys.security_policies sp
INNER JOIN sys.security_predicates spp ON sp.object_id = spp.object_id
WHERE sp.name = 'RegionSecurityPolicy';
-- Expected: predicate_type_desc = FILTER, TargetTable = PurchaseOrders


-- ============================================
-- SECTION 6: ROW ISOLATION TEST
-- ============================================
-- Expected: Admin = 5100, each region = 1275

SELECT 'Admin' AS UserRole, COUNT(*) AS VisibleRows FROM dbo.PurchaseOrders;

EXECUTE AS USER = 'buyer_north';
SELECT 'North' AS UserRole, COUNT(*) AS VisibleRows FROM dbo.PurchaseOrders;
REVERT;

EXECUTE AS USER = 'buyer_south';
SELECT 'South' AS UserRole, COUNT(*) AS VisibleRows FROM dbo.PurchaseOrders;
REVERT;

EXECUTE AS USER = 'buyer_east';
SELECT 'East' AS UserRole, COUNT(*) AS VisibleRows FROM dbo.PurchaseOrders;
REVERT;

EXECUTE AS USER = 'buyer_west';
SELECT 'West' AS UserRole, COUNT(*) AS VisibleRows FROM dbo.PurchaseOrders;
REVERT;


-- ============================================
-- SECTION 7: CROSS-REGION INVISIBILITY
-- ============================================
EXECUTE AS USER = 'buyer_north';
SELECT COUNT(*) AS SouthRowsVisibleToNorth 
FROM dbo.PurchaseOrders 
WHERE Region = 'South';
-- Expected: 0 — RLS hides rows even when explicitly queried
REVERT;


-- ============================================
-- SECTION 8: ENABLE / DISABLE TEST
-- ============================================
ALTER SECURITY POLICY Security.RegionSecurityPolicy WITH (STATE = OFF);
EXECUTE AS USER = 'buyer_north';
SELECT COUNT(*) AS RowsWhenDisabled FROM dbo.PurchaseOrders;
REVERT;
-- Expected: 5100

ALTER SECURITY POLICY Security.RegionSecurityPolicy WITH (STATE = ON);
EXECUTE AS USER = 'buyer_north';
SELECT COUNT(*) AS RowsWhenEnabled FROM dbo.PurchaseOrders;
REVERT;
-- Expected: 1275


-- ============================================
-- LESSONS LEARNED
-- ============================================
-- 1. RLS predicate must compare values that can actually match:
--    'North' != 'buyer_north' — use 'buyer_' + LOWER(@Region) = USER_NAME()
--
-- 2. SCHEMABINDING prevents ALTERing the predicate function while the policy
--    references it. Even STATE = OFF doesn't unlock it.
--    Fix: DROP the policy, alter the function, then recreate the policy.
--
-- 3. Disabling (STATE = OFF) stops enforcement at runtime but keeps the
--    metadata dependency. For schema changes you must DROP.
--
-- 4. RLS is silent — users get no error. Rows simply don't exist from
--    their perspective. This is by design.
--
-- 5. To modify the function later, the correct pattern is:
--      DROP SECURITY POLICY ...;
--      ALTER FUNCTION ...;
--      CREATE SECURITY POLICY ...;


-- ============================================
-- CLEANUP (do not run today — kept for reference)
-- ============================================
-- DROP SECURITY POLICY Security.RegionSecurityPolicy;
-- DROP FUNCTION Security.fn_RegionFilter;
-- DROP SCHEMA Security;
-- DROP USER buyer_north;
-- DROP USER buyer_south;
-- DROP USER buyer_east;
-- DROP USER buyer_west;
-- DROP LOGIN buyer_north;  -- run in master
-- DROP LOGIN buyer_south;  -- run in master
-- DROP LOGIN buyer_east;   -- run in master
-- DROP LOGIN buyer_west;   -- run in master