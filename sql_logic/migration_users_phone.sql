-- Migration: add cellphone to dbo.users so accounts created via phone can be found
-- Run once on production Azure SQL

IF NOT EXISTS (
    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_NAME = 'users' AND COLUMN_NAME = 'cellphone'
)
BEGIN
    ALTER TABLE [dbo].[users] ADD [cellphone] NVARCHAR(20) NULL;
    PRINT 'Column cellphone added to dbo.users';
END
ELSE
    PRINT 'Column cellphone already exists — skipped';
GO
