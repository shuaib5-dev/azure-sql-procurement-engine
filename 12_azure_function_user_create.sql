USE ProcurementDB;
GO

-- Create a database user mapped to the Function App's managed identity
CREATE USER [func-export-2026] FROM EXTERNAL PROVIDER;
GO

-- Grant read access
ALTER ROLE db_datareader ADD MEMBER [func-export-2026];
GO

-- Verify
SELECT 
    name, 
    type_desc, 
    authentication_type_desc,
    create_date
FROM sys.database_principals
WHERE name = 'func-export-2026';

