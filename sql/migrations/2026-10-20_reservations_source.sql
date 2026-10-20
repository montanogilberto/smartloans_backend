-- ============================================================
-- 2026-10-20: dbo.reservations.source — where a booking came from.
--
-- The Agent Performance dashboard counts WhatsApp conversations that ended in
-- a booking; without this column a WhatsApp booking can't be told apart from
-- a kiosk one. Values: 'kiosk' | 'whatsapp'. Rows created before this
-- migration stay NULL (unknown) — no backfill, they are not assumed kiosk.
--
-- Writers: modules/reservations.py (kiosk route, always 'kiosk') and
-- modules/whatsappReservations.py (_book, 'whatsapp'), both via sp_reservations
-- action 1, which defaults anything else to 'kiosk'.
--
-- Run order: this file, then sql/sp_reservations.sql (it INSERTs the column).
-- Safe to re-run. Rollback: 2026-10-20_reservations_source_ROLLBACK.sql.
-- ============================================================

IF COL_LENGTH('dbo.reservations', 'source') IS NULL
    ALTER TABLE [dbo].[reservations] ADD source NVARCHAR(20) NULL;
GO
