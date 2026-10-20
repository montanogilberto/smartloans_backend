-- Rollback of 2026-10-20_reservations_source.sql. Re-run the PREVIOUS
-- sql/sp_reservations.sql first (git show HEAD~1:sql/sp_reservations.sql):
-- the current one INSERTs the column and would fail without it.
IF COL_LENGTH('dbo.reservations', 'source') IS NOT NULL
    ALTER TABLE [dbo].[reservations] DROP COLUMN source;
GO
