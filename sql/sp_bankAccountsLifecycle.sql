-- ============================================================
-- bankAccounts lifecycle (RFC-001, arquitectura v1.2 D11/D17/D18/D19)
-- Hand-written infra (excepción factory: evoluciona tabla existente).
--  · CLABE versionada: PENDING_VERIFICATION → PRIMARY → ARCHIVED, jamás UPDATE
--  · clabeHash (SHA-256) para no-duplicados cross-cliente sin exponer la CLABE
--  · bankAccountSnapshots: banco/CLABE/titular congelados por préstamo (D19)
--  · reveal_counterparty: única vía para ver la CLABE completa ajena (auditada)
-- Cifrado at-rest (clabeEncrypted) = hardening posterior: requiere key mgmt
-- que el hosting compartido actual no facilita; mientras, la CLABE solo sale
-- enmascarada salvo por reveal_counterparty.
-- ============================================================

-- ── ALTERs (guardados) ──────────────────────────────────────
IF COL_LENGTH('dbo.bankAccounts', 'clabeHash') IS NULL
    ALTER TABLE dbo.bankAccounts ADD clabeHash NVARCHAR(64) NULL;
GO
IF COL_LENGTH('dbo.bankAccounts', 'rfc') IS NULL
    ALTER TABLE dbo.bankAccounts ADD rfc NVARCHAR(13) NULL;
GO
IF COL_LENGTH('dbo.bankAccounts', 'accountStatus') IS NULL
    ALTER TABLE dbo.bankAccounts ADD accountStatus NVARCHAR(22) NOT NULL
        CONSTRAINT DF_bankAccounts_status DEFAULT 'PRIMARY';
GO

-- Backfill: hash + estado para filas existentes
UPDATE dbo.bankAccounts
SET clabeHash = CONVERT(NVARCHAR(64), HASHBYTES('SHA2_256', clabe), 2)
WHERE clabeHash IS NULL;
GO

-- No-duplicados entre clientes (D11): una CLABE viva pertenece a UNA persona
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_bankAccounts_clabeHash')
    CREATE UNIQUE INDEX UQ_bankAccounts_clabeHash
        ON dbo.bankAccounts (companyId, clabeHash)
        WHERE accountStatus <> 'ARCHIVED' AND isActive = 1;
GO

-- ── Tabla: bankAccountSnapshots (D19) ───────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'bankAccountSnapshots')
CREATE TABLE dbo.bankAccountSnapshots (
    snapshotId   INT IDENTITY PRIMARY KEY,
    companyId    INT NOT NULL,
    loanId       INT NOT NULL,
    clientId     INT NOT NULL,
    partyRole    NVARCHAR(10) NOT NULL,     -- borrower | lender
    bankCode     NVARCHAR(5)  NULL,
    bankName     NVARCHAR(100) NOT NULL,
    clabe        NVARCHAR(18) NOT NULL,     -- copia congelada al firmar
    clabeLast4   NVARCHAR(4)  NOT NULL,
    holderName   NVARCHAR(255) NOT NULL,    -- titular esperado (D17)
    created_At   DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_snapshot UNIQUE (loanId, partyRole),
    CONSTRAINT CK_snapshot_role CHECK (partyRole IN ('borrower','lender'))
);
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_bankAccountsLifecycle', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_bankAccountsLifecycle;
GO
CREATE PROCEDURE [dbo].[sp_bankAccountsLifecycle]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action      NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].action')
        DECLARE @companyId   INT           = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].companyId')
        DECLARE @clientId    INT           = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].clientId')
        DECLARE @clabe       NVARCHAR(18)  = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].clabe')
        DECLARE @bankCode    NVARCHAR(5)   = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankCode')
        DECLARE @bankName    NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankName')
        DECLARE @holderName  NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].holderName')
        DECLARE @rfc         NVARCHAR(13)  = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].rfc')
        DECLARE @loanId      INT           = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].loanId')
        DECLARE @requesterClientId INT     = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].requesterClientId')
        DECLARE @requesterUserId   INT     = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].requesterUserId')
        DECLARE @borrowerClientId  INT     = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].borrowerClientId')
        DECLARE @lenderClientId    INT     = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].lenderClientId')
        DECLARE @hash NVARCHAR(64) = CASE WHEN @clabe IS NULL THEN NULL
            ELSE CONVERT(NVARCHAR(64), HASHBYTES('SHA2_256', @clabe), 2) END

        -- ── check_duplicate ─────────────────────────────────
        IF @action = 'check_duplicate'
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.bankAccounts
                       WHERE companyId = @companyId AND clabeHash = @hash
                         AND accountStatus <> 'ARCHIVED' AND isActive = 1
                         AND clientId <> ISNULL(@clientId, -1))
                SELECT '{"duplicate":true}' AS [jsonResult]
            ELSE
                SELECT '{"duplicate":false}' AS [jsonResult]
            RETURN
        END

        -- ── add_pending (D18: nueva CLABE = INSERT, jamás UPDATE) ──
        IF @action = 'add_pending'
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.bankAccounts
                       WHERE companyId = @companyId AND clabeHash = @hash
                         AND accountStatus <> 'ARCHIVED' AND isActive = 1
                         AND clientId <> @clientId)
            BEGIN
                SELECT '{"error":"Esta CLABE ya está registrada por otro cliente."}' AS [jsonResult]
                RETURN
            END
            -- ¿Primera cuenta del cliente? → nace PRIMARY directo
            DECLARE @hasPrimary BIT = CASE WHEN EXISTS (
                SELECT 1 FROM dbo.bankAccounts
                WHERE companyId = @companyId AND clientId = @clientId
                  AND accountStatus = 'PRIMARY' AND isActive = 1) THEN 1 ELSE 0 END

            INSERT INTO dbo.bankAccounts
                (companyId, clientId, clabe, clabeHash, bankCode, bankName,
                 holderName, rfc, accountStatus, isDefault, isVerified)
            VALUES
                (@companyId, @clientId, @clabe, @hash, @bankCode, @bankName,
                 @holderName, @rfc,
                 CASE WHEN @hasPrimary = 1 THEN 'PENDING_VERIFICATION' ELSE 'PRIMARY' END,
                 CASE WHEN @hasPrimary = 1 THEN 0 ELSE 1 END, 0)

            SELECT (SELECT TOP 1 bankAccountId, accountStatus, clabeLast4 = RIGHT(clabe,4),
                           bankName, holderName
                    FROM dbo.bankAccounts WHERE bankAccountId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
            RETURN
        END

        -- ── promote_primary (bloqueada con préstamos activos) ──
        IF @action = 'promote_primary'
        BEGIN
            DECLARE @pendingId INT = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankAccountId')
            IF EXISTS (SELECT 1 FROM dbo.loans l
                       WHERE l.companyId = @companyId
                         AND l.loanStatus IN ('active','pending_funding','funded','in_dispute')
                         AND (l.clientId = @clientId OR EXISTS (
                              SELECT 1 FROM dbo.loanContracts c
                              WHERE c.loanId = l.loanId AND c.lenderClientId = @clientId)))
            BEGIN
                SELECT '{"error":"No puedes cambiar tu cuenta principal con préstamos activos. Se promoverá al liquidarlos."}' AS [jsonResult]
                RETURN
            END
            UPDATE dbo.bankAccounts SET accountStatus = 'ARCHIVED', isDefault = 0, updated_at = GETUTCDATE()
            WHERE companyId = @companyId AND clientId = @clientId
              AND accountStatus = 'PRIMARY' AND bankAccountId <> @pendingId;
            UPDATE dbo.bankAccounts SET accountStatus = 'PRIMARY', isDefault = 1, updated_at = GETUTCDATE()
            WHERE companyId = @companyId AND bankAccountId = @pendingId
              AND accountStatus = 'PENDING_VERIFICATION';
            SELECT '{"promoted":true}' AS [jsonResult]
            RETURN
        END

        -- ── archive ─────────────────────────────────────────
        IF @action = 'archive'
        BEGIN
            DECLARE @archiveId INT = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankAccountId')
            UPDATE dbo.bankAccounts SET accountStatus = 'ARCHIVED', isDefault = 0,
                   isActive = 0, updated_at = GETUTCDATE()
            WHERE companyId = @companyId AND bankAccountId = @archiveId
              AND accountStatus <> 'PRIMARY';   -- la PRIMARY no se archiva directo
            IF @@ROWCOUNT = 0
                SELECT '{"error":"La cuenta principal no se archiva directamente: promueve otra primero."}' AS [jsonResult]
            ELSE
                SELECT '{"archived":true}' AS [jsonResult]
            RETURN
        END

        -- ── snapshot_for_loan (D19: congela ambas partes al firmar) ──
        IF @action = 'snapshot_for_loan'
        BEGIN
            -- UNA cuenta por cliente: PRIMARY, prefiriendo default y verificada
            ;WITH ranked AS (
                SELECT b.*, ROW_NUMBER() OVER (
                    PARTITION BY b.clientId
                    ORDER BY b.isDefault DESC, b.isVerified DESC, b.created_At DESC) AS rn
                FROM dbo.bankAccounts b
                WHERE b.companyId = @companyId AND b.isActive = 1
                  AND b.accountStatus = 'PRIMARY'
                  AND b.clientId IN (@borrowerClientId, @lenderClientId)
            )
            INSERT INTO dbo.bankAccountSnapshots
                (companyId, loanId, clientId, partyRole, bankCode, bankName, clabe, clabeLast4, holderName)
            SELECT @companyId, @loanId, r.clientId,
                   CASE WHEN r.clientId = @borrowerClientId THEN 'borrower' ELSE 'lender' END,
                   r.bankCode, ISNULL(r.bankName,'Banco'), r.clabe, RIGHT(r.clabe,4), r.holderName
            FROM ranked r
            WHERE r.rn = 1
              AND NOT EXISTS (SELECT 1 FROM dbo.bankAccountSnapshots s
                              WHERE s.loanId = @loanId AND s.clientId = r.clientId);
            SELECT (SELECT snapshotId, clientId, partyRole, bankName, clabeLast4, holderName
                    FROM dbo.bankAccountSnapshots WHERE loanId = @loanId
                    FOR JSON PATH) AS [jsonResult]
            RETURN
        END

        -- ── reveal_counterparty (D4: única vía a la CLABE completa ajena) ──
        IF @action = 'reveal_counterparty'
        BEGIN
            -- El solicitante debe ser parte del préstamo
            IF NOT EXISTS (SELECT 1 FROM dbo.bankAccountSnapshots
                           WHERE companyId = @companyId AND loanId = @loanId
                             AND clientId = @requesterClientId)
            BEGIN
                SELECT '{"error":"No eres parte de este préstamo."}' AS [jsonResult]
                RETURN
            END
            -- Auditoría durable de la revelación
            INSERT INTO dbo.auditLogs
                (correlationId, companyId, actorUserId, actorClientId,
                 entityName, entityId, fieldName, oldValue, newValue, action)
            VALUES
                (NEWID(), @companyId, @requesterUserId, @requesterClientId,
                 'bankAccountSnapshots', CAST(@loanId AS NVARCHAR(50)),
                 'clabe', NULL, 'REVEALED_TO_COUNTERPARTY', 'READ')

            SELECT (SELECT TOP 1 s.partyRole, s.bankName, s.clabe, s.holderName,
                           advertencia = N'Antes de enviar, verifica que tu banco muestre este titular. Si aparece otro nombre, NO transfieras.'
                    FROM dbo.bankAccountSnapshots s
                    WHERE s.companyId = @companyId AND s.loanId = @loanId
                      AND s.clientId <> @requesterClientId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
            RETURN
        END

        SELECT '{"error":"Acción no soportada."}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
