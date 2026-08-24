-- ============================================================
-- sp_arcadeRounds_void — anula una ronda y DEVUELVE la apuesta
-- ============================================================
-- Existe por un fallo real: sp_arcadeRounds_open cobra la apuesta y abre la
-- ronda, y si el codigo revienta ANTES de liquidar, la ronda queda abierta
-- para siempre con las fichas ya cobradas.
--
-- En los juegos por turnos el jugador puede cerrarla jugando. En los
-- INSTANTANEOS (volado, dados, ruleta, raspadito) no hay accion que ofrecerle:
-- la ronda queda atorada y sp_arcadeRounds_open le rechaza toda apuesta futura
-- de ese juego con round_in_progress. El jugador queda encerrado fuera.
--
-- Anular es la salida honesta: se devuelve exactamente lo cobrado y la ronda
-- se marca 'voided'. NUNCA se usa para deshacer un resultado que no gusto —
-- solo cuando la ronda nunca llego a jugarse.
--
-- Idempotente: solo toca rondas 'open'.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeRounds_void', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeRounds_void;
GO

CREATE PROCEDURE [dbo].[sp_arcadeRounds_void]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @roundId INT           = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].roundId')
        DECLARE @reason  NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].reason')

        DECLARE @companyId INT, @clientId INT, @bet INT, @gameKey NVARCHAR(40)
        DECLARE @walletId INT, @balance INT

        BEGIN TRANSACTION
            SELECT @companyId = companyId, @clientId = clientId,
                   @bet = betAmount, @gameKey = gameKey
            FROM [dbo].[arcadeRounds] WITH (UPDLOCK, HOLDLOCK)
            WHERE roundId = @roundId AND roundStatus = 'open'

            IF @companyId IS NULL
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"status":"not_open","roundId":' + CAST(@roundId AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            SELECT @walletId = walletId, @balance = coinBalance
            FROM [dbo].[arcadeWallets] WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND clientId = @clientId

            SET @balance = @balance + @bet

            UPDATE [dbo].[arcadeWallets]
            SET coinBalance = @balance,
                -- Se descuenta de lo apostado: la ronda no ocurrio, y dejarlo
                -- inflaria el denominador del RTP del jugador.
                lifetimeWagered = CASE WHEN lifetimeWagered >= @bet
                                       THEN lifetimeWagered - @bet ELSE 0 END,
                updated_at = GETUTCDATE()
            WHERE walletId = @walletId

            INSERT INTO [dbo].[arcadeTransactions]
                (companyId, clientId, walletId, roundId, txType, amount, balanceAfter, description)
            VALUES
                (@companyId, @clientId, @walletId, @roundId, 'refund', @bet, @balance,
                 ISNULL(@reason, 'Ronda anulada en ' + @gameKey))

            UPDATE [dbo].[arcadeRounds]
            SET roundStatus = 'voided', outcome = 'void',
                settledAt = GETUTCDATE(), updated_at = GETUTCDATE()
            WHERE roundId = @roundId
        COMMIT TRANSACTION

        SELECT '{"status":"voided","roundId":' + CAST(@roundId AS NVARCHAR) +
               ',"refunded":' + CAST(@bet AS NVARCHAR) +
               ',"coinBalance":' + CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
