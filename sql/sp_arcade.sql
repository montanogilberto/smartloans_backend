-- ============================================================
-- arcade — mini-juegos de apuesta con FICHAS VIRTUALES
-- ============================================================
-- FICHAS, NO DINERO. arcadeWallets.coinBalance no tiene ninguna
-- ruta de retiro: no se conecta con walletTransactions, ni con
-- Stripe, ni con SPEI. Es un saldo cerrado y no canjeable, y esa
-- separacion es lo que mantiene al modulo fuera del permiso
-- SEGOB de la Ley Federal de Juegos y Sorteos. Si algun dia se
-- abre el canje, ese puente necesita permiso + geocerca + KYC.
--
-- El servidor es la autoridad: el cliente nunca decide un
-- resultado. La barajada y el calendario de topos se derivan de
-- HMAC-SHA256(serverSeed, clientSeed) en modules/arcade.py y se
-- guardan en arcadeRounds.stateJson; el cliente solo declara
-- acciones ("pido carta", "pegue al topo 3 en 412 ms").
--
-- Juego limpio (provably fair): serverSeedHash se entrega ANTES
-- de jugar y serverSeed se revela AL LIQUIDAR, para que el
-- jugador compruebe SHA256(serverSeed) = serverSeedHash. Cada
-- ronda estrena serverSeed, asi que el nonce es solo contador de
-- auditoria, no entra en la derivacion.
-- ============================================================

-- ── Tabla: arcadeGames (catalogo) ───────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'arcadeGames')
CREATE TABLE [dbo].[arcadeGames] (
    gameId        INT IDENTITY PRIMARY KEY,
    companyId     INT            NOT NULL,
    gameKey       NVARCHAR(40)   NOT NULL,
    name          NVARCHAR(60)   NOT NULL,
    tagline       NVARCHAR(120)  NULL,
    iconName      NVARCHAR(60)   NOT NULL,
    category      NVARCHAR(20)   NOT NULL,   -- cards | reflex | sports | luck
    minBet        INT            NOT NULL DEFAULT 10,
    maxBet        INT            NOT NULL DEFAULT 500,
    rtp           DECIMAL(5,4)   NOT NULL DEFAULT 0.9600,
    maxMultiplier DECIMAL(8,2)   NOT NULL DEFAULT 2.00,
    isActive      NVARCHAR(1)    NOT NULL DEFAULT '1',
    comingSoon    NVARCHAR(1)    NOT NULL DEFAULT '1',
    sortOrder     INT            NOT NULL DEFAULT 0,
    created_At    DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at    DATETIME2      NULL
)
GO

-- gameKey es la llave que usa el frontend y a la que apunta arcadeRounds.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UX_arcadeGames_key')
    CREATE UNIQUE INDEX UX_arcadeGames_key ON [dbo].[arcadeGames] (gameKey);
GO

-- Seed del catalogo (idempotente). Solo blackjack y mole salen jugables;
-- los otros ocho pintan el tile bloqueado con "Proximamente".
--
-- OJO con rtp: es el retorno TEORICO con juego OPTIMO, no el que se mide.
-- El 0.9950 de blackjack es la cifra publicada para estas reglas (6 barajas,
-- crupier se planta en 17, BJ paga 3:2) jugando estrategia basica; un jugador
-- normal saca bastante menos. Se muestra porque es el estandar de la industria,
-- pero NO es una promesa de lo que va a ganar quien juegue mal.
MERGE [dbo].[arcadeGames] AS t
USING (VALUES
    (1008, 'blackjack',   'Blackjack 21',      'Vence al crupier sin pasarte de 21',      'diamondOutline',    'cards',  10, 500, 0.9950,   4.00, '1', '0',  1),
    (1008, 'mole',        'Atrapa al Topo',    'Reflejos: cada topo suma multiplicador',  'bugOutline',        'reflex', 10, 300, 0.9600,   5.00, '1', '0',  2),
    (1008, 'bowling',     'Boliche',           'Chuzas seguidas, premio en escalera',     'discOutline',       'sports', 10, 300, 0.9500,  10.00, '1', '1',  3),
    (1008, 'dice',        'Dados',             'Apuesta a mayor o menor que tu numero',   'diceOutline',       'luck',   10, 500, 0.9700,   9.90, '1', '1',  4),
    (1008, 'coinflip',    'Volado',            'Aguila o sol: doble o nada',              'cashOutline',       'luck',   10, 500, 0.9800,   2.00, '1', '1',  5),
    (1008, 'higherlower', 'Mayor o Menor',     'Adivina la siguiente carta y acumula',    'trendingUpOutline', 'cards',  10, 300, 0.9600,  20.00, '1', '1',  6),
    (1008, 'mines',       'Minas',             'Destapa casillas y retirate a tiempo',    'gridOutline',       'luck',   10, 300, 0.9700,  24.00, '1', '1',  7),
    (1008, 'wheel',       'Ruleta de Premios', 'Gira y cae en tu multiplicador',          'pieChartOutline',   'luck',   10, 250, 0.9600,  50.00, '1', '1',  8),
    (1008, 'scratch',     'Raspadito',         'Raspa tres iguales y cobra',              'ticketOutline',     'luck',   10, 200, 0.9400, 100.00, '1', '1',  9),
    (1008, 'penalty',     'Penales',           'Cobra el penal y vence al portero',       'footballOutline',   'sports', 10, 300, 0.9500,   3.00, '1', '1', 10)
) AS s (companyId, gameKey, name, tagline, iconName, category, minBet, maxBet, rtp, maxMultiplier, isActive, comingSoon, sortOrder)
ON t.gameKey = s.gameKey
WHEN NOT MATCHED THEN
    INSERT (companyId, gameKey, name, tagline, iconName, category, minBet, maxBet, rtp, maxMultiplier, isActive, comingSoon, sortOrder)
    VALUES (s.companyId, s.gameKey, s.name, s.tagline, s.iconName, s.category, s.minBet, s.maxBet, s.rtp, s.maxMultiplier, s.isActive, s.comingSoon, s.sortOrder);
GO

-- ── Tabla: arcadeWallets ────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'arcadeWallets')
CREATE TABLE [dbo].[arcadeWallets] (
    walletId         INT IDENTITY PRIMARY KEY,
    companyId        INT         NOT NULL,
    clientId         INT         NOT NULL,
    coinBalance      INT         NOT NULL DEFAULT 0,
    lifetimeWagered  INT         NOT NULL DEFAULT 0,
    lifetimeWon      INT         NOT NULL DEFAULT 0,
    lifetimeRounds   INT         NOT NULL DEFAULT 0,
    nextNonce        INT         NOT NULL DEFAULT 1,
    dailyWagerLimit  INT         NOT NULL DEFAULT 5000,  -- 0 = sin tope
    lastDailyBonusAt DATETIME2   NULL,
    isLocked         NVARCHAR(1) NOT NULL DEFAULT '0',
    created_At       DATETIME2   NOT NULL DEFAULT GETUTCDATE(),
    updated_at       DATETIME2   NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UX_arcadeWallets_client')
    CREATE UNIQUE INDEX UX_arcadeWallets_client ON [dbo].[arcadeWallets] (companyId, clientId);
GO

-- ── Tabla: arcadeRounds ─────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'arcadeRounds')
CREATE TABLE [dbo].[arcadeRounds] (
    roundId        INT IDENTITY PRIMARY KEY,
    companyId      INT            NOT NULL,
    clientId       INT            NOT NULL,
    gameKey        NVARCHAR(40)   NOT NULL,
    betAmount      INT            NOT NULL,
    payoutAmount   INT            NOT NULL DEFAULT 0,
    multiplier     DECIMAL(8,2)   NOT NULL DEFAULT 0,
    outcome        NVARCHAR(20)   NULL,       -- win | lose | push | blackjack
    roundStatus    NVARCHAR(20)   NOT NULL DEFAULT 'open',  -- open | settled | voided
    serverSeedHash NVARCHAR(64)   NOT NULL,
    serverSeed     NVARCHAR(64)   NULL,       -- se revela al liquidar
    clientSeed     NVARCHAR(64)   NOT NULL,
    nonce          INT            NOT NULL,
    stateJson      NVARCHAR(MAX)  NULL,       -- estado autoritativo del servidor
    resultJson     NVARCHAR(MAX)  NULL,
    settledAt      DATETIME2      NULL,
    created_At     DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at     DATETIME2      NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_arcadeRounds_client_created')
    CREATE INDEX IX_arcadeRounds_client_created
        ON [dbo].[arcadeRounds] (companyId, clientId, created_At DESC) INCLUDE (gameKey, roundStatus);
GO
-- Sirve al candado "una sola ronda abierta por juego" de sp_arcadeRounds_open.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_arcadeRounds_open')
    CREATE INDEX IX_arcadeRounds_open
        ON [dbo].[arcadeRounds] (companyId, clientId, gameKey, roundStatus);
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_arcadeRounds_game')
    ALTER TABLE [dbo].[arcadeRounds]
        ADD CONSTRAINT FK_arcadeRounds_game
        FOREIGN KEY (gameKey) REFERENCES [dbo].[arcadeGames] (gameKey);
GO

-- ── Tabla: arcadeTransactions (libro mayor de fichas) ───────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'arcadeTransactions')
CREATE TABLE [dbo].[arcadeTransactions] (
    transactionId INT IDENTITY PRIMARY KEY,
    companyId     INT            NOT NULL,
    clientId      INT            NOT NULL,
    walletId      INT            NOT NULL,
    roundId       INT            NULL,
    txType        NVARCHAR(20)   NOT NULL,   -- bet_debit | payout_credit | welcome_grant | daily_bonus | refund | adjustment
    amount        INT            NOT NULL,   -- con signo: negativo debita
    balanceAfter  INT            NOT NULL,
    description   NVARCHAR(200)  NULL,
    created_At    DATETIME2      NOT NULL DEFAULT GETUTCDATE()
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_arcadeTransactions_client')
    CREATE INDEX IX_arcadeTransactions_client
        ON [dbo].[arcadeTransactions] (companyId, clientId, created_At DESC);
GO

-- ============================================================
-- sp_arcadeGames_all — catalogo para el dashboard
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeGames_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeGames_all;
GO

CREATE PROCEDURE [dbo].[sp_arcadeGames_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @isActive NVARCHAR(1) = JSON_VALUE(@pjsonfile, '$.arcadeGames[0].isActive')

        SELECT ISNULL(
            (SELECT gameKey, name, tagline, iconName, category,
                    minBet, maxBet, rtp, maxMultiplier, isActive, comingSoon, sortOrder
             FROM [dbo].[arcadeGames]
             WHERE (@isActive IS NULL OR isActive = @isActive)
             ORDER BY sortOrder
             FOR JSON PATH, ROOT('arcadeGames')),
            '{"arcadeGames":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeWallets_one — lee el monedero, creandolo si no existe
-- ============================================================
-- Crear al leer evita una pantalla de "activa tu monedero": el
-- jugador entra al arcade y ya tiene sus fichas de bienvenida.
-- El INSERT va bajo transaccion + reintento por UX_arcadeWallets_client
-- porque dos peticiones simultaneas del mismo cliente (dashboard +
-- push de refresco) chocarian en el unique index.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeWallets_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeWallets_one;
GO

CREATE PROCEDURE [dbo].[sp_arcadeWallets_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.arcadeWallets[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.arcadeWallets[0].clientId')
        DECLARE @welcome   INT = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeWallets[0].welcomeGrant') AS INT), 1000)
        DECLARE @walletId  INT

        IF @companyId IS NULL OR @clientId IS NULL
        BEGIN
            SELECT '{"error":"missing_identity","message":"companyId y clientId son obligatorios"}' AS [jsonResult]
            RETURN
        END

        SELECT @walletId = walletId FROM [dbo].[arcadeWallets]
        WHERE companyId = @companyId AND clientId = @clientId

        IF @walletId IS NULL
        BEGIN
            BEGIN TRANSACTION
                INSERT INTO [dbo].[arcadeWallets] (companyId, clientId, coinBalance)
                VALUES (@companyId, @clientId, @welcome)
                SET @walletId = SCOPE_IDENTITY()

                INSERT INTO [dbo].[arcadeTransactions]
                    (companyId, clientId, walletId, txType, amount, balanceAfter, description)
                VALUES
                    (@companyId, @clientId, @walletId, 'welcome_grant', @welcome, @welcome, 'Fichas de bienvenida')
            COMMIT TRANSACTION
        END

        SELECT ISNULL(
            (SELECT TOP 1 walletId, companyId, clientId, coinBalance,
                    lifetimeWagered, lifetimeWon, lifetimeRounds,
                    dailyWagerLimit, isLocked,
                    CONVERT(NVARCHAR, lastDailyBonusAt, 127) AS lastDailyBonusAt,
                    -- Apostado HOY: el frontend pinta cuanto queda del tope diario.
                    ISNULL((SELECT -SUM(t.amount) FROM [dbo].[arcadeTransactions] t
                            WHERE t.walletId = w.walletId AND t.txType = 'bet_debit'
                              AND t.created_At >= CAST(GETUTCDATE() AS DATE)), 0) AS wageredToday
             FROM [dbo].[arcadeWallets] w
             WHERE w.walletId = @walletId
             FOR JSON PATH, ROOT('arcadeWallets')),
            '{"arcadeWallets":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeWallets_dailyBonus — bono diario, una vez cada 24 h
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeWallets_dailyBonus', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeWallets_dailyBonus;
GO

CREATE PROCEDURE [dbo].[sp_arcadeWallets_dailyBonus]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.arcadeWallets[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.arcadeWallets[0].clientId')
        DECLARE @amount    INT = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeWallets[0].amount') AS INT), 250)
        DECLARE @walletId INT, @balance INT, @last DATETIME2

        BEGIN TRANSACTION
            -- UPDLOCK/HOLDLOCK: dos toques al boton no deben acreditar dos bonos.
            SELECT @walletId = walletId, @balance = coinBalance, @last = lastDailyBonusAt
            FROM [dbo].[arcadeWallets] WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND clientId = @clientId

            IF @walletId IS NULL
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"no_wallet","message":"El monedero no existe todavia"}' AS [jsonResult]
                RETURN
            END

            IF @last IS NOT NULL AND DATEDIFF(HOUR, @last, GETUTCDATE()) < 24
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"granted":false,"reason":"too_soon","coinBalance":' + CAST(@balance AS NVARCHAR) +
                       ',"nextBonusAt":"' + CONVERT(NVARCHAR, DATEADD(HOUR, 24, @last), 127) + '"}' AS [jsonResult]
                RETURN
            END

            SET @balance = @balance + @amount

            UPDATE [dbo].[arcadeWallets]
            SET coinBalance = @balance, lastDailyBonusAt = GETUTCDATE(), updated_at = GETUTCDATE()
            WHERE walletId = @walletId

            INSERT INTO [dbo].[arcadeTransactions]
                (companyId, clientId, walletId, txType, amount, balanceAfter, description)
            VALUES
                (@companyId, @clientId, @walletId, 'daily_bonus', @amount, @balance, 'Bono diario de fichas')
        COMMIT TRANSACTION

        SELECT '{"granted":true,"amount":' + CAST(@amount AS NVARCHAR) +
               ',"coinBalance":' + CAST(@balance AS NVARCHAR) +
               ',"nextBonusAt":"' + CONVERT(NVARCHAR, DATEADD(HOUR, 24, GETUTCDATE()), 127) + '"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeRounds_open — abre la ronda y debita la apuesta
-- ============================================================
-- Todo el gasto de fichas pasa por aqui, en UNA transaccion con
-- UPDLOCK sobre el renglon del monedero. Sin ese candado, dos
-- apuestas simultaneas leerian el mismo saldo y ambas pasarian
-- la validacion — el clasico doble gasto.
--
-- El servidor NO recibe el resultado: recibe la semilla y el
-- estado inicial ya derivado en modules/arcade.py (baraja
-- barajada / calendario de topos). Como cada ronda estrena
-- serverSeed, el estado se puede calcular antes del INSERT y la
-- apertura sigue siendo un solo viaje.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeRounds_open', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeRounds_open;
GO

CREATE PROCEDURE [dbo].[sp_arcadeRounds_open]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT          = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].companyId')
        DECLARE @clientId  INT          = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].clientId')
        DECLARE @gameKey   NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].gameKey')
        DECLARE @betAmount INT          = TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].betAmount') AS INT)
        DECLARE @seedHash  NVARCHAR(64) = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].serverSeedHash')
        DECLARE @seed      NVARCHAR(64) = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].serverSeed')
        DECLARE @clientSeed NVARCHAR(64) = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].clientSeed')
        DECLARE @stateJson NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.arcadeRounds[0].state')

        DECLARE @walletId INT, @balance INT, @locked NVARCHAR(1), @limit INT, @nonce INT
        DECLARE @minBet INT, @maxBet INT, @active NVARCHAR(1), @soon NVARCHAR(1)
        DECLARE @wageredToday INT, @roundId INT

        IF @betAmount IS NULL OR @betAmount <= 0
        BEGIN
            SELECT '{"error":"bad_bet","message":"La apuesta debe ser mayor a cero"}' AS [jsonResult]
            RETURN
        END

        SELECT @minBet = minBet, @maxBet = maxBet, @active = isActive, @soon = comingSoon
        FROM [dbo].[arcadeGames] WHERE gameKey = @gameKey

        IF @minBet IS NULL
        BEGIN
            SELECT '{"error":"unknown_game","message":"Ese juego no existe"}' AS [jsonResult]
            RETURN
        END
        IF @active <> '1' OR @soon = '1'
        BEGIN
            SELECT '{"error":"game_unavailable","message":"Ese juego todavia no esta disponible"}' AS [jsonResult]
            RETURN
        END
        IF @betAmount < @minBet OR @betAmount > @maxBet
        BEGIN
            SELECT '{"error":"bet_out_of_range","message":"Apuesta fuera de los limites del juego","minBet":' +
                   CAST(@minBet AS NVARCHAR) + ',"maxBet":' + CAST(@maxBet AS NVARCHAR) + '}' AS [jsonResult]
            RETURN
        END

        BEGIN TRANSACTION
            SELECT @walletId = walletId, @balance = coinBalance, @locked = isLocked,
                   @limit = dailyWagerLimit, @nonce = nextNonce
            FROM [dbo].[arcadeWallets] WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND clientId = @clientId

            IF @walletId IS NULL
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"no_wallet","message":"El monedero no existe todavia"}' AS [jsonResult]
                RETURN
            END
            IF @locked = '1'
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"wallet_locked","message":"Tu monedero esta bloqueado"}' AS [jsonResult]
                RETURN
            END
            IF @balance < @betAmount
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"insufficient_coins","message":"No tienes fichas suficientes","coinBalance":' +
                       CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            -- Tope diario de juego responsable (0 = sin tope).
            IF @limit > 0
            BEGIN
                SELECT @wageredToday = ISNULL(-SUM(amount), 0)
                FROM [dbo].[arcadeTransactions]
                WHERE walletId = @walletId AND txType = 'bet_debit'
                  AND created_At >= CAST(GETUTCDATE() AS DATE)

                IF @wageredToday + @betAmount > @limit
                BEGIN
                    ROLLBACK TRANSACTION
                    SELECT '{"error":"daily_limit","message":"Alcanzaste tu limite diario de juego","dailyWagerLimit":' +
                           CAST(@limit AS NVARCHAR) + ',"wageredToday":' + CAST(@wageredToday AS NVARCHAR) + '}' AS [jsonResult]
                    RETURN
                END
            END

            -- Una sola ronda abierta por juego: si no, el jugador podria dejar
            -- una mano mala colgada y abrir otra hasta que salga una buena.
            IF EXISTS (SELECT 1 FROM [dbo].[arcadeRounds]
                       WHERE companyId = @companyId AND clientId = @clientId
                         AND gameKey = @gameKey AND roundStatus = 'open')
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"round_in_progress","message":"Ya tienes una ronda sin terminar en este juego"}' AS [jsonResult]
                RETURN
            END

            SET @balance = @balance - @betAmount

            INSERT INTO [dbo].[arcadeRounds]
                (companyId, clientId, gameKey, betAmount, roundStatus,
                 serverSeedHash, serverSeed, clientSeed, nonce, stateJson)
            VALUES
                (@companyId, @clientId, @gameKey, @betAmount, 'open',
                 @seedHash, @seed, @clientSeed, @nonce, @stateJson)
            SET @roundId = SCOPE_IDENTITY()

            UPDATE [dbo].[arcadeWallets]
            SET coinBalance     = @balance,
                lifetimeWagered = lifetimeWagered + @betAmount,
                nextNonce       = nextNonce + 1,
                updated_at      = GETUTCDATE()
            WHERE walletId = @walletId

            INSERT INTO [dbo].[arcadeTransactions]
                (companyId, clientId, walletId, roundId, txType, amount, balanceAfter, description)
            VALUES
                (@companyId, @clientId, @walletId, @roundId, 'bet_debit', -@betAmount, @balance,
                 'Apuesta en ' + @gameKey)
        COMMIT TRANSACTION

        SELECT '{"roundId":' + CAST(@roundId AS NVARCHAR) +
               ',"nonce":' + CAST(@nonce AS NVARCHAR) +
               ',"serverSeedHash":"' + @seedHash + '"' +
               ',"coinBalance":' + CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeRounds_state — guarda el estado de una ronda abierta
-- ============================================================
-- Para juegos por turnos (blackjack pide carta): el estado vive
-- en el servidor entre accion y accion. Solo toca rondas 'open'.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeRounds_state', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeRounds_state;
GO

CREATE PROCEDURE [dbo].[sp_arcadeRounds_state]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @roundId   INT           = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].roundId')
        DECLARE @clientId  INT           = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].clientId')
        DECLARE @stateJson NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.arcadeRounds[0].state')

        UPDATE [dbo].[arcadeRounds]
        SET stateJson = @stateJson, updated_at = GETUTCDATE()
        WHERE roundId = @roundId AND clientId = @clientId AND roundStatus = 'open'

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT '{"error":"round_not_open","message":"Esa ronda ya no esta abierta"}' AS [jsonResult]
            RETURN
        END

        SELECT '{"message":"ok","roundId":' + CAST(@roundId AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeRounds_double — cobra la SEGUNDA apuesta al doblar
-- ============================================================
-- Doblar duplica la exposicion, asi que tiene que duplicar el cobro. Sin esta
-- SP el jugador arriesgaba una apuesta y cobraba como si hubiera arriesgado
-- dos: doblar siempre saldria a favor y la ventaja de la casa se invertia.
--
-- No se revalida el tope diario aqui a proposito: la mano ya esta repartida y
-- cortarla a la mitad dejaria al jugador sin poder cerrarla.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeRounds_double', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeRounds_double;
GO

CREATE PROCEDURE [dbo].[sp_arcadeRounds_double]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @roundId  INT = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].roundId')
        DECLARE @clientId INT = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].clientId')
        DECLARE @companyId INT, @bet INT, @walletId INT, @balance INT, @gameKey NVARCHAR(40)

        BEGIN TRANSACTION
            SELECT @companyId = companyId, @bet = betAmount, @gameKey = gameKey
            FROM [dbo].[arcadeRounds] WITH (UPDLOCK, HOLDLOCK)
            WHERE roundId = @roundId AND clientId = @clientId AND roundStatus = 'open'

            IF @companyId IS NULL
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"round_not_open","message":"Esa ronda ya no esta abierta"}' AS [jsonResult]
                RETURN
            END

            SELECT @walletId = walletId, @balance = coinBalance
            FROM [dbo].[arcadeWallets] WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND clientId = @clientId

            IF @balance < @bet
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"insufficient_coins","message":"No te alcanza para doblar","coinBalance":' +
                       CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            SET @balance = @balance - @bet

            UPDATE [dbo].[arcadeWallets]
            SET coinBalance     = @balance,
                lifetimeWagered = lifetimeWagered + @bet,
                updated_at      = GETUTCDATE()
            WHERE walletId = @walletId

            INSERT INTO [dbo].[arcadeTransactions]
                (companyId, clientId, walletId, roundId, txType, amount, balanceAfter, description)
            VALUES
                (@companyId, @clientId, @walletId, @roundId, 'bet_debit', -@bet, @balance,
                 'Dobla en ' + @gameKey)
        COMMIT TRANSACTION

        SELECT '{"message":"doubled","roundId":' + CAST(@roundId AS NVARCHAR) +
               ',"coinBalance":' + CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeRounds_settle — liquida la ronda y acredita el pago
-- ============================================================
-- Idempotente por construccion: el UPDATE exige roundStatus='open',
-- asi que un reintento del cliente (red intermitente) no paga dos
-- veces. @payoutAmount es el RETORNO TOTAL — la apuesta ya se
-- debito al abrir, asi que ganar 1:1 paga 2x, un push paga 1x y
-- perder paga 0.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeRounds_settle', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeRounds_settle;
GO

CREATE PROCEDURE [dbo].[sp_arcadeRounds_settle]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @roundId    INT           = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].roundId')
        DECLARE @clientId   INT           = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].clientId')
        DECLARE @payout     INT           = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].payoutAmount') AS INT), 0)
        DECLARE @outcome    NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].outcome')
        DECLARE @resultJson NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.arcadeRounds[0].result')
        DECLARE @stateJson  NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.arcadeRounds[0].state')

        DECLARE @companyId INT, @walletId INT, @balance INT, @bet INT, @gameKey NVARCHAR(40)

        BEGIN TRANSACTION
            SELECT @companyId = companyId, @bet = betAmount, @gameKey = gameKey
            FROM [dbo].[arcadeRounds] WITH (UPDLOCK, HOLDLOCK)
            WHERE roundId = @roundId AND clientId = @clientId AND roundStatus = 'open'

            IF @companyId IS NULL
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"round_not_open","message":"Esa ronda ya fue liquidada"}' AS [jsonResult]
                RETURN
            END

            UPDATE [dbo].[arcadeRounds]
            SET payoutAmount = @payout,
                multiplier   = CASE WHEN @bet > 0 THEN CAST(@payout AS DECIMAL(8,2)) / @bet ELSE 0 END,
                outcome      = @outcome,
                roundStatus  = 'settled',
                stateJson    = ISNULL(@stateJson, stateJson),
                resultJson   = @resultJson,
                settledAt    = GETUTCDATE(),
                updated_at   = GETUTCDATE()
            WHERE roundId = @roundId

            SELECT @walletId = walletId, @balance = coinBalance
            FROM [dbo].[arcadeWallets] WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND clientId = @clientId

            SET @balance = @balance + @payout

            UPDATE [dbo].[arcadeWallets]
            SET coinBalance    = @balance,
                lifetimeWon    = lifetimeWon + @payout,
                lifetimeRounds = lifetimeRounds + 1,
                updated_at     = GETUTCDATE()
            WHERE walletId = @walletId

            -- Perder no mueve fichas al liquidar (ya se debitaron al abrir),
            -- asi que no ensuciamos el libro con un renglon de importe 0.
            IF @payout > 0
                INSERT INTO [dbo].[arcadeTransactions]
                    (companyId, clientId, walletId, roundId, txType, amount, balanceAfter, description)
                VALUES
                    (@companyId, @clientId, @walletId, @roundId, 'payout_credit', @payout, @balance,
                     'Premio en ' + @gameKey)
        COMMIT TRANSACTION

        SELECT (SELECT TOP 1 roundId, gameKey, betAmount, payoutAmount, multiplier, outcome,
                       roundStatus, serverSeed, serverSeedHash, clientSeed, nonce,
                       @balance AS coinBalance,
                       CONVERT(NVARCHAR, settledAt, 127) AS settledAt
                FROM [dbo].[arcadeRounds] WHERE roundId = @roundId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeRounds_one — ronda por id (incluye stateJson)
-- ============================================================
-- USO INTERNO del backend: recarga el estado autoritativo entre
-- acciones. stateJson trae la baraja completa, asi que la ruta
-- NUNCA lo devuelve tal cual — modules/arcade.py arma la vista
-- recortada que ve el jugador.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeRounds_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeRounds_one;
GO

CREATE PROCEDURE [dbo].[sp_arcadeRounds_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @roundId  INT = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].roundId')
        DECLARE @clientId INT = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].clientId')

        SELECT ISNULL(
            (SELECT TOP 1 roundId, companyId, clientId, gameKey, betAmount, payoutAmount,
                    multiplier, outcome, roundStatus, serverSeedHash, clientSeed, nonce,
                    -- La semilla solo existe para el jugador DESPUES de liquidar:
                    -- revelarla con la ronda abierta le entregaria la baraja.
                    CASE WHEN roundStatus = 'settled' THEN serverSeed END AS serverSeed,
                    JSON_QUERY(stateJson)  AS state,
                    JSON_QUERY(resultJson) AS result,
                    CONVERT(NVARCHAR, settledAt, 127)  AS settledAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM [dbo].[arcadeRounds]
             WHERE roundId = @roundId AND (@clientId IS NULL OR clientId = @clientId)
             FOR JSON PATH, ROOT('arcadeRounds')),
            '{"arcadeRounds":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeRounds_all — historial del jugador
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeRounds_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeRounds_all;
GO

CREATE PROCEDURE [dbo].[sp_arcadeRounds_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT          = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].companyId')
        DECLARE @clientId  INT          = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].clientId')
        DECLARE @gameKey   NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].gameKey')
        DECLARE @top       INT          = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeRounds[0].top') AS INT), 50)

        SELECT ISNULL(
            (SELECT TOP (@top) roundId, gameKey, betAmount, payoutAmount, multiplier,
                    outcome, roundStatus, serverSeedHash, clientSeed, nonce,
                    CASE WHEN roundStatus = 'settled' THEN serverSeed END AS serverSeed,
                    CONVERT(NVARCHAR, settledAt, 127)  AS settledAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM [dbo].[arcadeRounds]
             WHERE companyId = @companyId AND clientId = @clientId
               AND (@gameKey IS NULL OR gameKey = @gameKey)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('arcadeRounds')),
            '{"arcadeRounds":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeTransactions_all — libro mayor de fichas del jugador
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeTransactions_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeTransactions_all;
GO

CREATE PROCEDURE [dbo].[sp_arcadeTransactions_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.arcadeTransactions[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.arcadeTransactions[0].clientId')
        DECLARE @top       INT = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeTransactions[0].top') AS INT), 50)

        SELECT ISNULL(
            (SELECT TOP (@top) transactionId, roundId, txType, amount, balanceAfter, description,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM [dbo].[arcadeTransactions]
             WHERE companyId = @companyId AND clientId = @clientId
             ORDER BY created_At DESC, transactionId DESC
             FOR JSON PATH, ROOT('arcadeTransactions')),
            '{"arcadeTransactions":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
