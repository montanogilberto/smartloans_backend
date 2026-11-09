-- Ticket to the client after a saldo top-up (transfer, cash, terminal, card):
-- push -> WhatsApp (template abono_saldo) -> SMS. Data only, no DDL.
-- notificationDispatches has an FK to this table, so this row must exist
-- before the backend that sends eventName 'wallet_topup_credited' is deployed.
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'wallet_topup_credited')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('wallet_topup_credited', '["push","whatsapp","sms"]', 1);
GO
