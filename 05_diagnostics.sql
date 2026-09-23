-- ============================================
-- DAY 5: QUERY STORE & DMV DIAGNOSTICS
-- Database: ProcurementDB
-- Objective: Identify top CPU and IO queries using Query Store and DMVs
-- ============================================

-- ============================================
-- SECTION 1: VERIFY QUERY STORE STATE
-- ============================================
SELECT 
    actual_state_desc,
    readonly_reason,
    current_storage_size_mb,
    max_storage_size_mb
FROM sys.database_query_store_options;
-- Expected: actual_state_desc = READ_WRITE


-- ============================================
-- SECTION 2: GENERATE WORKLOAD
-- 5 patterns x 15 runs = 75 executions to populate DMV/Query Store stats
-- ============================================

-- Workload 1: Heavy aggregation (CPU-bound)
SELECT V.Region, V.VendorName,
       COUNT(PO.POID) AS Orders,
       SUM(PO.OrderAmount) AS Spend
FROM dbo.Vendors V
INNER JOIN dbo.PurchaseOrders PO ON V.VendorID = PO.VendorID
GROUP BY V.Region, V.VendorName;
GO 15

-- Workload 2: Filter on low-cardinality column (uses Day 4 covering index)
SELECT POID, OrderAmount 
FROM dbo.PurchaseOrders 
WHERE Status = 'Pending';
GO 15

-- Workload 3: Range filter on date
SELECT POID, OrderAmount, OrderDate
FROM dbo.PurchaseOrders
WHERE OrderDate >= '2026-01-01';
GO 15

-- Workload 4: JOIN with computed total
SELECT PO.POID, SUM(LI.Quantity * LI.UnitCost) AS LineTotal
FROM dbo.PurchaseOrders PO
INNER JOIN dbo.LineItems LI ON PO.POID = LI.POID
WHERE PO.Status = 'Approved'
GROUP BY PO.POID;
GO 15

-- Workload 5: Correlated subquery (intentionally slow — N+1 anti-pattern)
SELECT V.VendorID, V.VendorName,
    (SELECT SUM(OrderAmount) FROM dbo.PurchaseOrders 
     WHERE VendorID = V.VendorID) AS TotalSpend
FROM dbo.Vendors V;
GO 15


-- ============================================
-- SECTION 3: QUERY STORE CAPTURE VERIFICATION
-- ============================================
SELECT 
    (SELECT COUNT(*) FROM sys.query_store_query) AS CapturedQueries,
    (SELECT current_storage_size_mb 
     FROM sys.database_query_store_options) AS StorageMB;


-- ============================================
-- SECTION 4: QUERY STORE PER-QUERY DETAIL
-- ============================================
SELECT 
    q.query_id,
    qt.query_sql_text,
    COUNT(DISTINCT p.plan_id) AS PlanCount,
    SUM(rs.count_executions)  AS TotalExecutions
FROM sys.query_store_query q
INNER JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
INNER JOIN sys.query_store_plan p ON q.query_id = p.query_id
INNER JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
GROUP BY q.query_id, qt.query_sql_text
ORDER BY TotalExecutions DESC;


-- ============================================
-- SECTION 5: TOP CPU QUERIES (DMV)
-- Filter by base table name to exclude IntelliSense noise
-- ============================================
SELECT TOP 10
    qs.execution_count                                        AS Executions,
    qs.total_worker_time / 1000.0                             AS TotalCPU_ms,
    qs.total_worker_time / qs.execution_count / 1000.0        AS AvgCPU_ms,
    qs.total_logical_reads / qs.execution_count               AS AvgReads,
    qs.total_elapsed_time / qs.execution_count / 1000.0       AS AvgElapsed_ms,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset 
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1
    ) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE (st.text LIKE '%PurchaseOrders%' 
    OR st.text LIKE '%LineItems%'
    OR st.text LIKE '%Vendors%'
    OR st.text LIKE '%ApprovalLogs%')
  AND st.text NOT LIKE '%sys.%'
ORDER BY qs.total_worker_time DESC;


-- ============================================
-- SECTION 6: TOP IO QUERIES (DMV)
-- ============================================
SELECT TOP 5
    qs.execution_count                                   AS Executions,
    qs.total_logical_reads / qs.execution_count          AS AvgReads,
    qs.total_logical_reads                               AS TotalReads,
    qs.total_worker_time / qs.execution_count / 1000.0   AS AvgCPU_ms,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset 
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset END - qs.statement_start_offset)/2)+1
    ) AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE (st.text LIKE '%PurchaseOrders%' 
    OR st.text LIKE '%LineItems%'
    OR st.text LIKE '%Vendors%'
    OR st.text LIKE '%ApprovalLogs%')
  AND st.text NOT LIKE '%sys.%'
ORDER BY qs.total_logical_reads DESC;


-- ============================================
-- SECTION 7: LIVE REQUESTS (What's running right now)
-- ============================================
SELECT 
    r.session_id,
    r.status,
    r.command,
    r.wait_type,
    r.wait_time,
    r.cpu_time,
    r.total_elapsed_time,
    DB_NAME(r.database_id) AS DatabaseName,
    SUBSTRING(st.text, (r.statement_start_offset/2)+1,
        ((CASE r.statement_end_offset 
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE r.statement_end_offset END - r.statement_start_offset)/2)+1
    ) AS QueryText
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.session_id <> @@SPID
ORDER BY r.total_elapsed_time DESC;
-- Expected: 0 rows when idle


-- ============================================
-- SECTION 8: FLUSH QUERY STORE TO DISK
-- ============================================
EXEC sp_query_store_flush_db;
-- Forces in-memory Query Store data to disk