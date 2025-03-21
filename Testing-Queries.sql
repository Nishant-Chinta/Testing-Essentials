-- Get Tables, Views, and Stored Procedures
--tables
SELECT 'Table' AS object_type, table_name AS object_name
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
ORDER BY object_name ASC;

-----------Views
SELECT 'View' AS object_type, table_name AS object_name
FROM information_schema.tables
WHERE table_type = 'VIEW'
ORDER BY object_name ASC;

-----------SP's
SELECT 'Stored Procedure' AS object_type, name AS object_name
FROM sys.objects
WHERE type = 'P'
ORDER BY object_name ASC;


----------Droping the constrains to drop Tables

DECLARE @sql NVARCHAR(MAX) = '';

SELECT @sql = @sql + 'ALTER TABLE ' + QUOTENAME(OBJECT_NAME(fk.parent_object_id)) + 
              ' DROP CONSTRAINT ' + QUOTENAME(fk.name) + ';' + CHAR(13)
FROM sys.foreign_keys AS fk;

-- Output the generated SQL
PRINT @sql;

EXEC sp_executesql @sql



---------Table,indexes storage..

SELECT 
    s.name AS [SchemaName],
    t.name AS [TableName],
    CAST(SUM(a.used_pages) * 8.0 / 1024 AS DECIMAL(12,2)) AS [TotalMB],
    CAST(SUM(a.data_pages) * 8.0 / 1024 AS DECIMAL(12,2)) AS [DataMB],
    CAST((SUM(a.used_pages) - SUM(a.data_pages)) * 8.0 / 1024 AS DECIMAL(12,2)) AS [IndexMB]
FROM sys.tables t
JOIN sys.schemas s 
    ON t.schema_id = s.schema_id
JOIN sys.indexes i 
    ON t.object_id = i.object_id
JOIN sys.partitions p 
    ON i.object_id = p.object_id 
    AND i.index_id = p.index_id
JOIN sys.allocation_units a 
    ON p.partition_id = a.container_id
GROUP BY s.name, t.name
ORDER BY [TotalMB] DESC;

----------How to find who last modified the table/Objects in SQL server?

DECLARE @filename VARCHAR(255) 
SELECT @FileName = SUBSTRING(path, 0, LEN(path)-CHARINDEX('\', REVERSE(path))+1) + '\Log.trc'  
FROM sys.traces   
WHERE is_default = 1;  

SELECT gt.HostName, 
       gt.ApplicationName, 
       gt.NTUserName, 
       gt.NTDomainName, 
       gt.LoginName, 
       gt.SPID, 
       gt.EventClass, 
       te.Name AS EventName,
       gt.EventSubClass,      
       gt.TEXTData, 
       gt.StartTime, 
       gt.EndTime, 
       gt.ObjectName, 
       gt.DatabaseName, 
       gt.FileName, 
       gt.IsSystem
FROM [fn_trace_gettable](@filename, DEFAULT) gt 
JOIN sys.trace_events te ON gt.EventClass = te.trace_event_id 
WHERE EventClass in (164) 
ORDER BY StartTime DESC; 


-------------- Display space information across all databases in SQL MI (excluding XTP files)
CREATE TABLE #DBSpaceInfo
(
    DatabaseName NVARCHAR(128),
    FileName NVARCHAR(128),
    FileType NVARCHAR(60),
    FileState NVARCHAR(60),
    FileSizeMB DECIMAL(18, 2),
    SpaceUsedMB DECIMAL(18, 2),
    FreeSpaceMB DECIMAL(18, 2),
    PercentUsed DECIMAL(18, 2),
    MaxSizeMB DECIMAL(18, 2),
    GrowthMB DECIMAL(18, 2),
    IsPercentGrowth BIT,
    PhysicalName NVARCHAR(260)
);

DECLARE @DBName NVARCHAR(128);
DECLARE @SQL NVARCHAR(MAX);

DECLARE db_cursor CURSOR FOR
SELECT name
FROM sys.databases
WHERE database_id > 4 -- Skip system databases
AND state = 0; -- Only online databases

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'
    USE [' + @DBName + '];
    INSERT INTO #DBSpaceInfo
    SELECT 
        DB_NAME() AS DatabaseName,
        f.name AS FileName,
        f.type_desc AS FileType,
        f.state_desc AS FileState,
        CAST(f.size / 128.0 AS DECIMAL(18, 2)) AS FileSizeMB,
        CAST(FILEPROPERTY(f.name, ''SpaceUsed'') / 128.0 AS DECIMAL(18, 2)) AS SpaceUsedMB,
        CAST((f.size - FILEPROPERTY(f.name, ''SpaceUsed'')) / 128.0 AS DECIMAL(18, 2)) AS FreeSpaceMB,
        CAST(FILEPROPERTY(f.name, ''SpaceUsed'') * 100.0 / NULLIF(f.size, 0) AS DECIMAL(18, 2)) AS PercentUsed,
        CAST(f.max_size / 128.0 AS DECIMAL(18, 2)) AS MaxSizeMB,
        CAST(f.growth / 128.0 AS DECIMAL(18, 2)) AS GrowthMB,
        f.is_percent_growth AS IsPercentGrowth,
        f.physical_name AS PhysicalName
    FROM 
        sys.database_files f
    WHERE
        f.type_desc NOT IN (''FILESTREAM'', ''MEMORY_OPTIMIZED_DATA'', ''LOG'') -- Exclude XTP/In-Memory OLTP files
    ';

    EXEC sp_executesql @SQL;
    FETCH NEXT FROM db_cursor INTO @DBName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Display the results
SELECT * FROM #DBSpaceInfo
ORDER BY DatabaseName, FileType, FileName;

-- Clean up
DROP TABLE #DBSpaceInfo;
