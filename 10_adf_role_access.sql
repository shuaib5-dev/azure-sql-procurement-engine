USE ProcurementDB;
GO

-- Create the ADF managed identity as a database user
CREATE USER [adf-procurement-2026] FROM EXTERNAL PROVIDER;
GO

-- Grant read access (minimum needed for copy source)
ALTER ROLE db_datareader ADD MEMBER [adf-procurement-2026];
GO

-- Grant write access for any future sink-to-SQL pipelines
ALTER ROLE db_datawriter ADD MEMBER [adf-procurement-2026];
GO

-- Verify
SELECT name, type_desc, authentication_type_desc
FROM sys.database_principals
WHERE name = 'adf-procurement-2026';

USE ProcurementDB;
GO

-- Give ADF's managed identity elevated access
ALTER ROLE db_owner ADD MEMBER [adf-procurement-2026];
GO

-- Verify
SELECT 
    r.name AS RoleName,
    m.name AS MemberName
FROM sys.database_role_members rm
INNER JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
INNER JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
WHERE m.name = 'adf-procurement-2026';