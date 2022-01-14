
use ReportsView; 
go 

-- Run the update sprocs for the ShpSld set of reports---
---------------------------------------------------------

DECLARE @step INT = 0, @result INT = 0, @sql NVARCHAR(MAX) = N'';
DECLARE @tbl TABLE([step] INT PRIMARY KEY, [pname] NVARCHAR(513));    
INSERT @tbl([step],[pname]) VALUES
    -- Updates the mapping of item codes to custom groupings.
    (1,N'dbo.ProdGoals_ItemMaster_UPDATE')
    -- Updates each specified table. These could be run in parallel, 
    -- but there's a crapton of overhead in all means of getting that set up.
    -- SSIS? CLR? OLE Automation? Power Shell? Scheduled Jobs?
    ,(2,N'dbo.ShpSld_New_UPDATE')
    ,(3,N'dbo.ShpSld_BI_UPDATE')
    ,(4,N'dbo.ShpSld_SIPS_UPDATE')
    ,(5,N'dbo.ShpSld_FrlnBS_UPDATE')
    ,(6,N'dbo.ShpSld_fEAN_UPDATE')
    ,(7,N'dbo.ShpSld_OnlineNew_UPDATE')
    ,(8,N'dbo.ShpSld_OnlineUsed_UPDATE')
    ;

SELECT @sql += N'
SET @step = ' + CONVERT(VARCHAR(12), 
    ROW_NUMBER() OVER (ORDER BY step)) + ';
IF @result = 0
BEGIN
    BEGIN TRY
    EXEC @result = ' + pname + ';
    END TRY
    BEGIN CATCH
    SET @result = ERROR_NUMBER();
    RETURN;
    END CATCH' 
FROM @tbl ORDER BY [step] OPTION (MAXDOP 1); 

SET @sql += REPLICATE(N' END ', @@ROWCOUNT);

-- select @sql


EXEC sp_executesql @sql, N'@step INT OUTPUT, @result INT OUTPUT', 
@step = @step OUTPUT, @result = @result OUTPUT;

PRINT 'Failed at step ' + CONVERT(VARCHAR(12), @step);
PRINT 'Error number was ' + CONVERT(VARCHAR(12), @result);
