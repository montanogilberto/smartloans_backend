-- Restores CK_clients_clientType to its original 4-value definition.
-- WARNING: if any client rows have been created with clientType = 'pos'
-- since this migration was applied, running this rollback will make the
-- constraint reject those existing rows on their next UPDATE (SQL Server
-- does not retroactively validate existing rows on ALTER TABLE ADD
-- CONSTRAINT unless WITH CHECK is used and the table is re-scanned — but
-- any future UPDATE to a 'pos' row would fail). Reassign or migrate those
-- rows to a real value before rolling back if any exist.

ALTER TABLE dbo.clients DROP CONSTRAINT IF EXISTS CK_clients_clientType
GO

ALTER TABLE dbo.clients
    ADD CONSTRAINT CK_clients_clientType
    CHECK ([clientType]='lawyer' OR [clientType]='both' OR [clientType]='lender' OR [clientType]='borrower')
GO
