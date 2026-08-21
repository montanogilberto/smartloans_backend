-- ============================================================
-- sp_arcadeRounds_liveWins — ganancias recientes para el ticker
-- ============================================================
-- ANONIMO A PROPOSITO. El feed NO devuelve clientId ni nombre.
--
-- Esto es una app de PRESTAMOS: publicar "Fulano gano 5,000 fichas" revelaria
-- que un cliente identificable esta jugando, a otros clientes y a quien mire
-- la pantalla. El ticker funciona igual mostrando juego, multiplicador y
-- fichas; la identidad no aporta nada y si crea un problema de privacidad.
--
-- Tampoco sale companyId hacia afuera: se filtra por el de quien consulta.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeRounds_liveWins', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeRounds_liveWins;
GO

CREATE PROCEDURE [dbo].[sp_arcadeRounds_liveWins]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].companyId')
        DECLARE @top       INT = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].top') AS INT), 20)

        IF @top > 50 SET @top = 50

        SELECT ISNULL(
            (SELECT TOP (@top) r.roundId, r.gameKey, g.name AS gameName,
                    r.betAmount, r.payoutAmount, r.multiplier,
                    CONVERT(NVARCHAR, r.settledAt, 127) AS settledAt
             FROM [dbo].[arcadeRounds] r
             JOIN [dbo].[arcadeGames] g ON g.gameKey = r.gameKey
             WHERE r.companyId = @companyId
               AND r.roundStatus = 'settled'
               AND r.payoutAmount > r.betAmount   -- solo ganancias reales
             ORDER BY r.settledAt DESC
             FOR JSON PATH, ROOT('arcadeRounds')),
            '{"arcadeRounds":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
