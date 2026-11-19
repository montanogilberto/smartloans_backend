-- ============================================================================
-- RFC-014 phase 1 — loan transaction tickets: delivery policy for the funding
-- events (POSVending docs/rfcs/RFC-014-loan-transaction-tickets.md).
--
-- notificationDispatches has an FK to notificationDispatch_policy
-- (FK_notificationDispatches_policy): without these rows every funding ticket
-- is refused with 400 "No notificationDispatch_policy row for eventName".
-- One eventName per recipient because the dispatcher's idempotency key
-- (companyId, sourceType, sourceId, eventName) has no recipient (RFC-014 P4).
--
-- Channels: WhatsApp (approved Utility template comprobante_listo) -> SMS.
-- No push here: push is the core channel (modules/loanPush.py) and the ticket
-- is only dispatched to parties WITHOUT the app (loanTickets._has_app).
-- Data only: no tables, columns or procedures change. Idempotent (re-runnable).
--
-- BEFORE APPLYING (the local .env may point at the PRODUCTION database):
--   1. Check the backend startup banner: [appEnv][startup] APP_ENV=... DB=...
--   2. Apply in DEV first, then QA, then PROD (development -> qa -> main).
--   3. Set LOAN_TICKET_LINK_SECRET in each environment's App Service settings
--      (a different long random value per environment). Without it the tickets
--      still go out, without the /comprobante link.
-- ============================================================================

IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'funding_declared_lender')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('funding_declared_lender', '["whatsapp","sms"]', 1);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'funding_declared_borrower')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('funding_declared_borrower', '["whatsapp","sms"]', 1);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'funding_confirmed_lender')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('funding_confirmed_lender', '["whatsapp","sms"]', 1);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'funding_confirmed_borrower')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('funding_confirmed_borrower', '["whatsapp","sms"]', 1);
GO

-- Check: 4 rows.
SELECT eventName, channel_list_json, allow_sms_fallback
FROM dbo.notificationDispatch_policy
WHERE eventName IN ('funding_declared_lender', 'funding_declared_borrower',
                    'funding_confirmed_lender', 'funding_confirmed_borrower');
GO
