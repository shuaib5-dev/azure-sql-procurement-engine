-- ============================================
-- DAY 7: DYNAMIC DATA MASKING (DDM) + READ-ONLY ROLES
-- Database: ProcurementDB
-- Objective: Mask sensitive columns + implement UNMASK hierarchy + read-only role
-- ============================================

-- ============================================
-- SECTION 1: APPLY DDM TO SENSITIVE COLUMNS
-- ============================================

ALTER TABLE dbo.Vendors
ALTER COLUMN BankAccount ADD MASKED WITH (FUNCTION = 'default()');
GO

ALTER TABLE dbo.Vendors
ALTER COLUMN VendorEmail ADD MASKED WITH (FUNCTION = 'email()');
GO

ALTER TABLE dbo.Vendors
ALTER COLUMN TaxID ADD MASKED WITH (FUNCTION = 'partial(2, "XXXX", 2)');
GO


-- ============================================
-- SECTION 2: VERIFY MASKS APPLIED
-- ============================================

SELECT 
    c.name AS ColumnName,
    c.is_masked,
    m.masking_function
FROM sys.masked_columns m
INNER JOIN sys.columns c ON m.object_id = c.object_id AND m.column_id = c.column_id
WHERE OBJECT_NAME(m.object_id) = 'Vendors';
-- Expected: 3 rows (BankAccount, VendorEmail, TaxID)


-- ============================================
-- SECTION 3: MASKING TESTS WITH IMPERSONATION
-- ============================================

-- Admin sees real values (dbo has UNMASK by default)
SELECT TOP 3 VendorID, VendorName, VendorEmail, BankAccount, TaxID
FROM dbo.Vendors;

-- Grant SELECT on Vendors to all regional buyers
GRANT SELECT ON dbo.Vendors TO buyer_north;
GRANT SELECT ON dbo.Vendors TO buyer_south;
GRANT SELECT ON dbo.Vendors TO buyer_east;
GRANT SELECT ON dbo.Vendors TO buyer_west;
GO

-- buyer_north sees masked values
EXECUTE AS USER = 'buyer_north';
SELECT TOP 3 VendorID, VendorName, VendorEmail, BankAccount, TaxID
FROM dbo.Vendors;
REVERT;

-- DDM doesn't affect WHERE clauses — filtering uses REAL values
EXECUTE AS USER = 'buyer_north';
SELECT COUNT(*) AS VendorsWithRealEmail
FROM dbo.Vendors
WHERE VendorEmail = 'contact@acme.com';
-- Expected: 1 (filtering worked on real value)

SELECT VendorEmail FROM dbo.Vendors WHERE VendorEmail = 'contact@acme.com';
-- Expected: cXXX@XXXX.com (display is masked)
REVERT;


-- ============================================
-- SECTION 4: UNMASK HIERARCHY — 4 LEVELS
-- ============================================
-- Rule: GRANT and REVOKE must target the SAME securable.
-- Granting at column level and revoking at database level
-- does NOT remove the column-level grant.

-- ----------------------------------------------
-- LEVEL 1: COLUMN-LEVEL UNMASK (buyer_north)
-- ----------------------------------------------
GRANT UNMASK ON dbo.Vendors(VendorEmail) TO buyer_north;
GO

-- Expected: VendorEmail unmasked, BankAccount + TaxID still masked
EXECUTE AS USER = 'buyer_north';
SELECT TOP 3 VendorID, VendorEmail, BankAccount, TaxID FROM dbo.Vendors;
REVERT;

REVOKE UNMASK ON dbo.Vendors(VendorEmail) FROM buyer_north;
GO

-- Verify masking restored
EXECUTE AS USER = 'buyer_north';
SELECT TOP 3 VendorID, VendorEmail FROM dbo.Vendors;
REVERT;

-- ----------------------------------------------
-- LEVEL 2: TABLE-LEVEL UNMASK (buyer_south)
-- ----------------------------------------------
GRANT UNMASK ON dbo.Vendors TO buyer_south;
GO

-- Expected: All 3 masked columns on Vendors unmasked
EXECUTE AS USER = 'buyer_south';
SELECT TOP 3 VendorID, VendorEmail, BankAccount, TaxID FROM dbo.Vendors;
REVERT;

REVOKE UNMASK ON dbo.Vendors FROM buyer_south;
GO

-- ----------------------------------------------
-- LEVEL 3: SCHEMA-LEVEL UNMASK (buyer_east)
-- ----------------------------------------------
GRANT UNMASK ON SCHEMA::dbo TO buyer_east;
GO

-- Expected: All masked columns in dbo schema unmasked
EXECUTE AS USER = 'buyer_east';
SELECT TOP 3 VendorID, VendorEmail, BankAccount, TaxID FROM dbo.Vendors;
REVERT;

REVOKE UNMASK ON SCHEMA::dbo FROM buyer_east;
GO

-- ----------------------------------------------
-- LEVEL 4: DATABASE-LEVEL UNMASK (buyer_west)
-- ----------------------------------------------
GRANT UNMASK TO buyer_west;
GO

-- Expected: All masked columns in entire database unmasked
EXECUTE AS USER = 'buyer_west';
SELECT TOP 3 VendorID, VendorEmail, BankAccount, TaxID FROM dbo.Vendors;
REVERT;

REVOKE UNMASK FROM buyer_west;
GO

-- Verify all UNMASK grants cleaned up
SELECT 
    pr.name AS UserName,
    p.class_desc,
    p.permission_name,
    p.state_desc,
    OBJECT_NAME(p.major_id) AS ObjectName,
    COL_NAME(p.major_id, p.minor_id) AS ColumnName
FROM sys.database_permissions p
INNER JOIN sys.database_principals pr ON p.grantee_principal_id = pr.principal_id
WHERE pr.name IN ('buyer_north', 'buyer_south', 'buyer_east', 'buyer_west')
  AND p.permission_name = 'UNMASK';
-- Expected: 0 rows


-- ============================================
-- SECTION 5: CREATE READ-ONLY ROLE
-- ============================================

CREATE ROLE app_readonly;
GO

GRANT SELECT ON SCHEMA::dbo TO app_readonly;
GO

DENY INSERT, UPDATE, DELETE ON SCHEMA::dbo TO app_readonly;
GO

ALTER ROLE app_readonly ADD MEMBER buyer_east;
GO

-- Verify role membership
SELECT 
    r.name AS RoleName,
    m.name AS MemberName
FROM sys.database_role_members rm
INNER JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
INNER JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
WHERE r.name = 'app_readonly';
-- Expected: 1 row (app_readonly -> buyer_east)


-- ============================================
-- SECTION 6: READ-ONLY ENFORCEMENT TESTS
-- ============================================

-- SELECT works
EXECUTE AS USER = 'buyer_east';
SELECT TOP 3 VendorID, VendorName, VendorEmail FROM dbo.Vendors;
-- Expected: 3 rows, VendorEmail masked
REVERT;

-- INSERT denied
EXECUTE AS USER = 'buyer_east';
INSERT INTO dbo.Vendors (VendorName, VendorEmail, BankAccount, TaxID, Region)
VALUES ('Blocked Vendor', 'blocked@test.com', 'IN000', 'TAX000', 'East');
-- Expected: The INSERT permission was denied on the object 'Vendors'
REVERT;

-- UPDATE denied
EXECUTE AS USER = 'buyer_east';
UPDATE dbo.Vendors SET VendorName = 'Hacked' WHERE VendorID = 1;
-- Expected: The UPDATE permission was denied on the object 'Vendors'
REVERT;

-- DELETE denied
EXECUTE AS USER = 'buyer_east';
DELETE FROM dbo.Vendors WHERE VendorID = 999;
-- Expected: The DELETE permission was denied on the object 'Vendors'
REVERT;

-- DENY beats GRANT — buyer_east was granted INSERT on PurchaseOrders in Day 6,
-- but the schema-level DENY on app_readonly overrides it.
EXECUTE AS USER = 'buyer_east';
INSERT INTO dbo.PurchaseOrders (VendorID, OrderAmount, Status, Region)
VALUES (1, 500.00, 'Pending', 'East');
-- Expected: Permission denied — schema-level DENY wins over table-level GRANT
REVERT;


-- ============================================
-- LESSONS LEARNED
-- ============================================
-- 1. DDM is a DISPLAY-layer protection. Data at rest is unchanged.
--    Anyone with UNMASK (or db_owner) sees real values.
--
-- 2. DDM does NOT affect WHERE clauses. Filters always compare against
--    real values. This is by design — DDM prevents accidental exposure,
--    not data extraction.
--
-- 3. UNMASK can be granted at 4 levels:
--    - COLUMN   → one column
--    - TABLE    → all masked columns in one table
--    - SCHEMA   → all masked columns across schemas
--    - DATABASE → all masked columns in the database
--
-- 4. GRANT and REVOKE must target the SAME securable.
--    Granting at column level and revoking at database level
--    does NOT remove the column-level grant.
--
-- 5. Follow least-privilege: grant UNMASK at the narrowest scope needed.
--
-- 6. DDM and RLS are complementary:
--    - RLS filters ROWS (which records a user sees)
--    - DDM masks COLUMNS (which fields a user sees, and how)
--
-- 7. DENY takes precedence over GRANT in SQL Server's security model.
--    A schema-level DENY overrides a table-level GRANT.
--    This is defense in depth — even accidental future grants
--    cannot escalate privileges past the DENY.
--
-- 8. When debugging "user still sees unmasked data":
--    Query sys.database_permissions filtered by permission_name = 'UNMASK'
--    and grantee_principal_id. Revoke at the exact level shown.


-- ============================================
-- CLEANUP (do not run today — kept for reference)
-- ============================================
-- ALTER TABLE dbo.Vendors ALTER COLUMN BankAccount DROP MASKED;
-- ALTER TABLE dbo.Vendors ALTER COLUMN VendorEmail DROP MASKED;
-- ALTER TABLE dbo.Vendors ALTER COLUMN TaxID DROP MASKED;
-- DROP ROLE app_readonly;
-- REVOKE SELECT ON dbo.Vendors FROM buyer_north;
-- REVOKE SELECT ON dbo.Vendors FROM buyer_south;
-- REVOKE SELECT ON dbo.Vendors FROM buyer_east;
-- REVOKE SELECT ON dbo.Vendors FROM buyer_west;