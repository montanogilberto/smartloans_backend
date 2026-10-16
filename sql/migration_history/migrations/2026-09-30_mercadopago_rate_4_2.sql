-- =============================================================================
-- Set the Mercado Pago terminal commission to 4.2%
-- =============================================================================
-- Forward-only data migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: dbo.commissionTerminals row 1 (provider 'mercadopago') still holds the
-- originally seeded 3.6% (verified 2026-09-30 via GET /all_commissionTerminals).
-- The negotiated rate is 4.2% (confirmed by the owner 2026-09-30). The data
-- fix for this lived at the end of sql/sp_commissionTerminals.sql, but that
-- file was never re-run in full (see 2026-09-30_redeploy_commissionTerminals_sps.sql
-- for why), so the fix never landed.
--
-- SCOPE: one catalog row. No backend code or SP computes commissions from
-- this value today (only the commissionTerminals CRUD reads it), so past
-- income rows are not recalculated.
-- Idempotent: targets the row by id + provider; re-running is a no-op
-- beyond refreshing updatedAt, and it only fires while the rate differs.
-- =============================================================================

UPDATE [dbo].[commissionTerminals]
   SET commissionRatePct = 4.200,
       updatedAt         = GETDATE()
 WHERE commissionTerminalId = 1
   AND provider            = 'mercadopago'
   AND commissionRatePct  <> 4.200;

SELECT commissionTerminalId, provider, commissionRatePct, updatedAt
  FROM [dbo].[commissionTerminals]
 WHERE commissionTerminalId = 1;
GO
