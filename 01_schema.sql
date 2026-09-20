-- ============================================
-- PROCUREMENT SCHEMA
-- ============================================

CREATE TABLE dbo.Vendors (
    VendorID      INT IDENTITY(1,1) PRIMARY KEY,
    VendorName    NVARCHAR(100) NOT NULL,
    VendorEmail   NVARCHAR(100) NOT NULL,
    BankAccount   NVARCHAR(34) NOT NULL,
    TaxID         NVARCHAR(20) NOT NULL,
    Region        NVARCHAR(20) NOT NULL,
    IsActive      BIT DEFAULT 1,
    CreatedAt     DATETIME2 DEFAULT SYSUTCDATETIME()
);

CREATE TABLE dbo.PurchaseOrders (
    POID          INT IDENTITY(1000,1) PRIMARY KEY,
    VendorID      INT NOT NULL FOREIGN KEY REFERENCES dbo.Vendors(VendorID),
    OrderAmount   DECIMAL(18,2) NOT NULL,
    OrderDate     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    Status        NVARCHAR(20) DEFAULT 'Pending',
    Region        NVARCHAR(20) NOT NULL
);

CREATE TABLE dbo.LineItems (
    LineItemID    INT IDENTITY(1,1) PRIMARY KEY,
    POID          INT NOT NULL FOREIGN KEY REFERENCES dbo.PurchaseOrders(POID),
    ItemName      NVARCHAR(100) NOT NULL,
    Quantity      INT NOT NULL,
    UnitCost      DECIMAL(18,2) NOT NULL
);

CREATE TABLE dbo.ApprovalLogs (
    LogID         INT IDENTITY(1,1) PRIMARY KEY,
    POID          INT NOT NULL FOREIGN KEY REFERENCES dbo.PurchaseOrders(POID),
    ApproverEmail NVARCHAR(100) NOT NULL,
    Action        NVARCHAR(20) NOT NULL,
    ActionDate    DATETIME2 DEFAULT SYSUTCDATETIME(),
    Comments      NVARCHAR(500) NULL
);