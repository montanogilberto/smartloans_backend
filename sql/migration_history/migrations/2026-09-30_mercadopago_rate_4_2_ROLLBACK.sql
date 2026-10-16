-- ROLLBACK for 2026-09-30_mercadopago_rate_4_2.sql
-- Restores the previously seeded 3.6% on the Mercado Pago terminal.

UPDATE [dbo].[commissionTerminals]
   SET commissionRatePct = 3.600,
       updatedAt         = GETDATE()
 WHERE commissionTerminalId = 1
   AND provider            = 'mercadopago';
GO
