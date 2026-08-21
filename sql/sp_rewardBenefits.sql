-- ============================================================
-- rewardBenefits — los puntos VALEN algo en el préstamo
-- ============================================================
-- Esta es la moneda que SI puede tener valor, y la razon importa:
--
--   fichas de arcade  -> se GANAN por azar  -> darles valor = premio,
--                        y premio + apuesta = permiso SEGOB.
--   puntos de premio  -> se GANAN por conducta (pagar a tiempo, completar
--                        KYC, referir) -> no hay azar, no hay premio.
--
-- REGLA QUE NO SE ROMPE: las fichas NUNCA se convierten en puntos. Ese puente
-- convertiria una ganancia de azar en valor economico y volveriamos a estar
-- del lado que necesita permiso. No existe SP, ruta ni columna que lo permita,
-- y no debe agregarse.
--
-- El incentivo ademas apunta al lado correcto: pagar a tiempo abarata el
-- credito. Lo contrario —que jugar mejorara el credito— empujaria a un cliente
-- endeudado a apostar para salir del hoyo, que es exactamente el dano que este
-- diseno evita.
-- ============================================================

-- ── Catalogo de beneficios ──────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'rewardBenefits')
CREATE TABLE [dbo].[rewardBenefits] (
    benefitId    INT IDENTITY PRIMARY KEY,
    companyId    INT            NOT NULL,
    benefitKey   NVARCHAR(40)   NOT NULL,
    name         NVARCHAR(80)   NOT NULL,
    description  NVARCHAR(200)  NULL,
    -- fee_discount_pct = % sobre la comision de apertura
    -- rate_discount_bps = puntos base menos de tasa anual
    benefitType  NVARCHAR(30)   NOT NULL,
    value        DECIMAL(10,2)  NOT NULL,
    pointsCost   INT            NOT NULL,
    isActive     NVARCHAR(1)    NOT NULL DEFAULT '1',
    sortOrder    INT            NOT NULL DEFAULT 0,
    created_At   DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at   DATETIME2      NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UX_rewardBenefits_key')
    CREATE UNIQUE INDEX UX_rewardBenefits_key ON [dbo].[rewardBenefits] (companyId, benefitKey);
GO

MERGE [dbo].[rewardBenefits] AS t
USING (VALUES
    (1008, 'fee_5',      'Comisión -5%',    'Cinco por ciento menos de comisión de apertura', 'fee_discount_pct',    5.00,   500, 1),
    (1008, 'fee_10',     'Comisión -10%',   'Diez por ciento menos de comisión de apertura',  'fee_discount_pct',   10.00,   900, 2),
    (1008, 'rate_25bps', 'Tasa -0.25%',     'Cuarto de punto menos en la tasa anual',         'rate_discount_bps',  25.00,  1500, 3),
    (1008, 'rate_50bps', 'Tasa -0.50%',     'Medio punto menos en la tasa anual',             'rate_discount_bps',  50.00,  2800, 4)
) AS s (companyId, benefitKey, name, description, benefitType, value, pointsCost, sortOrder)
ON t.companyId = s.companyId AND t.benefitKey = s.benefitKey
WHEN NOT MATCHED THEN
    INSERT (companyId, benefitKey, name, description, benefitType, value, pointsCost, sortOrder)
    VALUES (s.companyId, s.benefitKey, s.name, s.description, s.benefitType, s.value, s.pointsCost, s.sortOrder);
GO

-- ── Beneficios canjeados por prestamo ───────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanRewardBenefits')
CREATE TABLE [dbo].[loanRewardBenefits] (
    id           INT IDENTITY PRIMARY KEY,
    companyId    INT            NOT NULL,
    clientId     INT            NOT NULL,
    -- Nulo mientras el prestamo no existe: el beneficio se aparta al solicitar
    -- y se amarra al prestamo cuando se crea.
    loanId       INT            NULL,
    benefitKey   NVARCHAR(40)   NOT NULL,
    benefitType  NVARCHAR(30)   NOT NULL,
    value        DECIMAL(10,2)  NOT NULL,
    pointsSpent  INT            NOT NULL,
    rewardTxId   INT            NULL,
    status       NVARCHAR(20)   NOT NULL DEFAULT 'reserved',  -- reserved | applied | released
    created_At   DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at   DATETIME2      NULL
)
GO

-- Un solo beneficio activo por cliente sin prestamo asignado: sin esto se
-- podrian apartar cinco descuentos y aplicarlos todos al mismo credito.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UX_loanRewardBenefits_pending')
    CREATE UNIQUE INDEX UX_loanRewardBenefits_pending
        ON [dbo].[loanRewardBenefits] (companyId, clientId)
        WHERE loanId IS NULL AND status = 'reserved';
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_loanRewardBenefits_loan')
    CREATE INDEX IX_loanRewardBenefits_loan ON [dbo].[loanRewardBenefits] (companyId, loanId);
GO

-- ── Reglas de conducta que otorgan puntos ───────────────────
-- pointsPerUnit se lee como "puntos por cada $1 MXN pagado a tiempo".
-- 0.10 => una cuota de $1,000 da 100 puntos; cinco cuotas puntuales alcanzan
-- para el primer descuento de comision.
MERGE [dbo].[rewardRules] AS t
USING (VALUES
    (1008, 'Pago puntual de cuota', 'loan_on_time', 0.10, NULL, 500),
    (1008, 'Expediente completo',   'kyc_complete', 1.00, NULL, 250),
    (1008, 'Referido activado',     'referral',     1.00, NULL, 300)
) AS s (companyId, ruleName, ruleType, pointsPerUnit, minAmount, maxPointsPerTx)
ON t.companyId = s.companyId AND t.ruleName = s.ruleName
WHEN NOT MATCHED THEN
    INSERT (companyId, ruleName, ruleType, pointsPerUnit, minAmount, maxPointsPerTx, isActive)
    VALUES (s.companyId, s.ruleName, s.ruleType, s.pointsPerUnit, s.minAmount, s.maxPointsPerTx, 1);
GO

-- ============================================================
-- sp_rewards_earnOnce — otorga puntos UNA sola vez por referencia
-- ============================================================
-- El 'earn' que ya existia no es idempotente. Una cuota se marca pagada desde
-- tres sitios distintos (SPEI manual, cobro automatico, Stripe) y cualquiera
-- puede reintentar: sin este candado la misma cuota regalaria puntos varias
-- veces. La referencia (p.ej. 'cuota:1234') es la llave.
-- ============================================================
IF OBJECT_ID('dbo.sp_rewards_earnOnce', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_rewards_earnOnce;
GO

CREATE PROCEDURE [dbo].[sp_rewards_earnOnce]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].companyId')
        DECLARE @clientId  INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].clientId')
        DECLARE @points    INT           = TRY_CAST(JSON_VALUE(@pjsonfile, '$.rewards[0].points') AS INT)
        DECLARE @refId     NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.rewards[0].referenceId')
        DECLARE @desc      NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.rewards[0].description')
        DECLARE @ruleId    INT           = TRY_CAST(JSON_VALUE(@pjsonfile, '$.rewards[0].ruleId') AS INT)
        DECLARE @balance INT

        IF @companyId IS NULL OR @clientId IS NULL OR @refId IS NULL OR @points IS NULL
        BEGIN
            SELECT '{"error":"missing_fields"}' AS [jsonResult]
            RETURN
        END
        IF @points <= 0
        BEGIN
            SELECT '{"status":"skipped","reason":"no_points"}' AS [jsonResult]
            RETURN
        END

        BEGIN TRANSACTION
            IF EXISTS (SELECT 1 FROM [dbo].[rewardTransactions] WITH (UPDLOCK, HOLDLOCK)
                       WHERE companyId = @companyId AND clientId = @clientId
                         AND txType = 'earn' AND referenceId = @refId)
            BEGIN
                SELECT @balance = balance FROM [dbo].[rewardPoints]
                WHERE companyId = @companyId AND clientId = @clientId
                ROLLBACK TRANSACTION
                SELECT '{"status":"already_earned","balance":' + CAST(ISNULL(@balance,0) AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            IF NOT EXISTS (SELECT 1 FROM [dbo].[rewardPoints]
                           WHERE companyId = @companyId AND clientId = @clientId)
                INSERT INTO [dbo].[rewardPoints] (companyId, clientId, balance) VALUES (@companyId, @clientId, 0)

            UPDATE [dbo].[rewardPoints]
            SET balance = balance + @points,
                lifetimeEarned = lifetimeEarned + @points,
                lastActivity = GETUTCDATE(), updated_at = GETUTCDATE()
            WHERE companyId = @companyId AND clientId = @clientId

            SELECT @balance = balance FROM [dbo].[rewardPoints]
            WHERE companyId = @companyId AND clientId = @clientId

            INSERT INTO [dbo].[rewardTransactions]
                (companyId, clientId, ruleId, txType, points, balanceAfter, referenceId, description)
            VALUES (@companyId, @clientId, @ruleId, 'earn', @points, @balance, @refId, @desc)
        COMMIT TRANSACTION

        SELECT '{"status":"earned","points":' + CAST(@points AS NVARCHAR) +
               ',"balance":' + CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_rewardBenefits_all — catalogo + si al cliente le alcanza
-- ============================================================
IF OBJECT_ID('dbo.sp_rewardBenefits_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_rewardBenefits_all;
GO

CREATE PROCEDURE [dbo].[sp_rewardBenefits_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].clientId')
        DECLARE @balance   INT

        SELECT @balance = ISNULL(balance, 0) FROM [dbo].[rewardPoints]
        WHERE companyId = @companyId AND clientId = @clientId

        SELECT ISNULL(
            (SELECT benefitKey, name, description, benefitType, value, pointsCost,
                    CAST(CASE WHEN ISNULL(@balance,0) >= pointsCost THEN 1 ELSE 0 END AS BIT) AS affordable
             FROM [dbo].[rewardBenefits]
             WHERE companyId = @companyId AND isActive = '1'
             ORDER BY sortOrder
             FOR JSON PATH, ROOT('rewardBenefits')),
            '{"rewardBenefits":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_rewardBenefits_reserve — canjea puntos y aparta el beneficio
-- ============================================================
-- Descontar puntos y apartar el beneficio ocurren en UNA transaccion: si se
-- separaran, un fallo entre ambos dejaria al cliente sin puntos y sin
-- descuento, que es la peor de las dos mitades.
-- ============================================================
IF OBJECT_ID('dbo.sp_rewardBenefits_reserve', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_rewardBenefits_reserve;
GO

CREATE PROCEDURE [dbo].[sp_rewardBenefits_reserve]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].companyId')
        DECLARE @clientId   INT          = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].clientId')
        DECLARE @benefitKey NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].benefitKey')

        DECLARE @type NVARCHAR(30), @value DECIMAL(10,2), @cost INT
        DECLARE @balance INT, @txId INT, @id INT

        SELECT @type = benefitType, @value = value, @cost = pointsCost
        FROM [dbo].[rewardBenefits]
        WHERE companyId = @companyId AND benefitKey = @benefitKey AND isActive = '1'

        IF @type IS NULL
        BEGIN
            SELECT '{"error":"unknown_benefit","message":"Ese beneficio no existe"}' AS [jsonResult]
            RETURN
        END

        BEGIN TRANSACTION
            SELECT @balance = balance FROM [dbo].[rewardPoints] WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND clientId = @clientId

            IF ISNULL(@balance, 0) < @cost
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"insufficient_points","message":"No tienes puntos suficientes","balance":' +
                       CAST(ISNULL(@balance,0) AS NVARCHAR) + ',"pointsCost":' + CAST(@cost AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            IF EXISTS (SELECT 1 FROM [dbo].[loanRewardBenefits] WITH (UPDLOCK, HOLDLOCK)
                       WHERE companyId = @companyId AND clientId = @clientId
                         AND loanId IS NULL AND status = 'reserved')
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"benefit_already_reserved","message":"Ya tienes un beneficio apartado"}' AS [jsonResult]
                RETURN
            END

            SET @balance = @balance - @cost

            UPDATE [dbo].[rewardPoints]
            SET balance = @balance, lifetimeRedeemed = lifetimeRedeemed + @cost,
                lastActivity = GETUTCDATE(), updated_at = GETUTCDATE()
            WHERE companyId = @companyId AND clientId = @clientId

            INSERT INTO [dbo].[rewardTransactions]
                (companyId, clientId, txType, points, balanceAfter, referenceId, description)
            VALUES (@companyId, @clientId, 'redeem', -@cost, @balance,
                    'benefit:' + @benefitKey, 'Beneficio de prestamo: ' + @benefitKey)
            SET @txId = SCOPE_IDENTITY()

            INSERT INTO [dbo].[loanRewardBenefits]
                (companyId, clientId, benefitKey, benefitType, value, pointsSpent, rewardTxId, status)
            VALUES (@companyId, @clientId, @benefitKey, @type, @value, @cost, @txId, 'reserved')
            SET @id = SCOPE_IDENTITY()
        COMMIT TRANSACTION

        SELECT '{"status":"reserved","id":' + CAST(@id AS NVARCHAR) +
               ',"benefitKey":"' + @benefitKey + '","benefitType":"' + @type +
               '","value":' + CAST(@value AS NVARCHAR) +
               ',"pointsSpent":' + CAST(@cost AS NVARCHAR) +
               ',"balance":' + CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_rewardBenefits_bind — amarra el beneficio apartado al prestamo
-- ============================================================
IF OBJECT_ID('dbo.sp_rewardBenefits_bind', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_rewardBenefits_bind;
GO

CREATE PROCEDURE [dbo].[sp_rewardBenefits_bind]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].clientId')
        DECLARE @loanId    INT = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].loanId')

        UPDATE [dbo].[loanRewardBenefits]
        SET loanId = @loanId, status = 'applied', updated_at = GETUTCDATE()
        WHERE companyId = @companyId AND clientId = @clientId
          AND loanId IS NULL AND status = 'reserved'

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT '{"status":"none","message":"El cliente no tenia beneficio apartado"}' AS [jsonResult]
            RETURN
        END

        SELECT (SELECT TOP 1 benefitKey, benefitType, value, pointsSpent, status
                FROM [dbo].[loanRewardBenefits]
                WHERE companyId = @companyId AND loanId = @loanId
                ORDER BY id DESC
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_rewardBenefits_forClient — beneficio apartado / del prestamo
-- ============================================================
IF OBJECT_ID('dbo.sp_rewardBenefits_forClient', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_rewardBenefits_forClient;
GO

CREATE PROCEDURE [dbo].[sp_rewardBenefits_forClient]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].clientId')
        DECLARE @loanId    INT = TRY_CAST(JSON_VALUE(@pjsonfile, '$.rewardBenefits[0].loanId') AS INT)

        SELECT ISNULL(
            (SELECT id, benefitKey, benefitType, value, pointsSpent, status, loanId,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM [dbo].[loanRewardBenefits]
             WHERE companyId = @companyId AND clientId = @clientId
               AND (@loanId IS NULL OR loanId = @loanId)
             ORDER BY id DESC
             FOR JSON PATH, ROOT('loanRewardBenefits')),
            '{"loanRewardBenefits":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
