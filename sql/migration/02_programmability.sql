/* Generado desde [montanogilberto_smartloans] el 2026-08-15 15:50:03
   por sql/migration/generate_migration.py — NO editar a mano. */
/* PASO 2 de 3 — 1 functions, 188 stored procedures, 1 triggers, 3 views */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* ---------- VIEWS ---------- */

-- dbo.vw_sellListings_daily_history
IF OBJECT_ID(N'dbo.vw_sellListings_daily_history', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_sellListings_daily_history];
GO
CREATE   VIEW dbo.vw_sellListings_daily_history
AS
SELECT
  channel,
  market,
  channelItemId,
  unifiedProductId,
  listingDate,
  sellPriceUsd,
  sellPriceOriginal,
  currencyOriginal,
  fxRateToUsd,
  fxAsOfDate,
  rating,
  reviewsCount
FROM dbo.sellListings;
GO

-- dbo.vw_sellListings_latest_item
IF OBJECT_ID(N'dbo.vw_sellListings_latest_item', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_sellListings_latest_item];
GO
CREATE   VIEW dbo.vw_sellListings_latest_item
AS
WITH x AS (
  SELECT
    sl.*,
    rn = ROW_NUMBER() OVER (
      PARTITION BY sl.channel, sl.market, sl.channelItemId
      ORDER BY sl.listingDate DESC, sl.updatedAt DESC
    )
  FROM dbo.sellListings sl
)
SELECT
  sellListingId,
  channel,
  market,
  channelItemId,
  title,
  sellPriceOriginal,
  currencyOriginal,
  sellPriceUsd,
  fxRateToUsd,
  fxAsOfDate,
  listingTimestamp,
  listingDate,
  unifiedProductId,
  createdAt,
  updatedAt
FROM x
WHERE rn = 1;
GO

-- dbo.vw_sellListings_latest_unified
IF OBJECT_ID(N'dbo.vw_sellListings_latest_unified', N'V') IS NOT NULL
    DROP VIEW [dbo].[vw_sellListings_latest_unified];
GO
CREATE   VIEW dbo.vw_sellListings_latest_unified
AS
WITH x AS (
  SELECT
    sl.*,
    rn = ROW_NUMBER() OVER (
      PARTITION BY sl.unifiedProductId, sl.channel, sl.market
      ORDER BY sl.listingDate DESC, sl.updatedAt DESC
    )
  FROM dbo.sellListings sl
  WHERE sl.unifiedProductId IS NOT NULL
)
SELECT
  sellListingId,
  unifiedProductId,
  channel,
  market,
  channelItemId,
  title,
  sellPriceOriginal,
  currencyOriginal,
  sellPriceUsd,
  fxRateToUsd,
  fxAsOfDate,
  listingTimestamp,
  listingDate,
  createdAt,
  updatedAt
FROM x
WHERE rn = 1;
GO

/* ---------- FUNCTIONS ---------- */

-- dbo.fn_diagramobjects
IF OBJECT_ID(N'dbo.fn_diagramobjects', N'FN') IS NOT NULL
    DROP FUNCTION [dbo].[fn_diagramobjects];
GO

	CREATE FUNCTION dbo.fn_diagramobjects() 
	RETURNS int
	WITH EXECUTE AS N'dbo'
	AS
	BEGIN
		declare @id_upgraddiagrams		int
		declare @id_sysdiagrams			int
		declare @id_helpdiagrams		int
		declare @id_helpdiagramdefinition	int
		declare @id_creatediagram	int
		declare @id_renamediagram	int
		declare @id_alterdiagram 	int 
		declare @id_dropdiagram		int
		declare @InstalledObjects	int

		select @InstalledObjects = 0

		select 	@id_upgraddiagrams = object_id(N'dbo.sp_upgraddiagrams'),
			@id_sysdiagrams = object_id(N'dbo.sysdiagrams'),
			@id_helpdiagrams = object_id(N'dbo.sp_helpdiagrams'),
			@id_helpdiagramdefinition = object_id(N'dbo.sp_helpdiagramdefinition'),
			@id_creatediagram = object_id(N'dbo.sp_creatediagram'),
			@id_renamediagram = object_id(N'dbo.sp_renamediagram'),
			@id_alterdiagram = object_id(N'dbo.sp_alterdiagram'), 
			@id_dropdiagram = object_id(N'dbo.sp_dropdiagram')

		if @id_upgraddiagrams is not null
			select @InstalledObjects = @InstalledObjects + 1
		if @id_sysdiagrams is not null
			select @InstalledObjects = @InstalledObjects + 2
		if @id_helpdiagrams is not null
			select @InstalledObjects = @InstalledObjects + 4
		if @id_helpdiagramdefinition is not null
			select @InstalledObjects = @InstalledObjects + 8
		if @id_creatediagram is not null
			select @InstalledObjects = @InstalledObjects + 16
		if @id_renamediagram is not null
			select @InstalledObjects = @InstalledObjects + 32
		if @id_alterdiagram  is not null
			select @InstalledObjects = @InstalledObjects + 64
		if @id_dropdiagram is not null
			select @InstalledObjects = @InstalledObjects + 128
		
		return @InstalledObjects 
	END
GO

/* ---------- STORED PROCEDURES ---------- */

-- dbo.one_products
IF OBJECT_ID(N'dbo.one_products', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[one_products];
GO
/* SQL Server (T-SQL) example:
   Returns one product with nested productDetails + productOptions + optionChoices
   in the same JSON shape as your /one_products output.
*/
CREATE   PROCEDURE dbo.one_products
    @productId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.productId,
        p.name,
        ISNULL(p.barCode, '') AS barCode,
        ISNULL(p.code, '') AS code,
        CONVERT(varchar(10), p.dateOfExpire, 23) AS dateOfExpire, -- yyyy-mm-dd
        ISNULL(p.productFormId, 0) AS productFormId,
        ISNULL(p.manufactureId, 0) AS manufactureId,
        ISNULL(p.description, '') AS description,
        p.categoryId,
        p.companyId,
        p.createdAt,
        p.updatedAt,

        -- productDetails (array)
        JSON_QUERY(
            ISNULL((
                SELECT
                    pd.stockQuantity,
                    pd.unitPrice,
                    pd.salePrice
                FROM dbo.product_details pd
                WHERE pd.productId = p.productId
                FOR JSON PATH
            ), '[]')
        ) AS productDetails,

        -- productOptions (array), each with optionChoices (array)
        JSON_QUERY(
            ISNULL((
                SELECT
                    po.optionKey,
                    po.name,
                    po.[type],

                    JSON_QUERY(
                        ISNULL((
                            SELECT
                                poc.choiceKey,
                                poc.name,
                                poc.price,
                                ISNULL(poc.description, '') AS description
                            FROM dbo.product_option_choices poc
                            WHERE poc.productOptionId = po.productOptionId
                            ORDER BY poc.productOptionChoiceId
                            FOR JSON PATH
                        ), '[]')
                    ) AS optionChoices

                FROM dbo.product_options po
                WHERE po.productId = p.productId
                ORDER BY po.productOptionId
                FOR JSON PATH
            ), '[]')
        ) AS productOptions

    FROM dbo.products p
    WHERE p.productId = @productId
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_alterdiagram
IF OBJECT_ID(N'dbo.sp_alterdiagram', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_alterdiagram];
GO

	CREATE PROCEDURE dbo.sp_alterdiagram
	(
		@diagramname 	sysname,
		@owner_id	int	= null,
		@version 	int,
		@definition 	varbinary(max)
	)
	WITH EXECUTE AS 'dbo'
	AS
	BEGIN
		set nocount on
	
		declare @theId 			int
		declare @retval 		int
		declare @IsDbo 			int
		
		declare @UIDFound 		int
		declare @DiagId			int
		declare @ShouldChangeUID	int
	
		if(@diagramname is null)
		begin
			RAISERROR ('Invalid ARG', 16, 1)
			return -1
		end
	
		execute as caller;
		select @theId = DATABASE_PRINCIPAL_ID();	 
		select @IsDbo = IS_MEMBER(N'db_owner'); 
		if(@owner_id is null)
			select @owner_id = @theId;
		revert;
	
		select @ShouldChangeUID = 0
		select @DiagId = diagram_id, @UIDFound = principal_id from dbo.sysdiagrams where principal_id = @owner_id and name = @diagramname 
		
		if(@DiagId IS NULL or (@IsDbo = 0 and @theId <> @UIDFound))
		begin
			RAISERROR ('Diagram does not exist or you do not have permission.', 16, 1);
			return -3
		end
	
		if(@IsDbo <> 0)
		begin
			if(@UIDFound is null or USER_NAME(@UIDFound) is null) -- invalid principal_id
			begin
				select @ShouldChangeUID = 1 ;
			end
		end

		-- update dds data			
		update dbo.sysdiagrams set definition = @definition where diagram_id = @DiagId ;

		-- change owner
		if(@ShouldChangeUID = 1)
			update dbo.sysdiagrams set principal_id = @theId where diagram_id = @DiagId ;

		-- update dds version
		if(@version is not null)
			update dbo.sysdiagrams set version = @version where diagram_id = @DiagId ;

		return 0
	END
GO

-- dbo.sp_applicationLog
IF OBJECT_ID(N'dbo.sp_applicationLog', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_applicationLog];
GO
CREATE PROCEDURE [dbo].[sp_applicationLog] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [dbo].[applicationLogs]
            (correlationId, workflowId, companyId, [level], source, message, exception,
             apiEndpoint, httpStatus, durationMs, ipAddress)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            ISNULL(JSON_VALUE(value, '$.level'), 'INFO'),
            JSON_VALUE(value, '$.source'),
            JSON_VALUE(value, '$.message'),
            JSON_VALUE(value, '$.exception'),
            JSON_VALUE(value, '$.apiEndpoint'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.httpStatus')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.durationMs')),
            JSON_VALUE(value, '$.ipAddress')
        FROM OPENJSON(@pjsonfile, '$.logs')
        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_auditLog
IF OBJECT_ID(N'dbo.sp_auditLog', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_auditLog];
GO
CREATE PROCEDURE [dbo].[sp_auditLog] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [dbo].[auditLogs]
            (correlationId, companyId, actorUserId, actorClientId, entityName, entityId,
             fieldName, oldValue, newValue, action, ipAddress, deviceInfo)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.actorUserId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.actorClientId')),
            JSON_VALUE(value, '$.entityName'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.entityId')),
            JSON_VALUE(value, '$.fieldName'),
            JSON_VALUE(value, '$.oldValue'),
            JSON_VALUE(value, '$.newValue'),
            JSON_VALUE(value, '$.action'),
            JSON_VALUE(value, '$.ipAddress'),
            JSON_VALUE(value, '$.deviceInfo')
        FROM OPENJSON(@pjsonfile, '$.logs')
        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_bankAccounts
IF OBJECT_ID(N'dbo.sp_bankAccounts', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_bankAccounts];
GO

CREATE PROCEDURE [dbo].[sp_bankAccounts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action             INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].action')
        DECLARE @bankAccountId      INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankAccountId')
        DECLARE @companyId          INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].companyId')
        DECLARE @clientId           INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].clientId')
        DECLARE @clabe              NVARCHAR(18)   = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].clabe')
        DECLARE @bankCode           NVARCHAR(5)    = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankCode')
        DECLARE @bankName           NVARCHAR(100)  = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankName')
        DECLARE @holderName         NVARCHAR(255)  = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].holderName')
        DECLARE @isVerified         BIT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].isVerified')
        DECLARE @verificationMethod NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].verificationMethod')
        DECLARE @verificationCents  INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].verificationCents')
        DECLARE @isDefault          BIT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].isDefault')
        DECLARE @isActive           BIT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].isActive')

        IF @action = 1 -- CREATE (link)
        BEGIN
            -- First account for the client becomes the default automatically.
            DECLARE @firstForClient BIT =
                CASE WHEN EXISTS (SELECT 1 FROM [dbo].[bankAccounts]
                                  WHERE clientId = @clientId AND companyId = @companyId AND isActive = 1)
                     THEN 0 ELSE 1 END;

            INSERT INTO [dbo].[bankAccounts]
                (companyId, clientId, clabe, bankCode, bankName, holderName,
                 verificationMethod, verificationCents, isDefault)
            VALUES
                (@companyId, @clientId, @clabe, @bankCode, @bankName, @holderName,
                 ISNULL(@verificationMethod, 'micro_deposit'), @verificationCents,
                 ISNULL(@isDefault, @firstForClient))

            SELECT (SELECT TOP 1 bankAccountId, companyId, clientId,
                           RIGHT(clabe, 4) AS clabeLast4, bankCode, bankName, holderName,
                           isVerified, verificationMethod, isDefault,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[bankAccounts]
                    WHERE bankAccountId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (verify / set default / rename)
        BEGIN
            -- Making this account the default clears the previous one.
            IF @isDefault = 1
                UPDATE [dbo].[bankAccounts]
                SET isDefault = 0, updated_at = GETUTCDATE()
                WHERE clientId = (SELECT clientId FROM [dbo].[bankAccounts] WHERE bankAccountId = @bankAccountId)
                  AND companyId = @companyId AND bankAccountId <> @bankAccountId AND isDefault = 1;

            UPDATE [dbo].[bankAccounts]
            SET isVerified        = ISNULL(@isVerified, isVerified),
                verificationMethod = ISNULL(@verificationMethod, verificationMethod),
                -- On successful verification burn the micro-deposit code.
                verificationCents = CASE WHEN @isVerified = 1 THEN NULL ELSE verificationCents END,
                verifiedAt        = CASE WHEN @isVerified = 1 THEN GETUTCDATE() ELSE verifiedAt END,
                holderName        = ISNULL(@holderName, holderName),
                isDefault         = ISNULL(@isDefault, isDefault),
                isActive          = ISNULL(@isActive, isActive),
                updated_at        = GETUTCDATE()
            WHERE bankAccountId = @bankAccountId AND companyId = @companyId

            SELECT (SELECT TOP 1 bankAccountId, clientId, RIGHT(clabe, 4) AS clabeLast4,
                           bankName, isVerified, isDefault,
                           CONVERT(NVARCHAR, verifiedAt, 127) AS verifiedAt
                    FROM [dbo].[bankAccounts]
                    WHERE bankAccountId = @bankAccountId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- SOFT DELETE (audit trail keeps the row)
        BEGIN
            UPDATE [dbo].[bankAccounts]
            SET isActive = 0, isDefault = 0, updated_at = GETUTCDATE()
            WHERE bankAccountId = @bankAccountId AND companyId = @companyId

            SELECT '{"message":"deleted","bankAccountId":' + CAST(@bankAccountId AS NVARCHAR(20)) + '}' AS [jsonResult]
        END

        ELSE
            SELECT '{"error":"Invalid action"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_bankAccountsLifecycle
IF OBJECT_ID(N'dbo.sp_bankAccountsLifecycle', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_bankAccountsLifecycle];
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

-- dbo.sp_bankAccounts_all
IF OBJECT_ID(N'dbo.sp_bankAccounts_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_bankAccounts_all];
GO
CREATE PROCEDURE [dbo].[sp_bankAccounts_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].companyId')
    DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].clientId')

    SELECT ISNULL(
        (SELECT bankAccountId, companyId, clientId,
                RIGHT(clabe, 4) AS clabeLast4, bankCode, bankName, holderName,
                isVerified, verificationMethod, isDefault, isActive,
                CONVERT(NVARCHAR, verifiedAt, 127) AS verifiedAt,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[bankAccounts]
         WHERE companyId = @companyId
           AND (@clientId IS NULL OR clientId = @clientId)
           AND isActive = 1
         ORDER BY isDefault DESC, created_At DESC
         FOR JSON PATH, ROOT('bankAccounts')),
        '{"bankAccounts":[]}'
    ) AS [jsonResult]
END
GO

-- dbo.sp_bankAccounts_one
IF OBJECT_ID(N'dbo.sp_bankAccounts_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_bankAccounts_one];
GO
CREATE PROCEDURE [dbo].[sp_bankAccounts_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @bankAccountId INT = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankAccountId')

    -- Internal read for the verify endpoint / orchestrator: includes the full
    -- CLABE and pending verificationCents — never expose this SP's raw output
    -- to a client-facing response (modules must mask).
    SELECT ISNULL(
        (SELECT TOP 1 bankAccountId, companyId, clientId, clabe, bankCode, bankName,
                holderName, isVerified, verificationMethod, verificationCents,
                isDefault, isActive,
                CONVERT(NVARCHAR, verifiedAt, 127) AS verifiedAt
         FROM [dbo].[bankAccounts]
         WHERE bankAccountId = @bankAccountId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO

-- dbo.sp_buyOffers
IF OBJECT_ID(N'dbo.sp_buyOffers', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_buyOffers];
GO

CREATE PROC [dbo].[sp_buyOffers] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

  /*
  DECLARE @pjsonfile VARCHAR(MAX) = '{
    "buyOffers": [
      {
        "buyOfferId": 1,
        "sourceType": "online",
        "sourceName": "Walmart",
        "supplierSku": "SKU-123",
        "titleRaw": "Product X",
        "buyPriceOriginal": 100.00,
        "currencyOriginal": "USD",
        "buyPriceUsd": 100.00,
        "fxRateToUsd": 1.0,
        "fxAsOfDate": "2026-01-15",
        "minQty": 1,
        "leadTimeDays": 2,
        "shippingBuyOriginal": 5.00,
        "shippingBuyUsd": 5.00,
        "taxBuyOriginal": 8.00,
        "taxBuyUsd": 8.00,
        "offerTimestamp": "2026-01-15T18:00:00",
        "unifiedProductId": 1,
        "action": "1"
      }
    ]
  }';
  */

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
                 FROM OPENJSON(@pjsonfile, '$.buyOffers'));

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.buyOffers (
        sourceType, sourceName, supplierSku, titleRaw,
        buyPriceOriginal, currencyOriginal, buyPriceUsd,
        fxRateToUsd, fxAsOfDate,
        minQty, leadTimeDays,
        shippingBuyOriginal, shippingBuyUsd,
        taxBuyOriginal, taxBuyUsd,
        offerTimestamp, unifiedProductId
      )
      SELECT
        JSON_VALUE(value, '$.sourceType'),
        JSON_VALUE(value, '$.sourceName'),
        JSON_VALUE(value, '$.supplierSku'),
        JSON_VALUE(value, '$.titleRaw'),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.buyPriceOriginal')),
        JSON_VALUE(value, '$.currencyOriginal'),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.buyPriceUsd')),
        TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(value, '$.fxRateToUsd')),
        TRY_CONVERT(DATE, JSON_VALUE(value, '$.fxAsOfDate')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.minQty')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.leadTimeDays')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.shippingBuyOriginal')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.shippingBuyUsd')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.taxBuyOriginal')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.taxBuyUsd')),
        TRY_CONVERT(DATETIME2, JSON_VALUE(value, '$.offerTimestamp')),
        TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.unifiedProductId'))
      FROM OPENJSON(@pjsonfile, '$.buyOffers');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE b
      SET
        b.sourceType = JSON_VALUE(j.value, '$.sourceType'),
        b.sourceName = JSON_VALUE(j.value, '$.sourceName'),
        b.supplierSku = JSON_VALUE(j.value, '$.supplierSku'),
        b.titleRaw = JSON_VALUE(j.value, '$.titleRaw'),
        b.buyPriceOriginal = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.buyPriceOriginal')),
        b.currencyOriginal = JSON_VALUE(j.value, '$.currencyOriginal'),
        b.buyPriceUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.buyPriceUsd')),
        b.fxRateToUsd = TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(j.value, '$.fxRateToUsd')),
        b.fxAsOfDate = TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.fxAsOfDate')),
        b.minQty = TRY_CONVERT(INT, JSON_VALUE(j.value, '$.minQty')),
        b.leadTimeDays = TRY_CONVERT(INT, JSON_VALUE(j.value, '$.leadTimeDays')),
        b.shippingBuyOriginal = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.shippingBuyOriginal')),
        b.shippingBuyUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.shippingBuyUsd')),
        b.taxBuyOriginal = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.taxBuyOriginal')),
        b.taxBuyUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.taxBuyUsd')),
        b.offerTimestamp = TRY_CONVERT(DATETIME2, JSON_VALUE(j.value, '$.offerTimestamp')),
        b.unifiedProductId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.unifiedProductId')),
        b.updatedAt = SYSUTCDATETIME()
      FROM dbo.buyOffers b
      INNER JOIN OPENJSON(@pjsonfile, '$.buyOffers') j
        ON b.buyOfferId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.buyOfferId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.buyOffers
      WHERE buyOfferId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.buyOfferId'))
        FROM OPENJSON(@pjsonfile, '$.buyOffers')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH

  SELECT
    JSON_VALUE(value, '$.value') AS [value],
    JSON_VALUE(value, '$.msg')   AS [msg],
    JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_cashRegister
IF OBJECT_ID(N'dbo.sp_cashRegister', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_cashRegister];
GO

CREATE PROC [dbo].[sp_cashRegister]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  ------------------------------------------------------------
  -- Standard output
  ------------------------------------------------------------
  DECLARE
    @Outputmessage NVARCHAR(MAX) = N'{
      "result": [
        { "value": "", "msg": "", "error": "0", "output_json": null }
      ]
    }',
    @Error         NVARCHAR(4000) = N'',
    @action        INT;

  ------------------------------------------------------------
  -- Read action
  ------------------------------------------------------------
  SET @action = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.register[0].action'));

  IF @action IS NULL
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid input: action required.');
    GOTO ReturnResult;
  END;

  ------------------------------------------------------------
  -- Common fields
  ------------------------------------------------------------
  DECLARE
    @companyId        INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.register[0].companyId')),
    @userId           INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.register[0].userId')),
    @sessionId        INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.register[0].sessionId')),
    @openingCash      DECIMAL(10,2)  = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile, '$.register[0].openingCash')),
    @closingCash      DECIMAL(10,2)  = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile, '$.register[0].closingCash')),
    @movementType     VARCHAR(50)    = JSON_VALUE(@pjsonfile, '$.register[0].movementType'),
    @amount           DECIMAL(10,2)  = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile, '$.register[0].amount')),
    @incomeId         INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.register[0].incomeId')),
    @notes            NVARCHAR(250)  = JSON_VALUE(@pjsonfile, '$.register[0].notes'),
    
    -- New columns parsing mapping
    @openingNotes     NVARCHAR(500)  = JSON_VALUE(@pjsonfile, '$.register[0].openingNotes'),
    @closingNotes     NVARCHAR(500)  = JSON_VALUE(@pjsonfile, '$.register[0].closingNotes'),
    @autoClosed       BIT            = COALESCE(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.register[0].autoClosed')), 0),
    @cashPaid         DECIMAL(10,2)  = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile, '$.register[0].cashPaid')),
    @cashReturn       DECIMAL(10,2)  = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile, '$.register[0].cashReturn')),

    @startOfMonth     DATETIME       = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1),
    @startOfNextMonth DATETIME       = DATEADD(MONTH, 1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));

  -- Normalize movementType
  DECLARE
    @movementTypeNorm VARCHAR(50) = LOWER(LTRIM(RTRIM(COALESCE(@movementType, ''))));

  DECLARE
    @openSessionId INT,
    @systemBalance DECIMAL(10,2),
    @variance      DECIMAL(10,2);

  ------------------------------------------------------------
  -- Find open session
  ------------------------------------------------------------
  SELECT TOP 1 @openSessionId = sessionId
  FROM dbo.cashRegisterSessions
  WHERE companyId = @companyId
    AND status = 'open'
  ORDER BY openedAt DESC;

  BEGIN TRY

  /* ============================================================
     ACTION 1 : OPEN SESSION
  ============================================================ */
  IF @action = 1
  BEGIN
    IF @companyId IS NULL OR @userId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'companyId and userId required');
      GOTO ReturnResult;
    END;

    IF @openingCash IS NULL 
      SET @openingCash = 0;

    IF @openSessionId IS NOT NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Session already open');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @openSessionId));
      GOTO ReturnResult;
    END;

    BEGIN TRAN;

    INSERT INTO dbo.cashRegisterSessions
      (companyId, openedByUserId, openedAt, openingCash, status, openingNotes, autoClosed)
    VALUES
      (@companyId, @userId, GETDATE(), @openingCash, 'open', @openingNotes, 0);

    SET @sessionId = SCOPE_IDENTITY();

    COMMIT;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @sessionId));
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Session opened');

    SET @Outputmessage = JSON_MODIFY(
      @Outputmessage,
      '$.result[0].output_json',
      JSON_QUERY(CONCAT(
        '{',
          '"sessionId":', @sessionId, ',',
          '"openingCash":', FORMAT(@openingCash, '0.00'), ',',
          '"openingNotes":', COALESCE('"' + STRING_ESCAPE(@openingNotes, 'json') + '"', 'null'),
        '}'
      ))
    );

    GOTO ReturnResult;
  END;

  /* ============================================================
     ACTION 2 : CLOSE SESSION
  ============================================================ */
  IF @action = 2
  BEGIN
    IF @companyId IS NULL OR @userId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'companyId and userId required');
      GOTO ReturnResult;
    END;

    IF @sessionId IS NULL 
      SET @sessionId = @openSessionId;

    IF @sessionId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No open session');
      GOTO ReturnResult;
    END;

    SELECT
      @systemBalance =
        S.openingCash +
        COALESCE(SUM(
          CASE
            WHEN LOWER(LTRIM(RTRIM(M.movementType))) IN ('out', 'salida', 'retiro') THEN -M.amount
            ELSE M.amount
          END
        ), 0)
    FROM dbo.cashRegisterSessions S
    LEFT JOIN dbo.cashRegisterMovements M
      ON M.sessionId = S.sessionId
    WHERE S.sessionId = @sessionId
    GROUP BY S.openingCash;

    IF @systemBalance IS NULL 
      SET @systemBalance = 0;
    
    IF @closingCash IS NULL 
      SET @closingCash = @systemBalance;

    SET @variance = @closingCash - @systemBalance;

    BEGIN TRAN;

    UPDATE dbo.cashRegisterSessions
    SET closedAt = GETDATE(),
        closedByUserId = @userId,
        closingCash = @closingCash,
        status = 'closed',
        closingNotes = @closingNotes,
        autoClosed = @autoClosed,
        expectedCash = @systemBalance,
        cashDifference = @variance
    WHERE sessionId = @sessionId
      AND companyId = @companyId
      AND status = 'open';

    IF @@ROWCOUNT = 0
    BEGIN
      ROLLBACK;
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Session not found or already closed');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @sessionId));
      GOTO ReturnResult;
    END;

    COMMIT;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @sessionId));
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Session closed');

    SET @Outputmessage = JSON_MODIFY(
      @Outputmessage,
      '$.result[0].output_json',
      JSON_QUERY(CONCAT(
        '{',
        '"sessionId":', @sessionId, ',',
        '"systemBalance":', FORMAT(@systemBalance, '0.00'), ',',
        '"closingCash":', FORMAT(@closingCash, '0.00'), ',',
        '"variance":', FORMAT(@variance, '0.00'), ',',
        '"autoClosed":', CASE WHEN @autoClosed = 1 THEN 'true' ELSE 'false' END,
        '}'
      ))
    );

    GOTO ReturnResult;
  END;

  /* ============================================================
     ACTION 3 : ADD MOVEMENT
  ============================================================ */
  IF @action = 3
  BEGIN
    IF @companyId IS NULL OR @userId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'companyId and userId required');
      GOTO ReturnResult;
    END;

    IF @sessionId IS NULL 
      SET @sessionId = @openSessionId;

    IF @sessionId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No open session');
      GOTO ReturnResult;
    END;

    IF @movementTypeNorm = ''
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'movementType is required');
      GOTO ReturnResult;
    END;

    IF @amount IS NULL OR @amount <= 0
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'amount must be > 0');
      GOTO ReturnResult;
    END;

    IF NOT EXISTS (
      SELECT 1
      FROM dbo.cashRegisterSessions
      WHERE sessionId = @sessionId
        AND companyId = @companyId
        AND status = 'open'
    )
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Session not found or not open');
      GOTO ReturnResult;
    END;

    BEGIN TRAN;

    INSERT INTO dbo.cashRegisterMovements
      (sessionId, companyId, userId, movementType, amount, incomeId, notes, createdAt, cashPaid, cashReturn)
    VALUES
      (@sessionId, @companyId, @userId, @movementTypeNorm, @amount, @incomeId, @notes, GETDATE(), @cashPaid, @cashReturn);

    DECLARE @movementId INT = SCOPE_IDENTITY();

    COMMIT;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @movementId));
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Movement inserted');

    SET @Outputmessage = JSON_MODIFY(
      @Outputmessage,
      '$.result[0].output_json',
      JSON_QUERY(CONCAT(
        '{',
          '"movementId":', @movementId, ',',
          '"sessionId":', @sessionId, ',',
          '"movementType":"', @movementTypeNorm, '",',
          '"amount":', FORMAT(@amount, '0.00'), ',',
          '"cashPaid":', COALESCE(FORMAT(@cashPaid, '0.00'), 'null'), ',',
          '"cashReturn":', COALESCE(FORMAT(@cashReturn, '0.00'), 'null'), ',',
          '"incomeId":', COALESCE(CONVERT(NVARCHAR(20), @incomeId), 'null'),
        '}'
      ))
    );

    GOTO ReturnResult;
  END;

  /* ============================================================
     ACTION 4 : GET OPEN SESSION
  ============================================================ */
  IF @action = 4
  BEGIN
    IF @companyId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'companyId is required');
      GOTO ReturnResult;
    END;

    IF @openSessionId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'OK');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', '');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].output_json', NULL);
      GOTO ReturnResult;
    END;

    SELECT
      @systemBalance =
        S.openingCash +
        COALESCE(SUM(
          CASE
            WHEN LOWER(LTRIM(RTRIM(M.movementType))) IN ('out', 'salida', 'retiro') THEN -M.amount
            ELSE M.amount
          END
        ), 0)
    FROM dbo.cashRegisterSessions S
    LEFT JOIN dbo.cashRegisterMovements M
      ON M.sessionId = S.sessionId
    WHERE S.sessionId = @openSessionId
    GROUP BY S.openingCash;

    IF @systemBalance IS NULL 
      SET @systemBalance = 0;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @openSessionId));
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'OK');

    SET @Outputmessage = JSON_MODIFY(
      @Outputmessage,
      '$.result[0].output_json',
      JSON_QUERY(
        (
          SELECT
            S.sessionId,
            S.companyId,
            S.openedByUserId,
            S.openedAt,
            S.openingCash,
            S.openingNotes,
            S.autoClosed,
            @systemBalance AS systemBalance
          FROM dbo.cashRegisterSessions S
          WHERE S.sessionId = @openSessionId
          FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )
      )
    );

    GOTO ReturnResult;
  END;

  /* ============================================================
     ACTION 5 : LIST MOVEMENTS
     Required: companyId
     sessionId optional -> uses open session
     ONLY CURRENT MONTH
  ============================================================ */
  IF @action = 5
  BEGIN
    IF @companyId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'companyId is required');
      GOTO ReturnResult;
    END;

    IF @sessionId IS NULL 
      SET @sessionId = @openSessionId;

    IF @sessionId IS NULL
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'OK');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', '');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].output_json', NULL);
      GOTO ReturnResult;
    END;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @sessionId));
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'OK');

	SET @Outputmessage = JSON_MODIFY(
		@Outputmessage,
		'$.result[0].output_json',
		JSON_QUERY(
		  (
			SELECT
			  movementId, sessionId, companyId, userId,
			  movementType, amount, cashPaid, cashReturn,
			  incomeId, notes, createdAt
			FROM dbo.cashRegisterMovements
			WHERE sessionId = @sessionId
			  AND companyId = @companyId -- Bound to the session directly
			ORDER BY createdAt DESC
			FOR JSON PATH
		  )
		)
	  );

	GOTO ReturnResult;
  END;

  ------------------------------------------------------------
  -- Invalid action
  ------------------------------------------------------------
  SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
  SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid action. Use 1=OPEN, 2=CLOSE, 3=MOVEMENT, 4=GET_OPEN, 5=LIST_MOVEMENTS.');

  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 
      ROLLBACK;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
  END CATCH;

ReturnResult:
  SELECT
    JSON_VALUE(value, '$.value')       AS value,
    JSON_VALUE(value, '$.msg')         AS msg,
    JSON_VALUE(value, '$.error')       AS error,
    JSON_QUERY(value, '$.output_json') AS output_json
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_checkContact
IF OBJECT_ID(N'dbo.sp_checkContact', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_checkContact];
GO

CREATE PROC [dbo].[sp_checkContact]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @contact NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.checkContact[0].contact')

    -- ── 1. Find the client record ───────────────────────────────────────
    DECLARE
        @clientId   INT,
        @firstName  NVARCHAR(100),
        @lastName   NVARCHAR(100),
        @cellphone  NVARCHAR(20),
        @email      NVARCHAR(100),
        @companyId  INT,
        @qrBlobUrl  NVARCHAR(500);

    SELECT TOP 1
        @clientId  = c.clientId,
        @firstName = c.first_name,
        @lastName  = c.last_name,
        @cellphone = c.cellphone,
        @email     = c.email,
        @companyId = c.companyId,
        @qrBlobUrl = c.qrBlobUrl
    FROM dbo.clients c
    WHERE c.cellphone = @contact
       OR c.email     = @contact;

    -- No client found → check dbo.users directly before giving up. A user
    -- account with no linked client still means "this contact is taken".
    IF @clientId IS NULL
    BEGIN
        DECLARE @directUserId   INT,
                @directUserName NVARCHAR(100);

        SELECT TOP 1
            @directUserId   = u.userId,
            @directUserName = u.name
        FROM dbo.users u
        WHERE u.email = @contact
           OR u.cellphone = @contact;

        IF @directUserId IS NOT NULL
        BEGIN
            -- Registration wizard progress for this direct user account.
            DECLARE
                @dRegAppProfile     NVARCHAR(20),
                @dRegEnabledModules NVARCHAR(MAX),
                @dRegVerified       BIT,
                @dRegHasAccess      BIT = 0,
                @dRegCompanyId      INT,
                @dRegBranchId       INT,
                @dRegRoleCode       VARCHAR(50);

            SELECT
                @dRegAppProfile     = appProfile,
                @dRegEnabledModules = enabledModules,
                @dRegVerified       = identityVerified
            FROM dbo.users
            WHERE userId = @directUserId;

            SELECT TOP 1
                @dRegHasAccess = 1,
                @dRegCompanyId = companyId,
                @dRegBranchId  = branchId,
                @dRegRoleCode  = roleName
            FROM dbo.userCompanies
            WHERE userId = @directUserId;

            DECLARE @dRegComplete BIT =
                CASE WHEN @dRegAppProfile IS NOT NULL
                      AND ISNULL(@dRegVerified, 0)  = 1
                      AND ISNULL(@dRegHasAccess, 0) = 1
                     THEN 1 ELSE 0 END;

            SELECT (
                SELECT
                    1                AS found,
                    @directUserId    AS userId,
                    @directUserName  AS userName,
                    1                AS hasAccount,
                    CAST(CASE WHEN @dRegAppProfile IS NULL THEN 0 ELSE 1 END AS INT) AS stepProfile,
                    CAST(ISNULL(@dRegVerified, 0)  AS INT) AS stepVerify,
                    CAST(ISNULL(@dRegHasAccess, 0) AS INT) AS stepAccess,
                    CAST(@dRegComplete             AS INT) AS regComplete,
                    @dRegAppProfile                        AS appProfile,
                    JSON_QUERY(ISNULL(@dRegEnabledModules, '[]')) AS enabledModules,
                    @dRegCompanyId                         AS companyId,
                    @dRegBranchId                          AS branchId,
                    @dRegRoleCode                          AS roleCode
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            ) AS [jsonResult];
        END
        ELSE
        BEGIN
            SELECT '{"found":false}' AS [jsonResult];
        END
        RETURN;
    END

    -- ── 2. Check if a user account is linked (by email OR phone) ────────
    DECLARE
        @userId    INT,
        @userName  NVARCHAR(100),
        @hasAccount BIT = 0;

    SELECT TOP 1
        @userId   = u.userId,
        @userName = u.name
    FROM dbo.users u
    WHERE (u.email    = @email    AND @email    IS NOT NULL AND @email    <> '')
       OR (u.cellphone = @cellphone AND @cellphone IS NOT NULL AND @cellphone <> '');

    IF @userId IS NOT NULL
        SET @hasAccount = 1;

    -- ── 2b. Registration wizard progress (Perfil/Verificar/Acceso) ──────
    DECLARE
        @regAppProfile     NVARCHAR(20),
        @regEnabledModules NVARCHAR(MAX),
        @regVerified       BIT,
        @regHasAccess      BIT = 0,
        @regCompanyId      INT,
        @regBranchId       INT,
        @regRoleCode       VARCHAR(50);

    IF @userId IS NOT NULL
    BEGIN
        SELECT
            @regAppProfile     = appProfile,
            @regEnabledModules = enabledModules,
            @regVerified       = identityVerified
        FROM dbo.users
        WHERE userId = @userId;

        SELECT TOP 1
            @regHasAccess = 1,
            @regCompanyId = companyId,
            @regBranchId  = branchId,
            @regRoleCode  = roleName
        FROM dbo.userCompanies
        WHERE userId = @userId;
    END

    DECLARE @regComplete BIT =
        CASE WHEN @hasAccount = 1
              AND @regAppProfile IS NOT NULL
              AND ISNULL(@regVerified, 0)  = 1
              AND ISNULL(@regHasAccess, 0) = 1
             THEN 1 ELSE 0 END;

    -- ── 3. Loan completion steps ─────────────────────────────────────────
    -- Step 1: general info (client exists)         → always 1
    -- Step 2: QR saved to blob                     → qrBlobUrl not null
    -- Step 3: payment account (Stripe)             → checked on frontend
    -- Step 4: biometric verified                   → ClientFaceRecognitions.is_verified
    -- Step 5: contract accepted                    → ClientFaceRecognitions.contract_accepted
    -- Step 6: pagaré accepted                      → ClientFaceRecognitions.pagare_accepted

    DECLARE
        @isVerified       BIT = 0,
        @contractAccepted BIT = 0,
        @pagareAccepted   BIT = 0;

    SELECT TOP 1
        @isVerified       = ISNULL(cfr.is_verified, 0),
        @contractAccepted = ISNULL(cfr.contract_accepted, 0),
        @pagareAccepted   = ISNULL(cfr.pagare_accepted, 0)
    FROM dbo.ClientFaceRecognitions cfr
    WHERE cfr.companyId = @companyId
      AND cfr.clientId  = @clientId
    ORDER BY cfr.created_At DESC;

    DECLARE @stepsCompleted INT =
        1                                              -- general info
      + (CASE WHEN @qrBlobUrl  IS NOT NULL THEN 1 ELSE 0 END)
      + 0                                              -- Stripe: checked frontend
      + (CASE WHEN @isVerified       = 1 THEN 1 ELSE 0 END)
      + (CASE WHEN @contractAccepted = 1 THEN 1 ELSE 0 END)
      + (CASE WHEN @pagareAccepted   = 1 THEN 1 ELSE 0 END);

    DECLARE @completionPct INT = (@stepsCompleted * 100) / 6;

    -- ── 4. Return JSON ───────────────────────────────────────────────────
    SELECT (
        SELECT
            1                  AS found,
            @clientId          AS clientId,
            @firstName         AS firstName,
            @lastName          AS lastName,
            @cellphone         AS cellphone,
            @email             AS email,
            @companyId         AS companyId,
            @userId            AS userId,
            @userName          AS userName,
            CAST(@hasAccount AS INT) AS hasAccount,   -- 1 or 0, never NULL
            @completionPct     AS completionPct,
            @stepsCompleted    AS stepsCompleted,
            -- Individual step flags for detailed display
            1                  AS stepGeneralInfo,
            CAST(CASE WHEN @qrBlobUrl IS NOT NULL THEN 1 ELSE 0 END AS INT) AS stepQr,
            CAST(@isVerified       AS INT) AS stepBiometric,
            CAST(@contractAccepted AS INT) AS stepContract,
            CAST(@pagareAccepted   AS INT) AS stepPagare,
            -- Registration wizard progress (Cuenta/Perfil/Verificar/Acceso)
            CAST(CASE WHEN @regAppProfile IS NULL THEN 0 ELSE 1 END AS INT) AS stepProfile,
            CAST(ISNULL(@regVerified, 0)  AS INT) AS stepVerify,
            CAST(ISNULL(@regHasAccess, 0) AS INT) AS stepAccess,
            CAST(@regComplete             AS INT) AS regComplete,
            @regAppProfile                        AS appProfile,
            JSON_QUERY(ISNULL(@regEnabledModules, '[]')) AS enabledModules,
            @regBranchId                           AS branchId,
            @regRoleCode                           AS roleCode
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS [jsonResult];

    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

-- dbo.sp_checkUsername
IF OBJECT_ID(N'dbo.sp_checkUsername', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_checkUsername];
GO

CREATE PROC [dbo].[sp_checkUsername]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @takenJson NVARCHAR(MAX) = (
        SELECT u.[name]
        FROM dbo.users u
        INNER JOIN OPENJSON(@pjsonfile, '$.checkUsername[0].usernames') c
            ON u.[name] = c.[value]
        FOR JSON PATH
    );

    SELECT '{"taken":' + ISNULL(@takenJson, '[]') + '}' AS [jsonResult];

    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

-- dbo.sp_checks
IF OBJECT_ID(N'dbo.sp_checks', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_checks];
GO
CREATE PROC [dbo].[sp_checks] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
		"checks": [
			{
				"checkId": 1,
				"latitude": "29.0078375",
				"longitude": "-110.9272193",
				"description": "Avenida Savia, 83296, Hermosillo, Sonora",
				"datetimelocal": "2024-06-25T15:56:08",
				"checkTypeId": 1,
				"userId": 1,
				"street": "Avenida Savia",
				"postalCode": "83296",
				"city": "Hermosillo",
				"state": "Sonora",
				"createdAt": "2024-06-25T22:27:04.492Z",
				"updatedAt": "NULL",
				"action": "1"
			}
		]
	}';

	*/

    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.checks'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the checks
            INSERT INTO [dbo].[checks] 
                ([latitude], [longitude], [description], [datetimelocal], [checkTypeId], 
                 [userId], [street], [postalCode], [city], [state], [createdAt], [updatedAt])
            SELECT
                JSON_VALUE(value, '$.latitude'),
                JSON_VALUE(value, '$.longitude'),
                JSON_VALUE(value, '$.description'),
                CONVERT(datetime, JSON_VALUE(value, '$.datetimelocal')),
                JSON_VALUE(value, '$.checkTypeId'),
                JSON_VALUE(value, '$.userId'),
                JSON_VALUE(value, '$.street'),
                JSON_VALUE(value, '$.postalCode'),
                JSON_VALUE(value, '$.city'),
                JSON_VALUE(value, '$.state'),
                GETDATE(),
                NULL
            FROM OPENJSON(@pjsonfile, '$.checks');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the checks
            UPDATE c
            SET 
                c.[latitude] = JSON_VALUE(j.value, '$.latitude'),
                c.[longitude] = JSON_VALUE(j.value, '$.longitude'),
                c.[description] = JSON_VALUE(j.value, '$.description'),
                c.[datetimelocal] = CONVERT(datetime, JSON_VALUE(j.value, '$.datetimelocal')),
                c.[checkTypeId] = JSON_VALUE(j.value, '$.checkTypeId'),
                c.[userId] = JSON_VALUE(j.value, '$.userId'),
                c.[street] = JSON_VALUE(j.value, '$.street'),
                c.[postalCode] = JSON_VALUE(j.value, '$.postalCode'),
                c.[city] = JSON_VALUE(j.value, '$.city'),
                c.[state] = JSON_VALUE(j.value, '$.state'),
                c.[updatedAt] = GETDATE()
            FROM 
                [dbo].[checks] c
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.checks') j
                ON c.[checkId] = JSON_VALUE(j.value, '$.checkId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the checks
            DELETE FROM [dbo].[checks]
            WHERE [checkId] IN (SELECT JSON_VALUE(value, '$.checkId') FROM OPENJSON(@pjsonfile, '$.checks'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_checks_all
IF OBJECT_ID(N'dbo.sp_checks_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_checks_all];
GO
CREATE PROC [dbo].[sp_checks_all]
AS
SET NOCOUNT ON

BEGIN

    SELECT
        [checkId]
        ,[latitude]
        ,[longitude]
        ,ISNULL([description],'') AS description
        ,[datetimelocal]
        ,[checkTypeId]
        ,[userId]
        ,ISNULL([street],'') AS street
        ,ISNULL([postalCode],'') AS postalCode
        ,ISNULL([city],'') AS city
        ,ISNULL([state],'') AS state
        ,[createdAt]
        ,ISNULL([updatedAt],'') AS updatedAt
    FROM [dbo].[checks]
    FOR JSON AUTO, ROOT('checks');

END
GO

-- dbo.sp_checks_one
IF OBJECT_ID(N'dbo.sp_checks_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_checks_one];
GO

CREATE PROC [dbo].[sp_checks_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "checks": [
        {
        "checkId": "1"
        }
     ]   
    }'
    */

    DECLARE @checkId INT;

    SET @checkId = CAST((SELECT JSON_VALUE(value, '$.checkId') FROM OPENJSON(@pjsonfile, '$.checks')) AS INT);

    SELECT 
        [checkId]
        ,[latitude]
        ,[longitude]
        ,ISNULL([description],'') AS description
        ,[datetimelocal]
        ,[checkTypeId]
        ,[userId]
        ,ISNULL([street],'') AS street
        ,ISNULL([postalCode],'') AS postalCode
        ,ISNULL([city],'') AS city
        ,ISNULL([state],'') AS state
        ,[createdAt]
        ,ISNULL([updatedAt],'') AS updatedAt
    FROM 
        [montanogilberto_smartloans].[dbo].[checks]
    WHERE
        checkId = @checkId
    FOR JSON AUTO, ROOT('checks');

END
GO

-- dbo.sp_checks_today
IF OBJECT_ID(N'dbo.sp_checks_today', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_checks_today];
GO
CREATE PROC [dbo].[sp_checks_today]
AS
SET NOCOUNT ON

BEGIN

    SELECT 
        [checkId]
        ,[latitude]
        ,[longitude]
        ,ISNULL([description],'') AS description
        ,[datetimelocal]
        ,[checkTypeId]
        ,[userId]
        ,ISNULL([street],'') AS street
        ,ISNULL([postalCode],'') AS postalCode
        ,ISNULL([city],'') AS city
        ,ISNULL([state],'') AS state
        ,[createdAt]
        ,ISNULL([updatedAt],'') AS updatedAt
    FROM 
        [montanogilberto_smartloans].[dbo].[checks]
    WHERE
        CAST([datetimelocal] AS DATE) = CAST(GETDATE() AS DATE)
    FOR JSON AUTO, ROOT('checks');

END
GO

-- dbo.sp_clientDashboards
IF OBJECT_ID(N'dbo.sp_clientDashboards', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientDashboards];
GO

CREATE PROCEDURE [dbo].[sp_clientDashboards]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action           INT           = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].action')
        DECLARE @clientDashboardId INT          = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].clientDashboardId')
        DECLARE @companyId        INT           = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].companyId')
        DECLARE @clientId         INT           = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].clientId')
        DECLARE @availableCredit  DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].availableCredit')
        DECLARE @activeLoanBalance DECIMAL(18,2)= JSON_VALUE(@pjsonfile, '$.clientDashboards[0].activeLoanBalance')
        DECLARE @nextPaymentAmount DECIMAL(18,2)= JSON_VALUE(@pjsonfile, '$.clientDashboards[0].nextPaymentAmount')
        DECLARE @nextPaymentDate  DATETIME2     = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].nextPaymentDate')
        DECLARE @activityDate     DATETIME2     = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].activityDate')
        DECLARE @activityType     NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].activityType')
        DECLARE @description      NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].description')
        DECLARE @amount           DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].amount')
        DECLARE @loanNumber       NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].loanNumber')
        DECLARE @loanAmount       DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].loanAmount')
        DECLARE @remainingBalance DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].remainingBalance')
        DECLARE @status           NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].status')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[clientDashboards]
                (companyId, clientId, availableCredit, activeLoanBalance, nextPaymentAmount,
                 nextPaymentDate, activityDate, activityType, description, amount,
                 loanNumber, loanAmount, remainingBalance, status)
            VALUES
                (@companyId, @clientId, @availableCredit, @activeLoanBalance, @nextPaymentAmount,
                 @nextPaymentDate, @activityDate, @activityType, @description, @amount,
                 @loanNumber, @loanAmount, @remainingBalance, @status)

            SELECT (SELECT TOP 1 clientDashboardId, companyId, clientId, availableCredit,
                           activeLoanBalance, nextPaymentAmount,
                           CONVERT(NVARCHAR, nextPaymentDate, 127) AS nextPaymentDate,
                           CONVERT(NVARCHAR, activityDate, 127) AS activityDate,
                           activityType, description, amount, loanNumber, loanAmount,
                           remainingBalance, status,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[clientDashboards]
                    WHERE clientDashboardId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE
        BEGIN
            UPDATE [dbo].[clientDashboards]
            SET availableCredit   = ISNULL(@availableCredit, availableCredit),
                activeLoanBalance = ISNULL(@activeLoanBalance, activeLoanBalance),
                nextPaymentAmount = ISNULL(@nextPaymentAmount, nextPaymentAmount),
                nextPaymentDate   = ISNULL(@nextPaymentDate, nextPaymentDate),
                activityDate      = ISNULL(@activityDate, activityDate),
                activityType      = ISNULL(@activityType, activityType),
                description       = ISNULL(@description, description),
                amount            = ISNULL(@amount, amount),
                loanNumber        = ISNULL(@loanNumber, loanNumber),
                loanAmount        = ISNULL(@loanAmount, loanAmount),
                remainingBalance  = ISNULL(@remainingBalance, remainingBalance),
                status            = ISNULL(@status, status),
                updated_at        = GETUTCDATE()
            WHERE clientDashboardId = @clientDashboardId AND companyId = @companyId

            SELECT '{"message":"updated","clientDashboardId":' + CAST(@clientDashboardId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[clientDashboards]
            WHERE clientDashboardId = @clientDashboardId AND companyId = @companyId

            SELECT '{"message":"deleted","clientDashboardId":' + CAST(@clientDashboardId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_clientDashboards_all
IF OBJECT_ID(N'dbo.sp_clientDashboards_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientDashboards_all];
GO

CREATE PROCEDURE [dbo].[sp_clientDashboards_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].clientId')

        SELECT ISNULL(
            (SELECT clientDashboardId, companyId, clientId, availableCredit,
                    activeLoanBalance, nextPaymentAmount,
                    CONVERT(NVARCHAR, nextPaymentDate, 127) AS nextPaymentDate,
                    CONVERT(NVARCHAR, activityDate, 127) AS activityDate,
                    activityType, description, amount, loanNumber, loanAmount,
                    remainingBalance, status,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM [dbo].[clientDashboards]
             WHERE companyId = @companyId
               AND (@clientId IS NULL OR clientId = @clientId)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('clientDashboards')),
            '{"clientDashboards":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_clientFaceRecognitions
IF OBJECT_ID(N'dbo.sp_clientFaceRecognitions', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientFaceRecognitions];
GO
CREATE   PROC [dbo].[sp_clientFaceRecognitions] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @Outputmessage NVARCHAR(MAX) = '{
      "result": [
        { "value": "", "msg": "", "error": "" }
      ]
    }';
    DECLARE @action INT;
    DECLARE @resultId INT;

    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions')
    );

    DECLARE @payload TABLE (
        clientFaceRecognitionId      INT NULL,
        companyId                    INT NULL,
        clientId                     INT NULL,
        document_type                NVARCHAR(50) NULL,
        id_front_image_blob_url      NVARCHAR(2048) NULL,
        id_back_image_blob_url       NVARCHAR(2048) NULL,
        azure_session_id             UNIQUEIDENTIFIER NULL,
        client_selfie_blob_url       NVARCHAR(2048) NULL,
        confidence_score             DECIMAL(5,4) NULL,
        is_verified                  BIT NULL,

        nombre                       NVARCHAR(255) NULL,
        domicilio                    NVARCHAR(500) NULL,
        curp                         NVARCHAR(18) NULL,
        clave_elector                NVARCHAR(20) NULL,
        rfc                          NVARCHAR(13) NULL,
        fecha_nacimiento             NVARCHAR(10) NULL,

        contract_accepted            BIT NULL,
        contract_pdf_blob_url        NVARCHAR(2048) NULL,
        contract_accepted_at         DATETIME2(7) NULL,

        pagare_accepted              BIT NULL,
        pagare_pdf_blob_url          NVARCHAR(2048) NULL,
        pagare_accepted_at           DATETIME2(7) NULL,
        has_physical_pagare          BIT NULL,
        physical_pagare_verified_at  DATETIME2(7) NULL,

        -- Presence capture (video + GPS), added for location/audit evidence
        presence_video_blob_url            NVARCHAR(2048) NULL,
        presence_latitude                  DECIMAL(9,6) NULL,
        presence_longitude                 DECIMAL(9,6) NULL,
        presence_location_accuracy_meters  DECIMAL(9,2) NULL,
        presence_captured_at               DATETIME2(7) NULL,

        -- Signature match (ID-crop vs contract signature)
        id_signature_crop_blob_url    NVARCHAR(2048) NULL,
        contract_signature_blob_url   NVARCHAR(2048) NULL,
        signature_match_score         DECIMAL(5,2) NULL,
        signature_match_passed        BIT NULL,
        signature_matched_at          DATETIME2(7) NULL,

        userId                       INT NULL -- Captures the operator/creator identity context
    );

    INSERT INTO @payload (
        clientFaceRecognitionId,
        companyId,
        clientId,
        document_type,
        id_front_image_blob_url,
        id_back_image_blob_url,
        azure_session_id,
        client_selfie_blob_url,
        confidence_score,
        is_verified,
        nombre,
        domicilio,
        curp,
        clave_elector,
        rfc,
        fecha_nacimiento,
        contract_accepted,
        contract_pdf_blob_url,
        contract_accepted_at,
        pagare_accepted,
        pagare_pdf_blob_url,
        pagare_accepted_at,
        has_physical_pagare,
        physical_pagare_verified_at,
        presence_video_blob_url,
        presence_latitude,
        presence_longitude,
        presence_location_accuracy_meters,
        presence_captured_at,
        id_signature_crop_blob_url,
        contract_signature_blob_url,
        signature_match_score,
        signature_match_passed,
        signature_matched_at,
        userId
    )
    SELECT
        TRY_CONVERT(INT, JSON_VALUE(value, '$.clientFaceRecognitionId')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
        JSON_VALUE(value, '$.documentType'),
        JSON_VALUE(value, '$.idFrontImageBlobUrl'),
        JSON_VALUE(value, '$.idBackImageBlobUrl'),
        TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.azureSessionId')),
        JSON_VALUE(value, '$.clientSelfieBlobUrl'),
        TRY_CONVERT(DECIMAL(5,4), JSON_VALUE(value, '$.confidenceScore')),
        TRY_CONVERT(BIT, JSON_VALUE(value, '$.isVerified')),
        JSON_VALUE(value, '$.nombre'),
        JSON_VALUE(value, '$.domicilio'),
        JSON_VALUE(value, '$.curp'),
        JSON_VALUE(value, '$.claveElector'),
        JSON_VALUE(value, '$.rfc'),
        JSON_VALUE(value, '$.fechaNacimiento'),

        TRY_CONVERT(BIT, JSON_VALUE(value, '$.contractAccepted')),
        JSON_VALUE(value, '$.contractPdfBlobUrl'),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.contractAcceptedAt')),

        TRY_CONVERT(BIT, JSON_VALUE(value, '$.pagareAccepted')),
        JSON_VALUE(value, '$.pagarePdfBlobUrl'),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.pagareAcceptedAt')),
        TRY_CONVERT(BIT, JSON_VALUE(value, '$.hasPhysicalPagare')),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.physicalPagareVerifiedAt')),

        JSON_VALUE(value, '$.presenceVideoBlobUrl'),
        TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.presenceLatitude')),
        TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.presenceLongitude')),
        TRY_CONVERT(DECIMAL(9,2), JSON_VALUE(value, '$.presenceLocationAccuracyMeters')),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.presenceCapturedAt')),

        JSON_VALUE(value, '$.idSignatureCropBlobUrl'),
        JSON_VALUE(value, '$.contractSignatureBlobUrl'),
        TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(value, '$.signatureMatchScore')),
        TRY_CONVERT(BIT, JSON_VALUE(value, '$.signatureMatchPassed')),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.signatureMatchedAt')),

        TRY_CONVERT(INT, JSON_VALUE(value, '$.userId')) -- Maps to auditing tracking values
    FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions');

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1 -- INSERT
        BEGIN
            INSERT INTO dbo.ClientFaceRecognitions (
                companyId,
                clientId,
                document_type,
                id_front_image_blob_url,
                id_back_image_blob_url,
                azure_session_id,
                client_selfie_blob_url,
                confidence_score,
                is_verified,
                nombre,
                domicilio,
                curp,
                clave_elector,
                rfc,
                fecha_nacimiento,
                contract_accepted,
                contract_pdf_blob_url,
                contract_accepted_at,
                accepted_at,
                pagare_accepted,
                pagare_pdf_blob_url,
                pagare_accepted_at,
                has_physical_pagare,
                physical_pagare_verified_at,
                presence_video_blob_url,
                presence_latitude,
                presence_longitude,
                presence_location_accuracy_meters,
                presence_captured_at,
                id_signature_crop_blob_url,
                contract_signature_blob_url,
                signature_match_score,
                signature_match_passed,
                signature_matched_at,
                is_active,
                created_by,
                created_At
            )
            SELECT
                p.companyId,
                p.clientId,
                p.document_type,
                p.id_front_image_blob_url,
                p.id_back_image_blob_url,
                p.azure_session_id,
                p.client_selfie_blob_url,
                p.confidence_score,
                p.is_verified,
                p.nombre,
                p.domicilio,
                p.curp,
                p.clave_elector,
                p.rfc,
                p.fecha_nacimiento,
                p.contract_accepted,
                p.contract_pdf_blob_url,
                p.contract_accepted_at,
                -- Legacy NOT NULL column, superseded by contract_accepted_at
                -- but never dropped. Mirror it here so inserts don't fail.
                ISNULL(p.contract_accepted_at, SYSUTCDATETIME()),
                p.pagare_accepted,
                p.pagare_pdf_blob_url,
                p.pagare_accepted_at,
                ISNULL(p.has_physical_pagare, 0),
                p.physical_pagare_verified_at,
                p.presence_video_blob_url,
                p.presence_latitude,
                p.presence_longitude,
                p.presence_location_accuracy_meters,
                p.presence_captured_at,
                p.id_signature_crop_blob_url,
                p.contract_signature_blob_url,
                p.signature_match_score,
                p.signature_match_passed,
                p.signature_matched_at,
                1, -- Defaulting row state as active
                ISNULL(p.userId, 1), -- fallback safely to system user seed
                SYSUTCDATETIME()
            FROM @payload p;

            -- Frontend needs the new row's ID back so later captures (back
            -- image, selfie, confidence score, contract) update this same
            -- row instead of silently no-op'ing or creating duplicates.
            SET @resultId = SCOPE_IDENTITY();
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(20), @resultId));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2 -- UPDATE
        BEGIN
            -- COALESCE against the existing row so a partial patch (e.g.
            -- just { clientSelfieBlobUrl } from an incremental capture step)
            -- only touches the fields it actually sent, instead of nulling
            -- out every other NOT NULL column with the JSON's absent keys.
            UPDATE cfr
            SET
                cfr.companyId                  = COALESCE(p.companyId, cfr.companyId),
                cfr.clientId                   = COALESCE(p.clientId, cfr.clientId),
                cfr.document_type              = COALESCE(p.document_type, cfr.document_type),
                cfr.id_front_image_blob_url    = COALESCE(p.id_front_image_blob_url, cfr.id_front_image_blob_url),
                cfr.id_back_image_blob_url     = COALESCE(p.id_back_image_blob_url, cfr.id_back_image_blob_url),
                cfr.azure_session_id           = COALESCE(p.azure_session_id, cfr.azure_session_id),
                cfr.client_selfie_blob_url     = COALESCE(p.client_selfie_blob_url, cfr.client_selfie_blob_url),
                cfr.confidence_score           = COALESCE(p.confidence_score, cfr.confidence_score),
                cfr.is_verified                = COALESCE(p.is_verified, cfr.is_verified),

                cfr.nombre                     = COALESCE(p.nombre, cfr.nombre),
                cfr.domicilio                  = COALESCE(p.domicilio, cfr.domicilio),
                cfr.curp                       = COALESCE(p.curp, cfr.curp),
                cfr.clave_elector              = COALESCE(p.clave_elector, cfr.clave_elector),
                cfr.rfc                        = COALESCE(p.rfc, cfr.rfc),
                cfr.fecha_nacimiento           = COALESCE(p.fecha_nacimiento, cfr.fecha_nacimiento),

                cfr.contract_accepted          = COALESCE(p.contract_accepted, cfr.contract_accepted),
                cfr.contract_pdf_blob_url      = COALESCE(p.contract_pdf_blob_url, cfr.contract_pdf_blob_url),
                cfr.contract_accepted_at       = COALESCE(p.contract_accepted_at, cfr.contract_accepted_at),

                cfr.pagare_accepted            = COALESCE(p.pagare_accepted, cfr.pagare_accepted),
                cfr.pagare_pdf_blob_url        = COALESCE(p.pagare_pdf_blob_url, cfr.pagare_pdf_blob_url),
                cfr.pagare_accepted_at         = COALESCE(p.pagare_accepted_at, cfr.pagare_accepted_at),
                cfr.has_physical_pagare        = COALESCE(p.has_physical_pagare, cfr.has_physical_pagare),
                cfr.physical_pagare_verified_at = COALESCE(p.physical_pagare_verified_at, cfr.physical_pagare_verified_at),

                cfr.presence_video_blob_url            = COALESCE(p.presence_video_blob_url, cfr.presence_video_blob_url),
                cfr.presence_latitude                  = COALESCE(p.presence_latitude, cfr.presence_latitude),
                cfr.presence_longitude                 = COALESCE(p.presence_longitude, cfr.presence_longitude),
                cfr.presence_location_accuracy_meters  = COALESCE(p.presence_location_accuracy_meters, cfr.presence_location_accuracy_meters),
                cfr.presence_captured_at               = COALESCE(p.presence_captured_at, cfr.presence_captured_at),

                cfr.id_signature_crop_blob_url  = COALESCE(p.id_signature_crop_blob_url, cfr.id_signature_crop_blob_url),
                cfr.contract_signature_blob_url = COALESCE(p.contract_signature_blob_url, cfr.contract_signature_blob_url),
                cfr.signature_match_score       = COALESCE(p.signature_match_score, cfr.signature_match_score),
                cfr.signature_match_passed      = COALESCE(p.signature_match_passed, cfr.signature_match_passed),
                cfr.signature_matched_at        = COALESCE(p.signature_matched_at, cfr.signature_matched_at),

                cfr.updated_by                 = COALESCE(p.userId, cfr.updated_by),
                cfr.updated_at                 = SYSUTCDATETIME()
            FROM dbo.ClientFaceRecognitions cfr
            INNER JOIN @payload p ON cfr.clientFaceRecognitionId = p.clientFaceRecognitionId;

            SELECT TOP 1 @resultId = clientFaceRecognitionId FROM @payload;
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(20), @resultId));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3 -- DELETE
        BEGIN
            -- Hard delete logic retained from your existing layout structure
            DELETE cfr
            FROM dbo.ClientFaceRecognitions cfr
            INNER JOIN @payload p ON cfr.clientFaceRecognitionId = p.clientFaceRecognitionId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid action specified.');
        END

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH;

Finish:
    SELECT
        JSON_VALUE(value,'$.value') AS value,
        JSON_VALUE(value,'$.msg')   AS msg,
        JSON_VALUE(value,'$.error') AS error
    FROM OPENJSON(@Outputmessage,'$.result');
END;
GO

-- dbo.sp_clientFaceRecognitions_all
IF OBJECT_ID(N'dbo.sp_clientFaceRecognitions_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientFaceRecognitions_all];
GO
CREATE   PROC [dbo].[sp_clientFaceRecognitions_all] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT;
    SET @companyId = TRY_CONVERT(INT,
        (SELECT TOP 1 JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions'))
    );

    SELECT
        [clientFaceRecognitionId],
        ISNULL([companyId], 0)                             AS companyId,
        ISNULL([clientId], 0)                              AS clientId,
        ISNULL([document_type], '')                        AS documentType,
        ISNULL([id_front_image_blob_url], '')              AS idFrontImageBlobUrl,
        ISNULL([id_back_image_blob_url], '')               AS idBackImageBlobUrl,
        [azure_session_id]                                 AS azureSessionId,
        ISNULL([client_selfie_blob_url], '')               AS clientSelfieBlobUrl,
        ISNULL([confidence_score], 0.0000)                 AS confidenceScore,
        ISNULL([is_verified], 0)                           AS isVerified,

        -- Identity fields extracted from the ID (human-reviewed, may be blank)
        ISNULL([nombre], '')                                AS nombre,
        ISNULL([domicilio], '')                             AS domicilio,
        ISNULL([curp], '')                                  AS curp,
        ISNULL([clave_elector], '')                         AS claveElector,
        ISNULL([rfc], '')                                   AS rfc,
        ISNULL([fecha_nacimiento], '')                      AS fechaNacimiento,

        -- Legal Contract Metadata
        ISNULL([contract_accepted], 0)                     AS contractAccepted,
        ISNULL([contract_pdf_blob_url], '')                AS contractPdfBlobUrl,
        ISNULL(CONVERT(VARCHAR(30), [contract_accepted_at], 126), '') AS contractAcceptedAt,

        -- Legal Pagaré Metadata
        ISNULL([pagare_accepted], 0)                       AS pagareAccepted,
        ISNULL([pagare_pdf_blob_url], '')                  AS pagarePdfBlobUrl,
        ISNULL(CONVERT(VARCHAR(30), [pagare_accepted_at], 126), '')   AS pagareAcceptedAt,
        ISNULL([has_physical_pagare], 0)                   AS hasPhysicalPagare,
        ISNULL(CONVERT(VARCHAR(30), [physical_pagare_verified_at], 126), '') AS physicalPagareVerifiedAt,

        -- Presence capture (video + GPS)
        ISNULL([presence_video_blob_url], '')              AS presenceVideoBlobUrl,
        [presence_latitude]                                AS presenceLatitude,
        [presence_longitude]                                AS presenceLongitude,
        [presence_location_accuracy_meters]                AS presenceLocationAccuracyMeters,
        ISNULL(CONVERT(VARCHAR(30), [presence_captured_at], 126), '') AS presenceCapturedAt,

        -- Signature match
        ISNULL([id_signature_crop_blob_url], '')            AS idSignatureCropBlobUrl,
        ISNULL([contract_signature_blob_url], '')           AS contractSignatureBlobUrl,
        [signature_match_score]                             AS signatureMatchScore,
        [signature_match_passed]                            AS signatureMatchPassed,
        ISNULL(CONVERT(VARCHAR(30), [signature_matched_at], 126), '') AS signatureMatchedAt,

        -- System Audit Columns
        ISNULL([is_active], 1)                             AS isActive,
        ISNULL([created_by], 1)                            AS createdBy,
        ISNULL(CONVERT(VARCHAR(30), [created_At], 126), '') AS createdAt,
        [updated_by]                                       AS updatedBy,
        ISNULL(CONVERT(VARCHAR(30), [updated_at], 126), '') AS updatedAt
    FROM dbo.ClientFaceRecognitions
    WHERE companyId = @companyId
      AND [is_active] = 1 -- Ensures soft-deleted rows stay out of client listings
    FOR JSON AUTO, ROOT('clientFaceRecognitions');
END;
GO

-- dbo.sp_clientFaceRecognitions_one
IF OBJECT_ID(N'dbo.sp_clientFaceRecognitions_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientFaceRecognitions_one];
GO
-- NOTE: sp_clientFaceRecognitions_one has a pre-existing bug in its ID-
-- extraction logic (unrelated to this migration, confirmed unreachable by
-- any real caller — even its own documented example payload in
-- docs_description/clientFaceRecognitions_one.txt hits the same parse
-- error). Not fixed here since it's out of scope for this change and has
-- no current callers; flagging for whoever picks it up next.
CREATE   PROC [dbo].[sp_clientFaceRecognitions_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @clientFaceRecognitionId INT;
    SET @clientFaceRecognitionId = CAST(
        (SELECT TOP 1 JSON_VALUE(value, '$.clientFaceRecognitions')
         FROM OPENJSON(@pjsonfile)) AS INT
    );

    SELECT
        [clientFaceRecognitionId],
        ISNULL([companyId], 0)                             AS companyId,
        ISNULL([clientId], 0)                              AS clientId,
        ISNULL([document_type], '')                        AS documentType,
        ISNULL([id_front_image_blob_url], '')              AS idFrontImageBlobUrl,
        ISNULL([id_back_image_blob_url], '')               AS idBackImageBlobUrl,
        [azure_session_id]                                 AS azureSessionId,
        ISNULL([client_selfie_blob_url], '')               AS clientSelfieBlobUrl,
        ISNULL([confidence_score], 0.0000)                 AS confidenceScore,
        ISNULL([is_verified], 0)                           AS isVerified,

        -- Identity fields extracted from the ID (human-reviewed, may be blank)
        ISNULL([nombre], '')                                AS nombre,
        ISNULL([domicilio], '')                             AS domicilio,
        ISNULL([curp], '')                                  AS curp,
        ISNULL([clave_elector], '')                         AS claveElector,
        ISNULL([rfc], '')                                   AS rfc,
        ISNULL([fecha_nacimiento], '')                      AS fechaNacimiento,

        -- Legal Contract Metadata
        ISNULL([contract_accepted], 0)                     AS contractAccepted,
        ISNULL([contract_pdf_blob_url], '')                AS contractPdfBlobUrl,
        ISNULL(CONVERT(VARCHAR(30), [contract_accepted_at], 126), '') AS contractAcceptedAt,

        -- Legal Pagaré Metadata
        ISNULL([pagare_accepted], 0)                       AS pagareAccepted,
        ISNULL([pagare_pdf_blob_url], '')                  AS pagarePdfBlobUrl,
        ISNULL(CONVERT(VARCHAR(30), [pagare_accepted_at], 126), '')   AS pagareAcceptedAt,
        ISNULL([has_physical_pagare], 0)                   AS hasPhysicalPagare,
        ISNULL(CONVERT(VARCHAR(30), [physical_pagare_verified_at], 126), '') AS physicalPagareVerifiedAt,

        -- Presence capture (video + GPS)
        ISNULL([presence_video_blob_url], '')              AS presenceVideoBlobUrl,
        [presence_latitude]                                AS presenceLatitude,
        [presence_longitude]                                AS presenceLongitude,
        [presence_location_accuracy_meters]                AS presenceLocationAccuracyMeters,
        ISNULL(CONVERT(VARCHAR(30), [presence_captured_at], 126), '') AS presenceCapturedAt,

        -- Signature match
        ISNULL([id_signature_crop_blob_url], '')            AS idSignatureCropBlobUrl,
        ISNULL([contract_signature_blob_url], '')           AS contractSignatureBlobUrl,
        [signature_match_score]                             AS signatureMatchScore,
        [signature_match_passed]                            AS signatureMatchPassed,
        ISNULL(CONVERT(VARCHAR(30), [signature_matched_at], 126), '') AS signatureMatchedAt,

        -- System Audit Columns
        ISNULL([is_active], 1)                             AS isActive,
        ISNULL([created_by], 1)                            AS createdBy,
        ISNULL(CONVERT(VARCHAR(30), [created_At], 126), '') AS createdAt,
        [updated_by]                                       AS updatedBy,
        ISNULL(CONVERT(VARCHAR(30), [updated_at], 126), '') AS updatedAt
    FROM dbo.ClientFaceRecognitions
    WHERE clientFaceRecognitionId = @clientFaceRecognitionId
    FOR JSON AUTO, ROOT('clientFaceRecognitions');
END;
GO

-- dbo.sp_clientFollowUps
IF OBJECT_ID(N'dbo.sp_clientFollowUps', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientFollowUps];
GO

CREATE PROCEDURE [dbo].[sp_clientFollowUps]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action     INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].action')
        DECLARE @followUpId INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].followUpId')
        DECLARE @clientId   INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].clientId')
        DECLARE @companyId  INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].companyId')
        DECLARE @riskStatus NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].riskStatus'), 'on_track')
        DECLARE @reason     NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].reason')
        DECLARE @note       NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].note')
        DECLARE @assignedTo INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].assignedTo')
        DECLARE @dueDate    DATETIME2     = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].dueDate')
        DECLARE @resolvedAt DATETIME2     = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].resolvedAt')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[clientFollowUps]
                (clientId, companyId, riskStatus, reason, note, assignedTo, dueDate)
            VALUES
                (@clientId, @companyId, @riskStatus, @reason, @note, @assignedTo, @dueDate)

            SELECT (SELECT TOP 1 followUpId, clientId, companyId, riskStatus,
                           reason, note, assignedTo,
                           CONVERT(NVARCHAR, dueDate, 127)    AS dueDate,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[clientFollowUps]
                    WHERE followUpId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (change risk / resolve / reassign)
        BEGIN
            UPDATE [dbo].[clientFollowUps]
            SET riskStatus  = ISNULL(@riskStatus, riskStatus),
                reason      = ISNULL(@reason, reason),
                note        = ISNULL(@note, note),
                assignedTo  = ISNULL(@assignedTo, assignedTo),
                dueDate     = ISNULL(@dueDate, dueDate),
                resolvedAt  = ISNULL(@resolvedAt, resolvedAt),
                updated_at  = GETUTCDATE()
            WHERE followUpId = @followUpId

            SELECT '{"message":"updated","followUpId":' + CAST(@followUpId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[clientFollowUps] WHERE followUpId = @followUpId
            SELECT '{"message":"deleted","followUpId":' + CAST(@followUpId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_clientFollowUps_all
IF OBJECT_ID(N'dbo.sp_clientFollowUps_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientFollowUps_all];
GO

CREATE PROCEDURE [dbo].[sp_clientFollowUps_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].companyId')
        DECLARE @clientId   INT          = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].clientId')
        DECLARE @riskStatus NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].riskStatus')

        SELECT ISNULL(
            (SELECT followUpId, clientId, companyId, riskStatus,
                    reason, note, assignedTo,
                    CONVERT(NVARCHAR, dueDate, 127)    AS dueDate,
                    CONVERT(NVARCHAR, resolvedAt, 127) AS resolvedAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM [dbo].[clientFollowUps]
             WHERE companyId = @companyId
               AND (@clientId   IS NULL OR clientId   = @clientId)
               AND (@riskStatus IS NULL OR riskStatus = @riskStatus)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('clientFollowUps')),
            '{"clientFollowUps":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_clientFollowUps_one
IF OBJECT_ID(N'dbo.sp_clientFollowUps_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientFollowUps_one];
GO

CREATE PROCEDURE [dbo].[sp_clientFollowUps_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @followUpId INT = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].followUpId')

        SELECT ISNULL(
            (SELECT TOP 1 * FROM [dbo].[clientFollowUps]
             WHERE followUpId = @followUpId
             FOR JSON PATH, ROOT('clientFollowUps')),
            '{"clientFollowUps":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_clientWallets
IF OBJECT_ID(N'dbo.sp_clientWallets', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientWallets];
GO

CREATE PROCEDURE [dbo].[sp_clientWallets]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action     NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.wallets[0].action')
        DECLARE @clientId   INT           = JSON_VALUE(@pjsonfile, '$.wallets[0].clientId')
        DECLARE @companyId  INT           = JSON_VALUE(@pjsonfile, '$.wallets[0].companyId')
        DECLARE @amountMXN  DECIMAL(18,2) = ISNULL(JSON_VALUE(@pjsonfile, '$.wallets[0].amountMXN'), 0)
        DECLARE @creditType NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.wallets[0].creditType')
        DECLARE @debitType  NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.wallets[0].debitType')

        -- Ensure wallet row exists
        IF NOT EXISTS (SELECT 1 FROM [dbo].[clientWallets] WHERE clientId=@clientId AND companyId=@companyId)
            INSERT INTO [dbo].[clientWallets] (clientId, companyId) VALUES (@clientId, @companyId)

        IF @action = 'get'
        BEGIN
            SELECT (SELECT availableBalance, reservedBalance, totalTopUps, totalDisbursed, totalRepaid,
                           CONVERT(NVARCHAR,updatedAt,127) AS updatedAt
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'credit'
        BEGIN
            UPDATE [dbo].[clientWallets]
            SET availableBalance = availableBalance + @amountMXN,
                totalTopUps      = totalTopUps + CASE WHEN @creditType='top_up' THEN @amountMXN ELSE 0 END,
                totalRepaid      = totalRepaid + CASE WHEN @creditType='repayment_received' THEN @amountMXN ELSE 0 END,
                updatedAt        = GETUTCDATE()
            WHERE clientId=@clientId AND companyId=@companyId

            SELECT (SELECT availableBalance, reservedBalance, totalTopUps, totalDisbursed, totalRepaid
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'debit'
        BEGIN
            IF (SELECT availableBalance FROM [dbo].[clientWallets] WHERE clientId=@clientId AND companyId=@companyId) < @amountMXN
            BEGIN
                SELECT '{"error":"Saldo insuficiente en cartera"}' AS [jsonResult]
                RETURN
            END

            UPDATE [dbo].[clientWallets]
            SET availableBalance = availableBalance - @amountMXN,
                reservedBalance  = CASE WHEN @debitType='disbursement'
                                        THEN GREATEST(0, reservedBalance - @amountMXN)
                                        ELSE reservedBalance END,
                totalDisbursed   = totalDisbursed + @amountMXN,
                updatedAt        = GETUTCDATE()
            WHERE clientId=@clientId AND companyId=@companyId

            SELECT (SELECT availableBalance, reservedBalance, totalTopUps, totalDisbursed, totalRepaid
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'reserve'
        BEGIN
            IF (SELECT availableBalance FROM [dbo].[clientWallets] WHERE clientId=@clientId AND companyId=@companyId) < @amountMXN
            BEGIN
                SELECT '{"error":"Saldo insuficiente para reservar"}' AS [jsonResult]
                RETURN
            END

            UPDATE [dbo].[clientWallets]
            SET availableBalance = availableBalance - @amountMXN,
                reservedBalance  = reservedBalance  + @amountMXN,
                updatedAt        = GETUTCDATE()
            WHERE clientId=@clientId AND companyId=@companyId

            SELECT (SELECT availableBalance, reservedBalance
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'release'
        BEGIN
            -- Undo a prior 'reserve' when the disbursement it was held for
            -- fails, without touching totalDisbursed (no money actually moved).
            UPDATE [dbo].[clientWallets]
            SET availableBalance = availableBalance + LEAST(@amountMXN, reservedBalance),
                reservedBalance  = GREATEST(0, reservedBalance - @amountMXN),
                updatedAt        = GETUTCDATE()
            WHERE clientId=@clientId AND companyId=@companyId

            SELECT (SELECT availableBalance, reservedBalance
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT w.clientId, w.companyId, w.availableBalance, w.reservedBalance,
                        w.totalTopUps, w.totalDisbursed, w.totalRepaid,
                        c.first_name, c.last_name
                 FROM [dbo].[clientWallets] w
                 LEFT JOIN [dbo].[clients] c ON c.clientId = w.clientId
                 WHERE w.companyId = @companyId
                 ORDER BY w.availableBalance DESC
                 FOR JSON PATH, ROOT('wallets')),
                '{"wallets":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_clients
IF OBJECT_ID(N'dbo.sp_clients', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clients];
GO

CREATE PROC [dbo].[sp_clients] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Outputmessage NVARCHAR(MAX) = '
        {
          "result": [
            { "value": "", "msg": "", "error": "" }
          ]
        }',
        @Error NVARCHAR(500) = '',
        @action INT;

    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.clients')
    );

    DECLARE @payload TABLE (
        clientId INT NULL,
        companyId INT NULL,
        first_name NVARCHAR(100) NULL,
        last_name NVARCHAR(100) NULL,
        cellphone NVARCHAR(20) NULL,
        email NVARCHAR(100) NULL,
        clientType NVARCHAR(20) NULL
    );

    INSERT INTO @payload (
        clientId,
        companyId,
        first_name,
        last_name,
        cellphone,
        email,
        clientType
    )
    SELECT
        TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        JSON_VALUE(value, '$.first_name'),
        JSON_VALUE(value, '$.last_name'),
        JSON_VALUE(value, '$.cellphone'),
        NULLIF(JSON_VALUE(value, '$.email'), ''),
        JSON_VALUE(value, '$.clientType')
    FROM OPENJSON(@pjsonfile, '$.clients');

    BEGIN TRY

        BEGIN TRANSACTION;

        /* =========================
           ACTION 1 = INSERT
        ========================= */
        IF @action = 1
        BEGIN

            -- Duplicate cellphone in payload within same company
            IF EXISTS (
                SELECT 1
                FROM @payload
                GROUP BY companyId, cellphone
                HAVING COUNT(*) > 1
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Duplicate cellphone in payload.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END

            -- Duplicate email in payload within same company
            IF EXISTS (
                SELECT 1
                FROM @payload
                WHERE email IS NOT NULL
                GROUP BY companyId, email
                HAVING COUNT(*) > 1
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Duplicate email in payload.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END

            -- Cellphone already exists in same company
            IF EXISTS (
                SELECT 1
                FROM @payload p
                INNER JOIN dbo.clients c
                    ON c.companyId = p.companyId
                   AND c.cellphone = p.cellphone
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Cellphone already exists.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END

            -- Email already exists in same company
            IF EXISTS (
                SELECT 1
                FROM @payload p
                INNER JOIN dbo.clients c
                    ON c.companyId = p.companyId
                   AND c.email = p.email
                WHERE p.email IS NOT NULL
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Email already exists.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END

            INSERT INTO dbo.clients (
                companyId,
                first_name,
                last_name,
                cellphone,
                email,
                clientType,
                created_At,
                updated_at
            )
            SELECT
                p.companyId,
                p.first_name,
                p.last_name,
                p.cellphone,
                p.email,
                ISNULL(p.clientType, 'borrower'),
                GETDATE(),
                GETDATE()
            FROM @payload p;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Inserted Successfully');
        END

        /* =========================
           ACTION 2 = UPDATE
        ========================= */
        ELSE IF @action = 2
        BEGIN

            -- Cellphone duplicate validation
            IF EXISTS (
                SELECT 1
                FROM @payload p
                INNER JOIN dbo.clients c
                    ON c.companyId = p.companyId
                   AND c.cellphone = p.cellphone
                WHERE c.clientId <> p.clientId
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Cellphone already exists.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END

            -- Email duplicate validation
            IF EXISTS (
                SELECT 1
                FROM @payload p
                INNER JOIN dbo.clients c
                    ON c.companyId = p.companyId
                   AND c.email = p.email
                WHERE p.email IS NOT NULL
                  AND c.clientId <> p.clientId
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Email already exists.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END

            UPDATE c
            SET
                c.companyId = p.companyId,
                c.first_name = p.first_name,
                c.last_name = p.last_name,
                c.cellphone = p.cellphone,
                c.email = p.email,
                c.clientType = COALESCE(p.clientType, c.clientType),
                c.updated_at = GETDATE()
            FROM dbo.clients c
            INNER JOIN @payload p
                ON c.clientId = p.clientId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Updated Successfully');
        END

        /* =========================
           ACTION 3 = DELETE
        ========================= */
        ELSE IF @action = 3
        BEGIN

            DELETE c
            FROM dbo.clients c
            INNER JOIN @payload p
                ON c.clientId = p.clientId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Deleted Successfully');
        END

        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Invalid action. Use 1=Insert, 2=Update, 3=Delete.');
        END

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();

        SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);

    END CATCH

Finish:

    SELECT
        JSON_VALUE(value,'$.value') AS value,
        JSON_VALUE(value,'$.msg') AS msg,
        JSON_VALUE(value,'$.error') AS error
    FROM OPENJSON(@Outputmessage,'$.result');

END
GO

-- dbo.sp_clients_all
IF OBJECT_ID(N'dbo.sp_clients_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clients_all];
GO

CREATE PROC [dbo].[sp_clients_all]
AS
SET NOCOUNT ON
BEGIN

    SELECT
        [clientId],
        ISNULL([companyId], 0)     AS companyId,
        ISNULL([first_name], '')   AS first_name,
        ISNULL([last_name], '')    AS last_name,
        ISNULL([cellphone], '')    AS cellphone,
        ISNULL([email], '')        AS email,
        [created_At],
        [updated_at],
        clientType,
        ISNULL([qrBlobUrl], '')    AS qrBlobUrl
    FROM dbo.clients
    FOR JSON AUTO, ROOT('clients');

END
GO

-- dbo.sp_clients_one
IF OBJECT_ID(N'dbo.sp_clients_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clients_one];
GO

CREATE PROC [dbo].[sp_clients_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
      "clients": [
        { "clientId": "1" }
      ]
    }';
    */

    DECLARE @clientId INT;

    SET @clientId = CAST(
        (
            SELECT TOP 1 JSON_VALUE(value, '$.clientId')
            FROM OPENJSON(@pjsonfile, '$.clients')
        ) AS INT
    );

    SELECT
        clientId,
        ISNULL(companyId, 0) AS companyId,
        ISNULL(first_name, '') AS first_name,
        ISNULL(last_name, '') AS last_name,
        ISNULL(cellphone, '') AS cellphone,
        ISNULL(email, '') AS email,
        created_At,
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at,
        clientType,
        ISNULL(qrBlobUrl, '') AS qrBlobUrl
    FROM dbo.clients
    WHERE clientId = @clientId
    FOR JSON AUTO, ROOT('clients');

END
GO

-- dbo.sp_clients_qr
IF OBJECT_ID(N'dbo.sp_clients_qr', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clients_qr];
GO

CREATE PROCEDURE [dbo].[sp_clients_qr]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @clientId  INT           = JSON_VALUE(@pjsonfile, '$.clients[0].clientId')
        DECLARE @companyId INT           = JSON_VALUE(@pjsonfile, '$.clients[0].companyId')
        DECLARE @qrBlobUrl NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.clients[0].qrBlobUrl')

        UPDATE [dbo].[clients]
        SET    qrBlobUrl  = @qrBlobUrl,
               updated_at = GETUTCDATE()
        WHERE  clientId   = @clientId
          AND  companyId  = @companyId

        SELECT '{"message":"qrBlobUrl updated","clientId":' + CAST(@clientId AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_commands_all
IF OBJECT_ID(N'dbo.sp_commands_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_commands_all];
GO

--EXEC [sp_orders_all]

CREATE PROCEDURE [dbo].[sp_commands_all]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT commandId, phrase, action  FROM dbo.Commands
    FOR JSON AUTO, ROOT('commands');

END
GO

-- dbo.sp_companies
IF OBJECT_ID(N'dbo.sp_companies', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_companies];
GO

-- CRUD for dbo.companies using JSON payload
CREATE   PROC [dbo].[sp_companies] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*
    -- Demo payload
    DECLARE @pjsonfile VARCHAR(MAX) = '{
      "companies": [
        {
          "companyId": 1,
          "name": "GMO Lavandería",
          "createdAt": "2024-01-23T19:22:59.253",
          "updatedAt": "2024-01-23T19:22:59.253",
          "action": "1"
        }
      ]
    }';
    */

    DECLARE
        @Outputmessage NVARCHAR(MAX) = '
        {
          "result": [
            { "value": "", "msg": "", "error": "" }
          ]
        }',
        @Error NVARCHAR(500) = '',
        @action INT;

    -- Determine action from JSON (first element)
    SET @action =
    (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.companies')
    );

    IF @action IS NULL
    BEGIN
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid input: $.companies[0].action is required.');
        SELECT
            JSON_VALUE(value, '$.value') AS [value],
            JSON_VALUE(value, '$.msg')   AS [msg],
            JSON_VALUE(value, '$.error') AS [error]
        FROM OPENJSON(@Outputmessage, '$.result');
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            INSERT INTO dbo.companies ([name], createdAt, updatedAt)
            SELECT
                JSON_VALUE(value, '$.name'),
                ISNULL(TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.createdAt')), GETDATE()),
                ISNULL(TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.updatedAt')), GETDATE())
            FROM OPENJSON(@pjsonfile, '$.companies');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            UPDATE c
            SET
                c.[name]      = JSON_VALUE(j.value, '$.name'),
                c.updatedAt   = GETDATE()
            FROM dbo.companies c
            INNER JOIN OPENJSON(@pjsonfile, '$.companies') j
                ON c.companyId = TRY_CONVERT(INT, JSON_VALUE(j.value, '$.companyId'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            DELETE c
            FROM dbo.companies c
            WHERE c.companyId IN
            (
                SELECT TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId'))
                FROM OPENJSON(@pjsonfile, '$.companies')
            );

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid action. Use 1=INSERT, 2=UPDATE, 3=DELETE.');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg')   AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_companiesBranch_by_company
IF OBJECT_ID(N'dbo.sp_companiesBranch_by_company', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_companiesBranch_by_company];
GO

CREATE   PROC dbo.sp_companiesBranch_by_company (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @companyId INT =
        TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.companiesBranch[0].companyId'));

    IF @companyId IS NULL
    BEGIN
        SELECT
            branchId,
            [name],
            active,
            companyId,
            createdAt,
            updatedAt
        FROM dbo.companiesBranch
        WHERE 1 = 0
        FOR JSON AUTO, ROOT('companiesBranch');
        RETURN;
    END

    SELECT
        branchId,
        [name],
        active,
        companyId,
        createdAt,
        updatedAt
    FROM dbo.companiesBranch
    WHERE companyId = @companyId
    ORDER BY [name]
    FOR JSON AUTO, ROOT('companiesBranch');
END
GO

-- dbo.sp_companiesBranches
IF OBJECT_ID(N'dbo.sp_companiesBranches', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_companiesBranches];
GO

CREATE   PROC dbo.sp_companiesBranches (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @Outputmessage NVARCHAR(MAX) = N'{"result":[{"value":"","msg":"","error":""}]}',
        @Error NVARCHAR(500) = N'',
        @action INT;

    -- Determine action (from first element)
    SET @action =
    (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.companiesBranch')
    );

    IF @action IS NULL
    BEGIN
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',
            'Invalid input: $.companiesBranch[0].action is required (1=INSERT,2=UPDATE,3=DELETE).');
        SELECT @Outputmessage AS json_result;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        ------------------------------------------------------------
        -- INSERT
        ------------------------------------------------------------
        IF @action = 1
        BEGIN
            -- Validate required fields
            IF EXISTS (
                SELECT 1
                FROM OPENJSON(@pjsonfile, '$.companiesBranch') j
                WHERE NULLIF(JSON_VALUE(j.value,'$.name'), '') IS NULL
                   OR TRY_CONVERT(INT, JSON_VALUE(j.value,'$.companyId')) IS NULL
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',
                    'Invalid input: name and companyId are required for action=1.');
                SELECT @Outputmessage AS json_result;
                ROLLBACK TRANSACTION;
                RETURN;
            END

            DECLARE @Inserted TABLE (branchId INT);

            INSERT INTO dbo.companiesBranch ([name], active, companyId, createdAt, updatedAt)
            OUTPUT INSERTED.branchId INTO @Inserted(branchId)
            SELECT
                JSON_VALUE(j.value, '$.name'),
                ISNULL(NULLIF(JSON_VALUE(j.value, '$.active'), ''), '1'),
                TRY_CONVERT(INT, JSON_VALUE(j.value, '$.companyId')),
                GETDATE(),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.companiesBranch') j;

            -- Return the first inserted id (if multiple, you can extend to array later)
            DECLARE @newId INT = (SELECT TOP 1 branchId FROM @Inserted ORDER BY branchId DESC);

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @newId));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END

        ------------------------------------------------------------
        -- UPDATE
        ------------------------------------------------------------
        ELSE IF @action = 2
        BEGIN
            -- Validate required fields
            IF EXISTS (
                SELECT 1
                FROM OPENJSON(@pjsonfile, '$.companiesBranch') j
                WHERE TRY_CONVERT(INT, JSON_VALUE(j.value,'$.branchId')) IS NULL
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',
                    'Invalid input: branchId is required for action=2.');
                SELECT @Outputmessage AS json_result;
                ROLLBACK TRANSACTION;
                RETURN;
            END

            UPDATE b
            SET
                b.[name]    = ISNULL(NULLIF(JSON_VALUE(j.value, '$.name'), ''), b.[name]),
                b.active    = ISNULL(NULLIF(JSON_VALUE(j.value, '$.active'), ''), b.active),
                b.companyId = ISNULL(TRY_CONVERT(INT, JSON_VALUE(j.value, '$.companyId')), b.companyId),
                b.updatedAt = GETDATE()
            FROM dbo.companiesBranch b
            INNER JOIN OPENJSON(@pjsonfile, '$.companiesBranch') j
                ON b.branchId = TRY_CONVERT(INT, JSON_VALUE(j.value, '$.branchId'));

            IF @@ROWCOUNT = 0
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',
                    'No rows updated. Check branchId.');
            END
            ELSE
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
            END
        END

        ------------------------------------------------------------
        -- DELETE
        ------------------------------------------------------------
        ELSE IF @action = 3
        BEGIN
            -- Validate required fields
            IF EXISTS (
                SELECT 1
                FROM OPENJSON(@pjsonfile, '$.companiesBranch') j
                WHERE TRY_CONVERT(INT, JSON_VALUE(j.value,'$.branchId')) IS NULL
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',
                    'Invalid input: branchId is required for action=3.');
                SELECT @Outputmessage AS json_result;
                ROLLBACK TRANSACTION;
                RETURN;
            END

            DELETE b
            FROM dbo.companiesBranch b
            WHERE b.branchId IN
            (
                SELECT TRY_CONVERT(INT, JSON_VALUE(value, '$.branchId'))
                FROM OPENJSON(@pjsonfile, '$.companiesBranch')
            );

            IF @@ROWCOUNT = 0
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',
                    'No rows deleted. Check branchId.');
            END
            ELSE
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
            END
        END

        ------------------------------------------------------------
        -- INVALID ACTION
        ------------------------------------------------------------
        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',
                'Invalid action. Use 1=INSERT, 2=UPDATE, 3=DELETE.');
        END

        COMMIT TRANSACTION;

        SELECT @Outputmessage AS json_result;
        RETURN;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);

        SELECT @Outputmessage AS json_result;
        RETURN;
    END CATCH
END
GO

-- dbo.sp_companiesBranches_all
IF OBJECT_ID(N'dbo.sp_companiesBranches_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_companiesBranches_all];
GO

CREATE   PROC [dbo].[sp_companiesBranches_all]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        branchId,
        [name],
        active,
        companyId,
        createdAt,
        updatedAt
    FROM dbo.companiesBranch
    FOR JSON AUTO, ROOT('companiesBranch');
END
GO

-- dbo.sp_companiesBranches_one
IF OBJECT_ID(N'dbo.sp_companiesBranches_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_companiesBranches_one];
GO

CREATE   PROC [dbo].[sp_companiesBranches_one] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile NVARCHAR(MAX) = N'{
      "companiesBranch": [
        { "branchId": 1 }
      ]
    }';
    */

    DECLARE @branchId INT =
        TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.companiesBranch[0].branchId'));

    IF @branchId IS NULL
    BEGIN
        SELECT
            branchId,
            [name],
            active,
            companyId,
            createdAt,
            updatedAt
        FROM dbo.companiesBranch
        WHERE 1 = 0
        FOR JSON AUTO, ROOT('companiesBranch');
        RETURN;
    END

    SELECT
        branchId,
        [name],
        active,
        companyId,
        createdAt,
        updatedAt
    FROM dbo.companiesBranch
    WHERE branchId = @branchId
    FOR JSON AUTO, ROOT('companiesBranch');
END
GO

-- dbo.sp_companies_all
IF OBJECT_ID(N'dbo.sp_companies_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_companies_all];
GO

create PROC [dbo].[sp_companies_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT 
        companyId
        ,[name]
        ,createdAt
        ,updatedAt 
    FROM 
        dbo.companies
    FOR JSON AUTO, ROOT('companies');
END
GO

-- dbo.sp_companies_one
IF OBJECT_ID(N'dbo.sp_companies_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_companies_one];
GO

-- Get ONE company by companyId (JSON input -> JSON output)
CREATE   PROC [dbo].[sp_companies_one] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- Demo
    DECLARE @pjsonfile NVARCHAR(MAX) = N'{
      "companies": [
        { "companyId": 1 }
      ]
    }';
    */

    DECLARE @companyId INT =
        TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.companies[0].companyId'));

    IF @companyId IS NULL
    BEGIN
        -- Return empty but consistent JSON shape
        SELECT
            CAST('[]' AS NVARCHAR(MAX)) AS companies
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    SELECT
        companyId,
        [name],
        createdAt,
        updatedAt
    FROM dbo.companies
    WHERE companyId = @companyId
    FOR JSON AUTO, ROOT('companies');
END
GO

-- dbo.sp_contractors
IF OBJECT_ID(N'dbo.sp_contractors', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_contractors];
GO
CREATE PROC [dbo].[sp_contractors] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "contractors": [
        {
            "contractorId": 1,
            "employeeId": 2,
            "contractingCompany": "ABC Contractors",
            "contractStartDate": "2022-03-01",
            "contractEndDate": "2022-12-31",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/
    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.contractors'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the contractors
            INSERT INTO [dbo].[contractors] 
                ([employeeId], [contractingCompany], [contractStartDate], [contractEndDate], [createdAt])
            SELECT
                JSON_VALUE(value, '$.employeeId'),
                JSON_VALUE(value, '$.contractingCompany'),
                JSON_VALUE(value, '$.contractStartDate'),
                JSON_VALUE(value, '$.contractEndDate'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.contractors');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the contractors
            UPDATE c
            SET 
                c.[employeeId] = JSON_VALUE(j.value, '$.employeeId'),
                c.[contractingCompany] = JSON_VALUE(j.value, '$.contractingCompany'),
                c.[contractStartDate] = JSON_VALUE(j.value, '$.contractStartDate'),
                c.[contractEndDate] = JSON_VALUE(j.value, '$.contractEndDate')
            FROM 
                [dbo].[contractors] c
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.contractors') j
                ON c.[contractorId] = JSON_VALUE(j.value, '$.contractorId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the contractors
            DELETE FROM [dbo].[contractors]
            WHERE [contractorId] IN (SELECT JSON_VALUE(value, '$.contractorId') FROM OPENJSON(@pjsonfile, '$.contractors'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_contractors_all
IF OBJECT_ID(N'dbo.sp_contractors_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_contractors_all];
GO

CREATE PROC [dbo].[sp_contractors_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [contractorId],
        [employeeId],
        ISNULL([contractingCompany], '') AS contractingCompany,
        ISNULL([contractStartDate], '') AS contractStartDate,
        ISNULL([contractEndDate], '') AS contractEndDate,
        [createdAt]
    FROM [montanogilberto_smartloans].[dbo].[contractors]
    FOR JSON AUTO, ROOT('contractors');
END
GO

-- dbo.sp_contractors_one
IF OBJECT_ID(N'dbo.sp_contractors_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_contractors_one];
GO
CREATE PROC [dbo].[sp_contractors_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "contractors": [
        {
        "contractorId": "1"
        }
     ]   
    }'
    */

    DECLARE @contractorId INT;

    SET @contractorId = CAST((SELECT JSON_VALUE(value, '$.contractorId') FROM OPENJSON(@pjsonfile, '$.contractors')) AS INT);

    SELECT 
        [contractorId]
        ,[employeeId]
        ,ISNULL([contractingCompany], '') AS contractingCompany
        ,ISNULL([contractStartDate], '') AS contractStartDate
        ,ISNULL([contractEndDate], '') AS contractEndDate
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[contractors]
    WHERE
        contractorId = @contractorId
    FOR JSON AUTO, ROOT('contractors');

END
GO

-- dbo.sp_costRules
IF OBJECT_ID(N'dbo.sp_costRules', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_costRules];
GO

CREATE PROC [dbo].[sp_costRules] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

    /*
        DECLARE @pjsonfile VARCHAR(MAX) = '{
        "costRules": [
            {
            "channel": "amazon",
            "market": "US",
            "category": "Electronics",
            "feePercent": 0.150000,
            "fixedFeeUsd": 0.300000,
            "adsPercent": 0.050000,
            "returnsRate": 0.020000,
            "avgReturnCostUsd": 8.000000,
            "packagingCostUsd": 0.500000,
            "otherCostUsd": 0.250000,
            "effectiveFrom": "2026-01-17",
            "effectiveTo": null,
            "action": "1"
            }
        ]
        }';
    */

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (
    SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
    FROM OPENJSON(@pjsonfile, '$.costRules')
  );

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.costRules (
        channel, market, category,
        feePercent, fixedFeeUsd, adsPercent,
        returnsRate, avgReturnCostUsd,
        packagingCostUsd, otherCostUsd,
        effectiveFrom, effectiveTo
      )
      SELECT
        JSON_VALUE(value, '$.channel'),
        ISNULL(NULLIF(JSON_VALUE(value, '$.market'), ''), 'US'),
        JSON_VALUE(value, '$.category'),
        TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.feePercent')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.fixedFeeUsd')),
        TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.adsPercent')),
        TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.returnsRate')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.avgReturnCostUsd')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.packagingCostUsd')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value, '$.otherCostUsd')),
        TRY_CONVERT(DATE, JSON_VALUE(value, '$.effectiveFrom')),
        TRY_CONVERT(DATE, JSON_VALUE(value, '$.effectiveTo'))
      FROM OPENJSON(@pjsonfile, '$.costRules');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE cr
      SET
        cr.channel = JSON_VALUE(j.value, '$.channel'),
        cr.market  = ISNULL(NULLIF(JSON_VALUE(j.value, '$.market'), ''), 'US'),
        cr.category = JSON_VALUE(j.value, '$.category'),
        cr.feePercent = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(j.value, '$.feePercent')),
        cr.fixedFeeUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.fixedFeeUsd')),
        cr.adsPercent = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(j.value, '$.adsPercent')),
        cr.returnsRate = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(j.value, '$.returnsRate')),
        cr.avgReturnCostUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.avgReturnCostUsd')),
        cr.packagingCostUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.packagingCostUsd')),
        cr.otherCostUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.otherCostUsd')),
        cr.effectiveFrom = TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.effectiveFrom')),
        cr.effectiveTo   = TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.effectiveTo'))
      FROM dbo.costRules cr
      INNER JOIN OPENJSON(@pjsonfile, '$.costRules') j
        ON cr.ruleId = TRY_CONVERT(INT, JSON_VALUE(j.value, '$.ruleId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.costRules
      WHERE ruleId IN (
        SELECT TRY_CONVERT(INT, JSON_VALUE(value, '$.ruleId'))
        FROM OPENJSON(@pjsonfile, '$.costRules')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH

  SELECT
    JSON_VALUE(value, '$.value') AS [value],
    JSON_VALUE(value, '$.msg')   AS [msg],
    JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_creatediagram
IF OBJECT_ID(N'dbo.sp_creatediagram', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_creatediagram];
GO

	CREATE PROCEDURE dbo.sp_creatediagram
	(
		@diagramname 	sysname,
		@owner_id		int	= null, 	
		@version 		int,
		@definition 	varbinary(max)
	)
	WITH EXECUTE AS 'dbo'
	AS
	BEGIN
		set nocount on
	
		declare @theId int
		declare @retval int
		declare @IsDbo	int
		declare @userName sysname
		if(@version is null or @diagramname is null)
		begin
			RAISERROR (N'E_INVALIDARG', 16, 1);
			return -1
		end
	
		execute as caller;
		select @theId = DATABASE_PRINCIPAL_ID(); 
		select @IsDbo = IS_MEMBER(N'db_owner');
		revert; 
		
		if @owner_id is null
		begin
			select @owner_id = @theId;
		end
		else
		begin
			if @theId <> @owner_id
			begin
				if @IsDbo = 0
				begin
					RAISERROR (N'E_INVALIDARG', 16, 1);
					return -1
				end
				select @theId = @owner_id
			end
		end
		-- next 2 line only for test, will be removed after define name unique
		if EXISTS(select diagram_id from dbo.sysdiagrams where principal_id = @theId and name = @diagramname)
		begin
			RAISERROR ('The name is already used.', 16, 1);
			return -2
		end
	
		insert into dbo.sysdiagrams(name, principal_id , version, definition)
				VALUES(@diagramname, @theId, @version, @definition) ;
		
		select @retval = @@IDENTITY 
		return @retval
	END
GO

-- dbo.sp_creditScore_data
IF OBJECT_ID(N'dbo.sp_creditScore_data', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_creditScore_data];
GO

CREATE PROCEDURE [dbo].[sp_creditScore_data]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.creditScore[0].clientId')
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.creditScore[0].companyId')
        DECLARE @today DATETIME2 = GETUTCDATE()
        DECLARE @90dAgo DATETIME2 = DATEADD(DAY, -90, @today)

        -- Payment history from stripeTransactions
        DECLARE @totalPayments INT = (
            SELECT COUNT(*) FROM [dbo].[stripeTransactions]
            WHERE fromClientId = @clientId AND companyId = @companyId
              AND paymentType = 'loan_repayment'
        )
        DECLARE @onTimePayments INT = (
            SELECT COUNT(*) FROM [dbo].[stripeTransactions] st
            INNER JOIN [dbo].[loanInstallments] li
                ON st.stripePaymentIntentId = li.stripePaymentIntentId
            WHERE st.fromClientId = @clientId AND st.companyId = @companyId
              AND st.paymentType = 'loan_repayment' AND st.status = 'succeeded'
              AND li.paidAt <= DATEADD(DAY, 3, li.dueDate)  -- 3-day grace period
        )
        DECLARE @latePayments INT = (
            SELECT COUNT(*) FROM [dbo].[loanInstallments]
            WHERE clientId = @clientId AND companyId = @companyId
              AND status IN ('paid') AND paidAt > DATEADD(DAY, 3, dueDate)
        )
        DECLARE @defaults INT = (
            SELECT COUNT(*) FROM [dbo].[loanInstallments]
            WHERE clientId = @clientId AND companyId = @companyId AND status = 'delinquent'
        )

        -- Outstanding balance
        DECLARE @outstandingBalance DECIMAL(18,2) = (
            SELECT ISNULL(SUM(principalAmount), 0) FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
              AND loanStatus IN ('Active', 'active', 'Pending', 'pending')
        )
        DECLARE @totalCreditLimit DECIMAL(18,2) = (
            SELECT ISNULL(SUM(approvedAmount), 0) FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
        )

        -- Credit age
        DECLARE @creditAgeMonths INT = (
            SELECT ISNULL(
                DATEDIFF(MONTH,
                    MIN(created_At),
                    GETUTCDATE()),
                0)
            FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
        )

        -- Recent proposals (hard inquiries)
        DECLARE @proposalsLast90 INT = (
            SELECT COUNT(*) FROM [dbo].[loanProposals]
            WHERE borrowerId = @clientId AND companyId = @companyId
              AND created_At >= @90dAgo
        )

        -- Loan counts
        DECLARE @paidLoans INT = (
            SELECT COUNT(*) FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
              AND loanStatus IN ('Paid', 'paid', 'Completed', 'completed')
        )
        DECLARE @activeLoans INT = (
            SELECT COUNT(*) FROM [dbo].[loans]
            WHERE clientId = @clientId AND companyId = @companyId
              AND loanStatus IN ('Active', 'active')
        )

        -- Follow-up risk flags
        DECLARE @followUpAtRisk INT = (
            SELECT COUNT(*) FROM [dbo].[clientFollowUps]
            WHERE clientId = @clientId AND companyId = @companyId AND riskStatus = 'at_risk'
        )
        DECLARE @followUpDefault INT = (
            SELECT COUNT(*) FROM [dbo].[clientFollowUps]
            WHERE clientId = @clientId AND companyId = @companyId AND riskStatus = 'default'
        )

        -- Biometric & legal flags — read all three from the newest VERIFIED
        -- expediente, so a newer unfinished re-KYC row can't shadow it.
        -- NOTE: the ClientFaceRecognitions table columns are snake_case
        -- (is_verified / pagare_accepted / contract_accepted / created_At).
        -- The camelCase names below are only JSON OUTPUT aliases (what the
        -- Python engine reads) — the column references must be snake_case.
        DECLARE @faceId INT = (
            SELECT TOP 1 clientFaceRecognitionId
            FROM   [dbo].[ClientFaceRecognitions]
            WHERE  clientId = @clientId AND companyId = @companyId AND is_verified = 1
            ORDER BY created_At DESC
        );
        DECLARE @isVerified       BIT = CASE WHEN @faceId IS NULL THEN 0 ELSE 1 END;
        DECLARE @pagareAccepted   BIT = ISNULL((SELECT pagare_accepted   FROM [dbo].[ClientFaceRecognitions] WHERE clientFaceRecognitionId = @faceId), 0);
        DECLARE @contractAccepted BIT = ISNULL((SELECT contract_accepted FROM [dbo].[ClientFaceRecognitions] WHERE clientFaceRecognitionId = @faceId), 0);

        SELECT (SELECT
            @totalPayments      AS totalPayments,
            @onTimePayments     AS onTimePayments,
            @latePayments       AS latePayments,
            @defaults           AS [defaults],
            @outstandingBalance AS outstandingBalance,
            @totalCreditLimit   AS totalCreditLimit,
            @creditAgeMonths    AS creditAgeMonths,
            @proposalsLast90    AS proposalsLast90Days,
            @paidLoans          AS paidLoans,
            @activeLoans        AS activeLoans,
            @followUpAtRisk     AS followUpAtRisk,
            @followUpDefault    AS followUpDefault,
            ISNULL(@isVerified, 0)       AS isVerified,
            ISNULL(@pagareAccepted, 0)   AS pagareAccepted,
            ISNULL(@contractAccepted, 0) AS contractAccepted
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_creditScores
IF OBJECT_ID(N'dbo.sp_creditScores', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_creditScores];
GO

CREATE PROCEDURE [dbo].[sp_creditScores]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    NVARCHAR(10)   = JSON_VALUE(@pjsonfile, '$.creditScores[0].action')
        DECLARE @clientId  INT            = JSON_VALUE(@pjsonfile, '$.creditScores[0].clientId')
        DECLARE @companyId INT            = JSON_VALUE(@pjsonfile, '$.creditScores[0].companyId')
        DECLARE @score     INT            = JSON_VALUE(@pjsonfile, '$.creditScores[0].score')
        DECLARE @label     NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.creditScores[0].label')
        DECLARE @breakdown NVARCHAR(MAX)  = JSON_VALUE(@pjsonfile, '$.creditScores[0].breakdown')
        DECLARE @computedAt DATETIME2     = ISNULL(JSON_VALUE(@pjsonfile, '$.creditScores[0].computedAt'), GETUTCDATE())

        IF @action = 'upsert'
        BEGIN
            -- Derive label if not provided
            IF @label IS NULL
                SET @label = CASE
                    WHEN @score >= 750 THEN 'Excelente'
                    WHEN @score >= 700 THEN 'Muy bueno'
                    WHEN @score >= 650 THEN 'Bueno'
                    WHEN @score >= 600 THEN 'Regular'
                    WHEN @score >= 550 THEN 'Bajo'
                    ELSE 'Muy bajo' END

            MERGE [dbo].[creditScores] AS target
            USING (SELECT @clientId AS clientId, @companyId AS companyId) AS src
                ON target.clientId = src.clientId AND target.companyId = src.companyId
            WHEN MATCHED THEN
                UPDATE SET score=@score, label=@label, breakdown=@breakdown, computedAt=@computedAt
            WHEN NOT MATCHED THEN
                INSERT (clientId, companyId, score, label, breakdown, computedAt)
                VALUES (@clientId, @companyId, @score, @label, @breakdown, @computedAt);

            -- Always append history row
            INSERT INTO [dbo].[creditScoreHistory] (clientId, companyId, score, label, computedAt)
            VALUES (@clientId, @companyId, @score, @label, @computedAt)

            SELECT (SELECT TOP 1 score, label, breakdown, CONVERT(NVARCHAR,computedAt,127) AS computedAt
                    FROM [dbo].[creditScores]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 score, label, breakdown, CONVERT(NVARCHAR,computedAt,127) AS computedAt
                 FROM [dbo].[creditScores]
                 WHERE clientId=@clientId AND companyId=@companyId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{}'
            ) AS [jsonResult]
        END

        ELSE IF @action = 'history'
        BEGIN
            SELECT ISNULL(
                (SELECT score, label, CONVERT(NVARCHAR,computedAt,127) AS computedAt
                 FROM [dbo].[creditScoreHistory]
                 WHERE clientId=@clientId AND companyId=@companyId
                 ORDER BY computedAt ASC
                 FOR JSON PATH, ROOT('history')),
                '{"history":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_database_info_tables
IF OBJECT_ID(N'dbo.sp_database_info_tables', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_database_info_tables];
GO
CREATE PROC [dbo].[sp_database_info_tables]

AS

SET NOCOUNT ON

BEGIN

 

       SELECT

              t.[name] AS table_name,

              (

                      SELECT

                             c.[name] AS column_name,

                             CASE

                                    WHEN typ.name = 'varchar' THEN typ.name + '(' + CAST(c.max_length AS VARCHAR(10)) + ')'

                                    ELSE typ.name

                             END AS data_type,

                             CASE

                                    WHEN (

                                           SELECT COUNT(*)

                                           FROM sys.indexes i

                                           INNER JOIN sys.index_columns ic ON i.[object_id] = ic.[object_id] AND i.index_id = ic.index_id

                                           WHERE i.is_primary_key = 1 AND ic.column_id = c.column_id

                                    ) > 0 THEN 'Yes'

                                    ELSE 'Not'

                             END AS is_primary_key,

                             CASE

                                    WHEN (

                                           SELECT COUNT(*)

                                           FROM sys.foreign_key_columns fk

                                           WHERE fk.parent_object_id = c.[object_id] AND fk.parent_column_id = c.column_id

                                    ) > 0 THEN 'Yes'

                                    ELSE 'Not'

                             END AS is_foreign_key

                      FROM

                             sys.columns c

                             INNER JOIN sys.types typ ON c.user_type_id = typ.user_type_id

                      WHERE

                             c.[object_id] = t.[object_id]

                      ORDER BY

                             c.column_id

                      FOR JSON PATH

              ) AS columns_info

       FROM

              sys.tables t

       ORDER BY

              t.[name]

FOR JSON PATH, ROOT('database_info');

 

END
GO

-- dbo.sp_deleteClientCascade
IF OBJECT_ID(N'dbo.sp_deleteClientCascade', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_deleteClientCascade];
GO
CREATE   PROC [dbo].[sp_deleteClientCascade] (@pjsonfile VARCHAR(MAX))
-- ⚠️ DESTRUCTIVE & IRREVERSIBLE. Hard-deletes each client in the payload, its
--    linked login (dbo.users) and its child rows in cascade. BATCH: pass one or
--    many clients. Protected client ids (e.g. clientId 1 = Lavanderia / system
--    default) are SKIPPED, not deleted. Each client runs in its OWN transaction,
--    so one failure or skip does not abort the rest.
--
-- Input:  { "clients": [ { "clientId": 2116, "companyId": 1008 }, { "clientId": 2151 } ] }
--         companyId is optional per client (safety scope — refuses another company's client).
-- Output: single JSON string { "result": [ { clientId, value, msg, error }, ... ] }
--
-- Admin/maintenance utility — NOT wired to an API route on purpose. Run your
-- SELECT (or take a backup) before executing.
--
-- REVIEW before first run: the "other tables" block below extends the cascade so
-- foreign keys can't block the final DELETE and no orphans remain. Verify those
-- table/column names against your schema; comment out any that don't apply and
-- add any that are missing (digitalContracts, legalCases, etc.).
AS
SET NOCOUNT ON

DECLARE @results  VARCHAR(MAX) = '{ "result": [] }'
       ,@clientId  INT
       ,@companyId INT
       ,@rows      INT
       ,@value     VARCHAR(20)
       ,@msg       VARCHAR(500)
       ,@err       VARCHAR(1)

DECLARE client_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
           TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId'))
    FROM OPENJSON(@pjsonfile, '$.clients')

OPEN client_cursor
FETCH NEXT FROM client_cursor INTO @clientId, @companyId
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @rows = 0; SET @value = ''; SET @msg = ''; SET @err = '0'

    -- ── Validation ────────────────────────────────────────────────────────
    IF @clientId IS NULL OR @clientId = 0
    BEGIN SET @err = '1'; SET @msg = 'clientId es requerido.' END

    -- Protected ids → skipped quietly (no error), so the batch keeps going.
    ELSE IF @clientId IN (1)
    BEGIN SET @value = CAST(@clientId AS VARCHAR(20)); SET @msg = 'Cliente protegido — omitido (skipped).' END

    ELSE IF NOT EXISTS (
        SELECT 1 FROM dbo.clients
        WHERE clientId = @clientId AND (@companyId IS NULL OR companyId = @companyId)
    )
    BEGIN SET @err = '1'; SET @msg = 'Cliente no encontrado (o companyId no coincide).' END

    -- ── DELETE (cascade) ──────────────────────────────────────────────────
    ELSE
    BEGIN
        BEGIN TRY
            BEGIN TRAN
                -- 1. Child records from the original query.
                IF OBJECT_ID('dbo.savedPaymentMethods', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.savedPaymentMethods WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                IF OBJECT_ID('dbo.clientWallets', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.clientWallets WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                IF OBJECT_ID('dbo.ClientFaceRecognitions', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.ClientFaceRecognitions WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                IF OBJECT_ID('dbo.clientDashboards', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.clientDashboards WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                -- 2. Other tables that reference this client (REVIEW names).
                IF OBJECT_ID('dbo.clientFollowUps', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.clientFollowUps WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                IF OBJECT_ID('dbo.creditScoreHistory', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.creditScoreHistory WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                IF OBJECT_ID('dbo.creditScores', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.creditScores WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                -- loanProposals links two clients (lender + borrower) — match either side.
                IF OBJECT_ID('dbo.loanProposals', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.loanProposals WHERE borrowerId = @clientId OR lenderId = @clientId; SET @rows += @@ROWCOUNT END

                IF OBJECT_ID('dbo.loans', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.loans WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                -- 3. The login linked to this client (removes their ability to log in).
                IF OBJECT_ID('dbo.userCompanies', 'U') IS NOT NULL
                BEGIN
                    DELETE uc FROM dbo.userCompanies uc
                    INNER JOIN dbo.users u ON u.userId = uc.userId
                    WHERE u.clientId = @clientId
                    SET @rows += @@ROWCOUNT
                END

                IF OBJECT_ID('dbo.users', 'U') IS NOT NULL
                BEGIN DELETE FROM dbo.users WHERE clientId = @clientId; SET @rows += @@ROWCOUNT END

                -- 4. Finally the parent client row.
                DELETE FROM dbo.clients WHERE clientId = @clientId; SET @rows += @@ROWCOUNT
            COMMIT TRAN

            SET @value = CAST(@clientId AS VARCHAR(20))
            SET @msg   = 'Deleted Successfully (' + CAST(@rows AS VARCHAR(20)) + ' rows).'
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK
            SET @err = '1'; SET @msg = ERROR_MESSAGE()
        END CATCH
    END

    -- Append this client's outcome to the results array (msg JSON-escaped).
    SET @results = JSON_MODIFY(@results, 'append $.result',
        JSON_QUERY(
            '{"clientId":' + CAST(ISNULL(@clientId, 0) AS VARCHAR(20)) +
            ',"value":"'   + @value +
            '","msg":"'    + STRING_ESCAPE(@msg, 'json') +
            '","error":"'  + @err + '"}'
        ))

    FETCH NEXT FROM client_cursor INTO @clientId, @companyId
END
CLOSE client_cursor
DEALLOCATE client_cursor

-- Return the response as a single JSON string.
SELECT @results AS [jsonResult]
GO

-- dbo.sp_departaments
IF OBJECT_ID(N'dbo.sp_departaments', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_departaments];
GO
CREATE PROC [dbo].[sp_departaments] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "departments": [
        {
            "departmentId": 1,
            "departmentName": "HR",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/
    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.departments'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the departments
            INSERT INTO [dbo].[departments] 
                ([departmentName], [createdAt])
            SELECT
                JSON_VALUE(value, '$.departmentName'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.departments');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the departments
            UPDATE d
            SET 
                d.[departmentName] = JSON_VALUE(j.value, '$.departmentName')
            FROM 
                [dbo].[departments] d
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.departments') j
                ON d.[departmentId] = JSON_VALUE(j.value, '$.departmentId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the departments
            DELETE FROM [dbo].[departments]
            WHERE [departmentId] IN (SELECT JSON_VALUE(value, '$.departmentId') FROM OPENJSON(@pjsonfile, '$.departments'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_departaments_all
IF OBJECT_ID(N'dbo.sp_departaments_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_departaments_all];
GO

--EXEC sp_departments_all

CREATE PROC [dbo].[sp_departaments_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [departmentId],
        [departmentName],
        [createdAt]
    FROM [montanogilberto_smartloans].[dbo].[departments]
    FOR JSON AUTO, ROOT('departments');
END
GO

-- dbo.sp_departaments_one
IF OBJECT_ID(N'dbo.sp_departaments_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_departaments_one];
GO
CREATE PROC [dbo].[sp_departaments_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "departments": [
        {
        "departmentId": "1"
        }
     ]   
    }'
    */

    DECLARE @departmentId INT;

    SET @departmentId = CAST((SELECT JSON_VALUE(value, '$.departmentId') FROM OPENJSON(@pjsonfile, '$.departments')) AS INT);

    SELECT 
        [departmentId]
        ,[departmentName]
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[departments]
    WHERE
        departmentId = @departmentId
    FOR JSON AUTO, ROOT('departments');

END
GO

-- dbo.sp_departments
IF OBJECT_ID(N'dbo.sp_departments', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_departments];
GO
CREATE PROC [dbo].[sp_departments] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "departments": [
        {
            "departmentId": 1,
            "departmentName": "HR",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/
    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.departments'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the departments
            INSERT INTO [dbo].[departments] 
                ([departmentName], [createdAt])
            SELECT
                JSON_VALUE(value, '$.departmentName'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.departments');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the departments
            UPDATE d
            SET 
                d.[departmentName] = JSON_VALUE(j.value, '$.departmentName')
            FROM 
                [dbo].[departments] d
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.departments') j
                ON d.[departmentId] = JSON_VALUE(j.value, '$.departmentId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the departments
            DELETE FROM [dbo].[departments]
            WHERE [departmentId] IN (SELECT JSON_VALUE(value, '$.departmentId') FROM OPENJSON(@pjsonfile, '$.departments'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_departments_all
IF OBJECT_ID(N'dbo.sp_departments_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_departments_all];
GO

CREATE PROC [dbo].[sp_departments_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [departmentId],
        [departmentName],
        [createdAt]
    FROM [montanogilberto_smartloans].[dbo].[departments]
    FOR JSON AUTO, ROOT('departments');
END
GO

-- dbo.sp_departments_one
IF OBJECT_ID(N'dbo.sp_departments_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_departments_one];
GO
CREATE PROC [dbo].[sp_departments_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "departments": [
        {
        "departmentId": "1"
        }
     ]   
    }'
    */

    DECLARE @departmentId INT;

    SET @departmentId = CAST((SELECT JSON_VALUE(value, '$.departmentId') FROM OPENJSON(@pjsonfile, '$.departments')) AS INT);

    SELECT 
        [departmentId]
        ,[departmentName]
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[departments]
    WHERE
        departmentId = @departmentId
    FOR JSON AUTO, ROOT('departments');

END
GO

-- dbo.sp_digitalContracts
IF OBJECT_ID(N'dbo.sp_digitalContracts', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_digitalContracts];
GO

CREATE PROCEDURE [dbo].[sp_digitalContracts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.contract[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.contract[0].companyId')
    DECLARE @contractId      INT           = JSON_VALUE(@pjsonfile, '$.contract[0].contractId')
    DECLARE @loanId          INT           = JSON_VALUE(@pjsonfile, '$.contract[0].loanId')
    DECLARE @clientId        INT           = JSON_VALUE(@pjsonfile, '$.contract[0].clientId')

    IF @action = 'create_contract'
    BEGIN
        DECLARE @conversationId   INT           = JSON_VALUE(@pjsonfile, '$.contract[0].conversationId')
        DECLARE @borrowerClientId INT           = JSON_VALUE(@pjsonfile, '$.contract[0].borrowerClientId')
        DECLARE @lenderClientId   INT           = JSON_VALUE(@pjsonfile, '$.contract[0].lenderClientId')
        DECLARE @borrowerUserId   INT           = JSON_VALUE(@pjsonfile, '$.contract[0].borrowerUserId')
        DECLARE @lenderUserId     INT           = JSON_VALUE(@pjsonfile, '$.contract[0].lenderUserId')
        DECLARE @contractType     NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.contract[0].contractType'), 'contract')
        DECLARE @principalAmount  DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.contract[0].principalAmount')
        DECLARE @interestRate     DECIMAL(6,4)  = JSON_VALUE(@pjsonfile, '$.contract[0].interestRate')
        DECLARE @termMonths       INT           = JSON_VALUE(@pjsonfile, '$.contract[0].termMonths')
        DECLARE @paymentFrequency NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.contract[0].paymentFrequency'), 'monthly')
        DECLARE @startDate        DATETIME2     = JSON_VALUE(@pjsonfile, '$.contract[0].startDate')
        DECLARE @endDate          DATETIME2     = JSON_VALUE(@pjsonfile, '$.contract[0].endDate')
        DECLARE @contractHtml     NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.contract[0].contractHtml')
        DECLARE @notes            NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.contract[0].notes')

        INSERT INTO loanContracts
            (companyId, loanId, conversationId, borrowerClientId, lenderClientId,
             borrowerUserId, lenderUserId, contractType, principalAmount, interestRate,
             termMonths, paymentFrequency, startDate, endDate, contractHtml, notes)
        VALUES
            (@companyId, @loanId, @conversationId, @borrowerClientId, @lenderClientId,
             @borrowerUserId, @lenderUserId, @contractType, @principalAmount, @interestRate,
             @termMonths, @paymentFrequency, @startDate, @endDate, @contractHtml, @notes)

        DECLARE @newContractId INT = SCOPE_IDENTITY()

        SELECT (
            SELECT TOP 1
                contractId, companyId, loanId, borrowerClientId, lenderClientId,
                borrowerUserId, lenderUserId, contractType, principalAmount,
                interestRate, termMonths, paymentFrequency, contractStatus,
                CONVERT(NVARCHAR, startDate, 127) AS startDate,
                CONVERT(NVARCHAR, endDate, 127)   AS endDate,
                CONVERT(NVARCHAR, created_At, 127) AS created_At,
                @borrowerUserId AS targetUserId
            FROM loanContracts WHERE contractId = @newContractId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'sign_contract'
    BEGIN
        DECLARE @signerClientId    INT          = JSON_VALUE(@pjsonfile, '$.contract[0].signerClientId')
        DECLARE @signerUserId      INT          = JSON_VALUE(@pjsonfile, '$.contract[0].signerUserId')
        DECLARE @signerRole        NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.contract[0].signerRole')
        DECLARE @signatureImageUrl NVARCHAR(500)= JSON_VALUE(@pjsonfile, '$.contract[0].signatureImageUrl')
        DECLARE @ipAddress         NVARCHAR(50) = JSON_VALUE(@pjsonfile, '$.contract[0].ipAddress')
        DECLARE @deviceFingerprint NVARCHAR(200)= JSON_VALUE(@pjsonfile, '$.contract[0].deviceFingerprint')
        DECLARE @biometricVerified BIT          = ISNULL(JSON_VALUE(@pjsonfile, '$.contract[0].biometricVerified'), 0)

        INSERT INTO loanContractSignatures
            (contractId, signerClientId, signerUserId, signerRole,
             signatureImageUrl, ipAddress, deviceFingerprint, biometricVerified)
        VALUES
            (@contractId, @signerClientId, @signerUserId, @signerRole,
             @signatureImageUrl, @ipAddress, @deviceFingerprint, @biometricVerified)

        DECLARE @signatureCount INT
        SELECT @signatureCount = COUNT(*) FROM loanContractSignatures WHERE contractId = @contractId

        DECLARE @newStatus NVARCHAR(20) =
            CASE WHEN @signatureCount >= 2 THEN 'fully_signed' ELSE 'borrower_signed' END

        UPDATE loanContracts SET
            contractStatus = @newStatus,
            updated_at     = GETUTCDATE()
        WHERE contractId = @contractId

        DECLARE @signTargetUserId INT
        SELECT @signTargetUserId =
            CASE WHEN @signerRole = 'borrower' THEN lenderUserId ELSE borrowerUserId END
        FROM loanContracts WHERE contractId = @contractId

        SELECT (
            SELECT @contractId AS contractId, @newStatus AS contractStatus,
                   @signatureCount AS signaturesCount, @signTargetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'get_contract'
    BEGIN
        SELECT ISNULL(
            (SELECT TOP 1
                c.contractId, c.companyId, c.loanId, c.conversationId,
                c.borrowerClientId, c.lenderClientId, c.borrowerUserId, c.lenderUserId,
                c.contractType, c.principalAmount, c.interestRate, c.termMonths,
                c.paymentFrequency, c.contractStatus, c.pdfBlobUrl,
                CONVERT(NVARCHAR, c.startDate, 127)   AS startDate,
                CONVERT(NVARCHAR, c.endDate, 127)     AS endDate,
                CONVERT(NVARCHAR, c.created_At, 127)  AS created_At,
                CONVERT(NVARCHAR, c.updated_at, 127)  AS updated_at,
                (SELECT signatureId, signerClientId, signerRole, biometricVerified,
                        CONVERT(NVARCHAR, signedAt, 127) AS signedAt
                 FROM loanContractSignatures
                 WHERE contractId = c.contractId
                 FOR JSON PATH) AS signatures
             FROM loanContracts c
             WHERE c.contractId = @contractId AND c.companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    ELSE IF @action = 'list_contracts'
    BEGIN
        SELECT ISNULL(
            (SELECT contractId, companyId, loanId, contractType, contractStatus,
                    principalAmount, interestRate, termMonths, pdfBlobUrl,
                    borrowerClientId, lenderClientId,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM loanContracts
             WHERE companyId = @companyId
               AND (borrowerClientId = @clientId OR lenderClientId = @clientId)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    ELSE IF @action = 'void_contract'
    BEGIN
        DECLARE @voidSignerUserId INT = JSON_VALUE(@pjsonfile, '$.contract[0].signerUserId')

        UPDATE loanContracts SET
            contractStatus = 'void',
            updated_at     = GETUTCDATE()
        WHERE contractId = @contractId AND companyId = @companyId
          AND contractStatus = 'pending'

        DECLARE @voidTargetUserId INT
        SELECT @voidTargetUserId =
            CASE WHEN borrowerUserId = @voidSignerUserId THEN lenderUserId ELSE borrowerUserId END
        FROM loanContracts WHERE contractId = @contractId

        SELECT (
            SELECT @contractId AS contractId, 'void' AS contractStatus,
                   @voidTargetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'download_pdf'
    BEGIN
        SELECT ISNULL(
            (SELECT TOP 1 contractId, contractType, contractStatus, pdfBlobUrl
             FROM loanContracts
             WHERE contractId = @contractId AND companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_disbursement
IF OBJECT_ID(N'dbo.sp_disbursement', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_disbursement];
GO

CREATE PROCEDURE [dbo].[sp_disbursement]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.disbursement[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].companyId')
    DECLARE @disbursementId  INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].disbursementId')
    DECLARE @loanId          INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].loanId')
    DECLARE @clientId        INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].clientId')

    IF @action = 'initiate'
    BEGIN
        DECLARE @contractId       INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].contractId')
        DECLARE @borrowerClientId INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].borrowerClientId')
        DECLARE @lenderClientId   INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].lenderClientId')
        DECLARE @borrowerUserId   INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].borrowerUserId')
        DECLARE @lenderUserId     INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].lenderUserId')
        DECLARE @amount           DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.disbursement[0].amount')
        DECLARE @currency         NVARCHAR(10)  = ISNULL(JSON_VALUE(@pjsonfile, '$.disbursement[0].currency'), 'MXN')
        DECLARE @transferMethod   NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.disbursement[0].transferMethod')
        DECLARE @initNotes        NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.disbursement[0].notes')

        INSERT INTO loanDisbursements
            (companyId, loanId, contractId, borrowerClientId, lenderClientId,
             borrowerUserId, lenderUserId, amount, currency, disbursementStatus,
             transferMethod, notes)
        VALUES
            (@companyId, @loanId, @contractId, @borrowerClientId, @lenderClientId,
             @borrowerUserId, @lenderUserId, @amount, @currency, 'initiated',
             @transferMethod, @initNotes)

        DECLARE @newDisbId INT = SCOPE_IDENTITY()

        SELECT (
            SELECT disbursementId, companyId, loanId, contractId, disbursementStatus,
                   amount, currency, transferMethod,
                   @lenderUserId AS lenderUserId,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM loanDisbursements WHERE disbursementId = @newDisbId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'confirm_sent'
    BEGIN
        DECLARE @transferReference NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.disbursement[0].transferReference')
        DECLARE @sentNotes         NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.disbursement[0].notes')

        UPDATE loanDisbursements SET
            disbursementStatus = 'sent',
            transferReference  = ISNULL(@transferReference, transferReference),
            sentAt             = GETUTCDATE(),
            notes              = ISNULL(@sentNotes, notes),
            updated_at         = GETUTCDATE()
        WHERE disbursementId = @disbursementId AND companyId = @companyId

        DECLARE @sentBorrowerUserId INT
        DECLARE @sentAmount         DECIMAL(14,2)
        SELECT @sentBorrowerUserId = borrowerUserId, @sentAmount = amount
        FROM loanDisbursements WHERE disbursementId = @disbursementId

        SELECT (
            SELECT @disbursementId AS disbursementId, 'sent' AS disbursementStatus,
                   @sentAmount AS amount, @transferReference AS transferReference,
                   @sentBorrowerUserId AS borrowerUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'confirm_received'
    BEGIN
        UPDATE loanDisbursements SET
            disbursementStatus = 'received',
            receivedAt         = GETUTCDATE(),
            updated_at         = GETUTCDATE()
        WHERE disbursementId = @disbursementId AND companyId = @companyId

        UPDATE dbo.loans SET
            loanStatus       = 'active',
            disbursementDate = GETUTCDATE(),
            updated_at       = GETUTCDATE()
        WHERE loanId = @loanId AND companyId = @companyId

        DECLARE @rcvBorrowerUserId INT
        DECLARE @rcvLenderUserId   INT
        DECLARE @rcvAmount         DECIMAL(14,2)
        SELECT @rcvBorrowerUserId = borrowerUserId,
               @rcvLenderUserId   = lenderUserId,
               @rcvAmount         = amount
        FROM loanDisbursements WHERE disbursementId = @disbursementId

        SELECT (
            SELECT @disbursementId AS disbursementId, 'received' AS disbursementStatus,
                   @rcvAmount AS amount,
                   @rcvBorrowerUserId AS borrowerUserId, @rcvLenderUserId AS lenderUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'get_status'
    BEGIN
        SELECT ISNULL(
            (SELECT TOP 1
                disbursementId, companyId, loanId, contractId, disbursementStatus,
                amount, currency, transferReference, transferMethod,
                borrowerClientId, lenderClientId,
                CONVERT(NVARCHAR, sentAt, 127)     AS sentAt,
                CONVERT(NVARCHAR, receivedAt, 127) AS receivedAt,
                errorNote, notes,
                CONVERT(NVARCHAR, created_At, 127) AS created_At,
                CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM loanDisbursements
             WHERE loanId = @loanId AND companyId = @companyId
             ORDER BY created_At DESC
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    ELSE IF @action = 'list_disbursements'
    BEGIN
        SELECT ISNULL(
            (SELECT disbursementId, loanId, contractId, disbursementStatus,
                    amount, currency, transferMethod,
                    borrowerClientId, lenderClientId,
                    CONVERT(NVARCHAR, sentAt, 127)     AS sentAt,
                    CONVERT(NVARCHAR, receivedAt, 127) AS receivedAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM loanDisbursements
             WHERE companyId = @companyId
               AND (borrowerClientId = @clientId OR lenderClientId = @clientId)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    ELSE IF @action = 'failed'
    BEGIN
        DECLARE @errorNote NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.disbursement[0].errorNote')

        UPDATE loanDisbursements SET
            disbursementStatus = 'failed',
            errorNote          = @errorNote,
            updated_at         = GETUTCDATE()
        WHERE disbursementId = @disbursementId AND companyId = @companyId

        DECLARE @failBorrowerUserId INT
        DECLARE @failLenderUserId   INT
        SELECT @failBorrowerUserId = borrowerUserId,
               @failLenderUserId   = lenderUserId
        FROM loanDisbursements WHERE disbursementId = @disbursementId

        SELECT (
            SELECT @disbursementId AS disbursementId, 'failed' AS disbursementStatus,
                   @errorNote AS errorNote,
                   @failBorrowerUserId AS borrowerUserId, @failLenderUserId AS lenderUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_dropdiagram
IF OBJECT_ID(N'dbo.sp_dropdiagram', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_dropdiagram];
GO

	CREATE PROCEDURE dbo.sp_dropdiagram
	(
		@diagramname 	sysname,
		@owner_id	int	= null
	)
	WITH EXECUTE AS 'dbo'
	AS
	BEGIN
		set nocount on
		declare @theId 			int
		declare @IsDbo 			int
		
		declare @UIDFound 		int
		declare @DiagId			int
	
		if(@diagramname is null)
		begin
			RAISERROR ('Invalid value', 16, 1);
			return -1
		end
	
		EXECUTE AS CALLER;
		select @theId = DATABASE_PRINCIPAL_ID();
		select @IsDbo = IS_MEMBER(N'db_owner'); 
		if(@owner_id is null)
			select @owner_id = @theId;
		REVERT; 
		
		select @DiagId = diagram_id, @UIDFound = principal_id from dbo.sysdiagrams where principal_id = @owner_id and name = @diagramname 
		if(@DiagId IS NULL or (@IsDbo = 0 and @UIDFound <> @theId))
		begin
			RAISERROR ('Diagram does not exist or you do not have permission.', 16, 1)
			return -3
		end
	
		delete from dbo.sysdiagrams where diagram_id = @DiagId;
	
		return 0;
	END
GO

-- dbo.sp_employeeProjectAssignments
IF OBJECT_ID(N'dbo.sp_employeeProjectAssignments', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employeeProjectAssignments];
GO
CREATE PROC [dbo].[sp_employeeProjectAssignments] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "employeeProjectAssignments": [
        {
            "assignmentId": 1,
            "employeeId": 1,
            "projectId": 1,
            "assignmentStartDate": "2021-01-15",
            "assignmentEndDate": null,
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.employeeProjectAssignments'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the employeeProjectAssignments
            INSERT INTO [dbo].[employeeProjectAssignments] 
                ([employeeId], [projectId], [assignmentStartDate], [assignmentEndDate], [createdAt])
            SELECT
                JSON_VALUE(value, '$.employeeId'),
                JSON_VALUE(value, '$.projectId'),
                JSON_VALUE(value, '$.assignmentStartDate'),
                JSON_VALUE(value, '$.assignmentEndDate'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.employeeProjectAssignments');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the employeeProjectAssignments
            UPDATE epa
            SET 
                epa.[employeeId] = JSON_VALUE(j.value, '$.employeeId'),
                epa.[projectId] = JSON_VALUE(j.value, '$.projectId'),
                epa.[assignmentStartDate] = JSON_VALUE(j.value, '$.assignmentStartDate'),
                epa.[assignmentEndDate] = JSON_VALUE(j.value, '$.assignmentEndDate')
            FROM 
                [dbo].[employeeProjectAssignments] epa
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.employeeProjectAssignments') j
                ON epa.[assignmentId] = JSON_VALUE(j.value, '$.assignmentId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the employeeProjectAssignments
            DELETE FROM [dbo].[employeeProjectAssignments]
            WHERE [assignmentId] IN (SELECT JSON_VALUE(value, '$.assignmentId') FROM OPENJSON(@pjsonfile, '$.employeeProjectAssignments'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_employeeProjectAssignments_all
IF OBJECT_ID(N'dbo.sp_employeeProjectAssignments_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employeeProjectAssignments_all];
GO

CREATE PROC [dbo].[sp_employeeProjectAssignments_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [assignmentId],
        [employeeId],
        [projectId],
        ISNULL([assignmentStartDate], '') AS assignmentStartDate,
        ISNULL([assignmentEndDate], '') AS assignmentEndDate,
        [createdAt]
    FROM [montanogilberto_smartloans].[dbo].[employeeProjectAssignments]
    FOR JSON AUTO, ROOT('employeeProjectAssignments');
END
GO

-- dbo.sp_employeeProjectAssignments_one
IF OBJECT_ID(N'dbo.sp_employeeProjectAssignments_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employeeProjectAssignments_one];
GO
CREATE PROC [dbo].[sp_employeeProjectAssignments_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "employeeProjectAssignments": [
        {
        "assignmentId": "1"
        }
     ]   
    }'
    */

    DECLARE @assignmentId INT;

    SET @assignmentId = CAST((SELECT JSON_VALUE(value, '$.assignmentId') FROM OPENJSON(@pjsonfile, '$.employeeProjectAssignments')) AS INT);

    SELECT 
        [assignmentId]
        ,[employeeId]
        ,[projectId]
        ,ISNULL([assignmentStartDate], '') AS assignmentStartDate
        ,ISNULL([assignmentEndDate], '') AS assignmentEndDate
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[employeeProjectAssignments]
    WHERE
        assignmentId = @assignmentId
    FOR JSON AUTO, ROOT('employeeProjectAssignments');

END
GO

-- dbo.sp_employees
IF OBJECT_ID(N'dbo.sp_employees', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employees];
GO
CREATE PROC [dbo].[sp_employees] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "employees": [
        {
            "employeeId": 1,
            "firstName": "John",
            "lastName": "Doe",
            "email": "john.doe@example.com",
            "phoneNumber": "123-456-7890",
            "address": "123 Main St, City, Country",
            "employmentTypeId": 1,
            "position": "Engineer",
            "departmentId": 2,
            "statusId": 1,
            "hireDate": "2021-01-15",
            "endDate": null,
            "emergencyContactName": "Jane Doe",
            "emergencyContactRelationship": "Spouse",
            "emergencyContactPhone": "123-456-7891",
            "notes": "Notes about John Doe",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/
    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.employees'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the employees
            INSERT INTO [dbo].[employees] 
                ([firstName], [lastName], [email], [phoneNumber], [address], [employmentTypeId], 
                 [position], [departmentId], [statusId], [hireDate], [endDate], 
                 [emergencyContactName], [emergencyContactRelationship], [emergencyContactPhone], [notes], [createdAt])
            SELECT
                JSON_VALUE(value, '$.firstName'),
                JSON_VALUE(value, '$.lastName'),
                JSON_VALUE(value, '$.email'),
                JSON_VALUE(value, '$.phoneNumber'),
                JSON_VALUE(value, '$.address'),
                JSON_VALUE(value, '$.employmentTypeId'),
                JSON_VALUE(value, '$.position'),
                JSON_VALUE(value, '$.departmentId'),
                JSON_VALUE(value, '$.statusId'),
                JSON_VALUE(value, '$.hireDate'),
                JSON_VALUE(value, '$.endDate'),
                JSON_VALUE(value, '$.emergencyContactName'),
                JSON_VALUE(value, '$.emergencyContactRelationship'),
                JSON_VALUE(value, '$.emergencyContactPhone'),
                JSON_VALUE(value, '$.notes'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.employees');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the employees
            UPDATE e
            SET 
                e.[firstName] = JSON_VALUE(j.value, '$.firstName'),
                e.[lastName] = JSON_VALUE(j.value, '$.lastName'),
                e.[email] = JSON_VALUE(j.value, '$.email'),
                e.[phoneNumber] = JSON_VALUE(j.value, '$.phoneNumber'),
                e.[address] = JSON_VALUE(j.value, '$.address'),
                e.[employmentTypeId] = JSON_VALUE(j.value, '$.employmentTypeId'),
                e.[position] = JSON_VALUE(j.value, '$.position'),
                e.[departmentId] = JSON_VALUE(j.value, '$.departmentId'),
                e.[statusId] = JSON_VALUE(j.value, '$.statusId'),
                e.[hireDate] = JSON_VALUE(j.value, '$.hireDate'),
                e.[endDate] = JSON_VALUE(j.value, '$.endDate'),
                e.[emergencyContactName] = JSON_VALUE(j.value, '$.emergencyContactName'),
                e.[emergencyContactRelationship] = JSON_VALUE(j.value, '$.emergencyContactRelationship'),
                e.[emergencyContactPhone] = JSON_VALUE(j.value, '$.emergencyContactPhone'),
                e.[notes] = JSON_VALUE(j.value, '$.notes')
            FROM 
                [dbo].[employees] e
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.employees') j
                ON e.[employeeId] = JSON_VALUE(j.value, '$.employeeId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the employees
            DELETE FROM [dbo].[employees]
            WHERE [employeeId] IN (SELECT JSON_VALUE(value, '$.employeeId') FROM OPENJSON(@pjsonfile, '$.employees'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_employees_all
IF OBJECT_ID(N'dbo.sp_employees_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employees_all];
GO

CREATE PROC [dbo].[sp_employees_all]
AS
SET NOCOUNT ON

BEGIN
SELECT 
     e.[employeeId]
    ,e.[firstName]
    ,e.[lastName]
    ,e.[email]
    ,e.[phoneNumber]
    ,e.[address]
    ,et.[employmentType]
    ,e.[position]
    ,d.[departmentName]
    ,s.[status]
    ,e.[hireDate]
    ,e.[endDate]
    ,e.[emergencyContactName]
    ,e.[emergencyContactRelationship]
    ,e.[emergencyContactPhone]
    ,e.[notes]
    ,e.[createdAt]
  FROM 
    [dbo].[employees] e
    INNER JOIN [dbo].[employmentTypes] et ON et.[employmentTypeId] = e.[employmentTypeId]
    INNER JOIN [dbo].[departments] d ON d.[departmentId] = e.[departmentId]
    INNER JOIN [dbo].[statuses] s ON s.[statusId] = e.[statusId]
    FOR JSON AUTO, ROOT('employees');
END
GO

-- dbo.sp_employees_one
IF OBJECT_ID(N'dbo.sp_employees_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employees_one];
GO
CREATE PROC [dbo].[sp_employees_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "employees": [
        {
        "employeeId": "1"
        }
     ]   
    }'
    */

    DECLARE @employeeId INT;

    SET @employeeId = CAST((SELECT JSON_VALUE(value, '$.employeeId') FROM OPENJSON(@pjsonfile, '$.employees')) AS INT);

    SELECT 
        [employeeId]
        ,[firstName]
        ,[lastName]
        ,[email]
        ,ISNULL([phoneNumber], '') AS phoneNumber
        ,ISNULL([address], '') AS address
        ,[employmentTypeId]
        ,ISNULL([position], '') AS position
        ,[departmentId]
        ,[statusId]
        ,ISNULL([hireDate], '') AS hireDate
        ,ISNULL([endDate], '') AS endDate
        ,ISNULL([emergencyContactName], '') AS emergencyContactName
        ,ISNULL([emergencyContactRelationship], '') AS emergencyContactRelationship
        ,ISNULL([emergencyContactPhone], '') AS emergencyContactPhone
        ,ISNULL([notes], '') AS notes
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[employees]
    WHERE
        employeeId = @employeeId
    FOR JSON AUTO, ROOT('employees');

END
GO

-- dbo.sp_employmentTypes
IF OBJECT_ID(N'dbo.sp_employmentTypes', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employmentTypes];
GO
CREATE PROC [dbo].[sp_employmentTypes] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "employmentTypes": [
        {
            "employmentTypeId": 1,
            "employmentType": "permanent",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/
    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.employmentTypes'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the employmentTypes
            INSERT INTO [dbo].[employmentTypes] 
                ([employmentType], [createdAt])
            SELECT
                JSON_VALUE(value, '$.employmentType'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.employmentTypes');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the employmentTypes
            UPDATE e
            SET 
                e.[employmentType] = JSON_VALUE(j.value, '$.employmentType')
            FROM 
                [dbo].[employmentTypes] e
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.employmentTypes') j
                ON e.[employmentTypeId] = JSON_VALUE(j.value, '$.employmentTypeId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the employmentTypes
            DELETE FROM [dbo].[employmentTypes]
            WHERE [employmentTypeId] IN (SELECT JSON_VALUE(value, '$.employmentTypeId') FROM OPENJSON(@pjsonfile, '$.employmentTypes'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_employmentTypes_all
IF OBJECT_ID(N'dbo.sp_employmentTypes_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employmentTypes_all];
GO

CREATE PROC [dbo].[sp_employmentTypes_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [employmentTypeId],
        [employmentType],
        [createdAt]
    FROM [montanogilberto_smartloans].[dbo].[employmentTypes]
    FOR JSON AUTO, ROOT('employmentTypes');
END
GO

-- dbo.sp_employmentTypes_one
IF OBJECT_ID(N'dbo.sp_employmentTypes_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_employmentTypes_one];
GO
CREATE PROC [dbo].[sp_employmentTypes_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "employmentTypes": [
        {
        "employmentTypeId": "1"
        }
     ]   
    }'
    */

    DECLARE @employmentTypeId INT;

    SET @employmentTypeId = CAST((SELECT JSON_VALUE(value, '$.employmentTypeId') FROM OPENJSON(@pjsonfile, '$.employmentTypes')) AS INT);

    SELECT 
        [employmentTypeId]
        ,[employmentType]
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[employmentTypes]
    WHERE
        employmentTypeId = @employmentTypeId
    FOR JSON AUTO, ROOT('employmentTypes');

END
GO

-- dbo.sp_exchangeRates
IF OBJECT_ID(N'dbo.sp_exchangeRates', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_exchangeRates];
GO

CREATE PROC [dbo].[sp_exchangeRates] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

  /*
  DECLARE @pjsonfile VARCHAR(MAX) = '{
    "exchangeRates": [
      {
        "exchangeRateId": 1,
        "fromCurrency": "MXN",
        "toCurrency": "USD",
        "rate": 0.05812345,
        "asOfDate": "2026-01-15",
        "source": "banxico",
        "action": "1"
      }
    ]
  }';
  */

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  {
    "result": [
      { "value": "", "msg": "", "error": "" }
    ]
  }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
                 FROM OPENJSON(@pjsonfile, '$.exchangeRates'));

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.exchangeRates (fromCurrency, toCurrency, rate, asOfDate, source)
      SELECT
        JSON_VALUE(value, '$.fromCurrency'),
        ISNULL(NULLIF(JSON_VALUE(value, '$.toCurrency'), ''), 'USD'),
        TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(value, '$.rate')),
        TRY_CONVERT(DATE, JSON_VALUE(value, '$.asOfDate')),
        JSON_VALUE(value, '$.source')
      FROM OPENJSON(@pjsonfile, '$.exchangeRates');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE er
      SET
        er.fromCurrency = JSON_VALUE(j.value, '$.fromCurrency'),
        er.toCurrency   = ISNULL(NULLIF(JSON_VALUE(j.value, '$.toCurrency'), ''), 'USD'),
        er.rate         = TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(j.value, '$.rate')),
        er.asOfDate     = TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.asOfDate')),
        er.source       = JSON_VALUE(j.value, '$.source')
      FROM dbo.exchangeRates er
      INNER JOIN OPENJSON(@pjsonfile, '$.exchangeRates') j
        ON er.exchangeRateId = TRY_CONVERT(INT, JSON_VALUE(j.value, '$.exchangeRateId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.exchangeRates
      WHERE exchangeRateId IN (
        SELECT TRY_CONVERT(INT, JSON_VALUE(value, '$.exchangeRateId'))
        FROM OPENJSON(@pjsonfile, '$.exchangeRates')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH

  SELECT
    JSON_VALUE(value, '$.value') AS [value],
    JSON_VALUE(value, '$.msg')   AS [msg],
    JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_exchangeRates_by_day
IF OBJECT_ID(N'dbo.sp_exchangeRates_by_day', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_exchangeRates_by_day];
GO

create PROC [dbo].[sp_exchangeRates_by_day]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @asOfDate DATE =
        TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.exchangeRates[0].asOfDate'));

    -- If no date provided, return latest
    IF @asOfDate IS NULL
    BEGIN
        SELECT TOP (1)
            [exchangeRateId],
            [fromCurrency],
            [toCurrency],
            [rate],
            [asOfDate],
            ISNULL([source], '')      AS [source],
            [createdAt]
            --ISNULL([updatedAt], '')   AS [updatedAt]
        FROM [dbo].[exchangeRates]
        ORDER BY [asOfDate] DESC
        FOR JSON AUTO, ROOT('exchangeRates');

        RETURN;
    END

    -- Return exchange rate for specific day
    SELECT TOP (1)
        [exchangeRateId],
        [fromCurrency],
        [toCurrency],
        [rate],
        [asOfDate],
        ISNULL([source], '')      AS [source],
        [createdAt]
        --ISNULL([updatedAt], '')   AS [updatedAt]
    FROM [dbo].[exchangeRates]
    WHERE CAST([asOfDate] AS DATE) = @asOfDate
    ORDER BY [asOfDate] DESC
    FOR JSON AUTO, ROOT('exchangeRates');

END
GO

-- dbo.sp_exchangeRates_latestToUsd
IF OBJECT_ID(N'dbo.sp_exchangeRates_latestToUsd', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_exchangeRates_latestToUsd];
GO

CREATE   PROC dbo.sp_exchangeRates_latestToUsd
  @fromCurrency CHAR(3),
  @asOfDate     DATE = NULL
AS
BEGIN
  SET NOCOUNT ON;

  -- Normaliza parámetros
  SET @fromCurrency = UPPER(@fromCurrency);

  IF @asOfDate IS NULL
    SET @asOfDate = CAST(SYSUTCDATETIME() AS DATE);

  -- Caso trivial
  IF @fromCurrency = 'USD'
  BEGIN
    SELECT
      CAST(1.0 AS DECIMAL(18,8)) AS rateToUsd,
      @asOfDate                   AS asOfDate,
      CAST(NULL AS NVARCHAR(100)) AS source,
      CAST(NULL AS INT)           AS exchangeRateId;
    RETURN;
  END

  ;WITH cte AS (
    SELECT TOP (1)
      er.exchangeRateId,
      er.rate,
      er.asOfDate,
      er.source
    FROM dbo.exchangeRates er
    WHERE er.fromCurrency = @fromCurrency
      AND er.toCurrency = 'USD'
      AND er.asOfDate <= @asOfDate
    ORDER BY er.asOfDate DESC, er.exchangeRateId DESC
  )
  SELECT
    cte.rate          AS rateToUsd,
    cte.asOfDate      AS asOfDate,
    cte.source        AS source,
    cte.exchangeRateId AS exchangeRateId
  FROM cte;
END
GO

-- dbo.sp_exchangeRates_upsert
IF OBJECT_ID(N'dbo.sp_exchangeRates_upsert', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_exchangeRates_upsert];
GO

CREATE   PROC dbo.sp_exchangeRates_upsert
  @pjsonfile VARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '';

  BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH J AS (
      SELECT
        UPPER(JSON_VALUE(value,'$.fromCurrency')) AS fromCurrency,
        UPPER(ISNULL(NULLIF(JSON_VALUE(value,'$.toCurrency'),''),'USD')) AS toCurrency,
        TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(value,'$.rate')) AS rate,
        TRY_CONVERT(DATE, JSON_VALUE(value,'$.asOfDate')) AS asOfDate,
        NULLIF(JSON_VALUE(value,'$.source'),'') AS [source]
      FROM OPENJSON(@pjsonfile,'$.exchangeRates')
    )
    MERGE dbo.exchangeRates AS t
    USING J AS s
      ON  t.fromCurrency = s.fromCurrency
      AND t.toCurrency   = s.toCurrency
      AND t.asOfDate     = s.asOfDate
    WHEN MATCHED THEN
      UPDATE SET
        t.rate   = s.rate,
        t.source = COALESCE(s.source, t.source)
    WHEN NOT MATCHED THEN
      INSERT (fromCurrency,toCurrency,rate,asOfDate,[source])
      VALUES (s.fromCurrency,s.toCurrency,s.rate,s.asOfDate,s.source);

    COMMIT TRANSACTION;
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Upsert OK');
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);
  END CATCH

  SELECT
    JSON_VALUE(value,'$.value') AS [value],
    JSON_VALUE(value,'$.msg')   AS [msg],
    JSON_VALUE(value,'$.error') AS [error]
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_expense
IF OBJECT_ID(N'dbo.sp_expense', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_expense];
GO

/*
  dbo.sp_expenses

  Actions:
    1 = INSERT (single expense with multiple products)
    2 = UPDATE (header only)
    3 = DELETE (by expenseId)

  Insert behavior (action=1):
    - Accepts either:
      A) expenses[0].products (preferred)
      B) multiple elements in expenses[] (coalesced into one header + many products)
    - Creates ONE row in dbo.expenses
    - Creates one row per product in dbo.expenseDetails
    - Creates rows in dbo.expenseDetailOptions from each product's options,
      linked via expenseDetailId captured with OUTPUT.

  Notes:
    - Uses ISJSON/OPENJSON/JSON_VALUE/JSON_QUERY only.
*/

CREATE   PROC [dbo].[sp_expense]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  /*
  -- Sample payload
  DECLARE @pjsonfile NVARCHAR(MAX) = '
  {
    "expenses": [
      {
        "action": 1,
        "total": 430.50,
        "paymentMethod": "Tarjeta",
        "paymentDate": "2025-10-23T22:30:00",
        "userId": 1,
        "supplierId": 7,
        "companyId": 1,
        "products": [
          {
            "productId": 1,
            "options": {
              "productOptionId": 1,
              "choices": [
                { "productOptionChoiceId": 10, "name": "",      "price": -50.00 },
                { "productOptionChoiceId": 11, "name": "Petit", "price": -30.00 }
              ]
            }
          },
          {
            "productId": 2,
            "options": {
              "productOptionId": 5,
              "choices": [
                { "productOptionChoiceId": 42, "name": "Grande", "price": 20.00 }
              ]
            }
          }
        ]
      }
    ]
  }';
  */

  DECLARE
    @Outputmessage NVARCHAR(MAX) = N'{"result":[{"value":"","msg":"","error":""}]}',
    @Error NVARCHAR(500) = N'';

  BEGIN TRY
    IF @pjsonfile IS NULL OR TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].action')) IS NULL
      RAISERROR('Invalid or missing JSON/action.', 16, 1);

    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].action'));

    -- Validate company for INSERT/UPDATE
    IF @action IN (1,2)
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM OPENJSON(@pjsonfile, '$.expenses') WITH (companyId INT '$.companyId') j
        WHERE j.companyId IS NULL
      ) RAISERROR('companyId is required for all rows.', 16, 1);

      IF EXISTS (
        SELECT 1
        FROM OPENJSON(@pjsonfile, '$.expenses') WITH (companyId INT '$.companyId') j
        WHERE NOT EXISTS (SELECT 1 FROM dbo.companies c WHERE c.companyId = j.companyId)
      ) RAISERROR('One or more companyId values do not exist.', 16, 1);
    END

    BEGIN TRAN;

    IF @action = 1
    BEGIN
      --------------------------------------------------------------------------
      -- Build header + normalized @Products
      --------------------------------------------------------------------------
      DECLARE
        @header_total         DECIMAL(10,2) = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile, '$.expenses[0].total')),
        @header_paymentMethod NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.expenses[0].paymentMethod'),
        @header_paymentDate   DATETIME2     = TRY_CONVERT(DATETIME2, JSON_VALUE(@pjsonfile, '$.expenses[0].paymentDate')),
        @header_userId        INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].userId')),
        @header_supplierId    INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].supplierId')),
        @header_companyId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].companyId'));

      IF @header_userId IS NULL OR @header_supplierId IS NULL OR @header_companyId IS NULL
        RAISERROR('userId, supplierId, and companyId are required for INSERT.', 16, 1);

      -- If user sends multiple entries in expenses[], enforce same header fields
      IF EXISTS (
        SELECT 1
        FROM OPENJSON(@pjsonfile, '$.expenses') j
        WHERE TRY_CONVERT(INT, JSON_VALUE(j.value,'$.companyId'))   <> @header_companyId
           OR TRY_CONVERT(INT, JSON_VALUE(j.value,'$.userId'))      <> @header_userId
           OR TRY_CONVERT(INT, JSON_VALUE(j.value,'$.supplierId'))  <> @header_supplierId
           OR COALESCE(JSON_VALUE(j.value,'$.paymentMethod'),N'')   <> COALESCE(@header_paymentMethod,N'')
           OR COALESCE(TRY_CONVERT(DATETIME2, JSON_VALUE(j.value,'$.paymentDate')), '19000101')
              <> COALESCE(@header_paymentDate, '19000101')
      )
        RAISERROR('When sending multiple entries, header fields must match.', 16, 1);

      -- total: use header total, else sum totals provided per expenses[] entries
      DECLARE @sum_total DECIMAL(10,2);
      SELECT @sum_total = SUM(TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(j.value, '$.total')))
      FROM OPENJSON(@pjsonfile, '$.expenses') j;

      DECLARE @final_total DECIMAL(10,2) = COALESCE(@header_total, @sum_total, 0);

      DECLARE @Products TABLE
      (
        idx         INT IDENTITY(1,1) PRIMARY KEY,
        productId   INT           NOT NULL,
        optionsJson NVARCHAR(MAX) NULL
      );

      -- Preferred: expenses[0].products[]
      IF ISJSON(JSON_QUERY(@pjsonfile, '$.expenses[0].products')) = 1
      BEGIN
        INSERT INTO @Products (productId, optionsJson)
        SELECT TRY_CONVERT(INT, JSON_VALUE(p.value, '$.productId')),
               JSON_QUERY(p.value, '$.options')
        FROM OPENJSON(JSON_QUERY(@pjsonfile, '$.expenses[0].products')) p;
      END
      ELSE
      BEGIN
        -- Fallback: multiple elements with productId directly inside each expenses[] item
        INSERT INTO @Products (productId, optionsJson)
        SELECT TRY_CONVERT(INT, JSON_VALUE(j.value,'$.productId')),
               JSON_QUERY(j.value, '$.options')
        FROM OPENJSON(@pjsonfile, '$.expenses') j;
      END

      IF NOT EXISTS (SELECT 1 FROM @Products WHERE productId IS NOT NULL)
        RAISERROR('No products found. Provide expenses[0].products[] or entries with productId.', 16, 1);

      --------------------------------------------------------------------------
      -- Insert expense header
      --------------------------------------------------------------------------
      DECLARE @expenseId INT;

      INSERT INTO dbo.expenses (orderId, total, paymentMethod, paymentDate, userId, supplierId, companyId)
      VALUES (NULL, @final_total, @header_paymentMethod, COALESCE(@header_paymentDate, SYSUTCDATETIME()),
              @header_userId, @header_supplierId, @header_companyId);

      SET @expenseId = SCOPE_IDENTITY();

      --------------------------------------------------------------------------
      -- STAGING + MERGE to get (idx -> expenseDetailId) mapping
      --------------------------------------------------------------------------
      DECLARE @Staging TABLE (
        idx INT PRIMARY KEY,
        expenseId INT NOT NULL,
        productId INT NOT NULL
      );

      INSERT INTO @Staging (idx, expenseId, productId)
      SELECT idx, @expenseId, productId
      FROM @Products
      WHERE productId IS NOT NULL;

      DECLARE @ProductMap TABLE (
        idx INT PRIMARY KEY,
        expenseDetailId INT NOT NULL
      );

      MERGE dbo.expenseDetails AS tgt
      USING @Staging AS S
         ON 1 = 0
      WHEN NOT MATCHED THEN
        INSERT (expenseId, productId)
        VALUES (S.expenseId, S.productId)
      OUTPUT S.idx, inserted.expenseDetailId
        INTO @ProductMap (idx, expenseDetailId);

      --------------------------------------------------------------------------
      -- Insert options (linked via @ProductMap)
      --------------------------------------------------------------------------

      -- A) options.choices array
      INSERT INTO dbo.expenseDetailOptions (expenseDetailId, productOptionId, productOptionChoiceId)
      SELECT
        M.expenseDetailId,
        TRY_CONVERT(INT, JSON_VALUE(P.optionsJson, '$.productOptionId')),
        TRY_CONVERT(INT, JSON_VALUE(C.value, '$.productOptionChoiceId'))
      FROM @Products AS P
      JOIN @ProductMap AS M
        ON M.idx = P.idx
      CROSS APPLY OPENJSON(P.optionsJson, '$.choices') AS C
      WHERE ISJSON(P.optionsJson) = 1
        AND EXISTS (SELECT 1 FROM OPENJSON(P.optionsJson, '$.choices'))
        AND TRY_CONVERT(INT, JSON_VALUE(P.optionsJson, '$.productOptionId')) IS NOT NULL
        AND TRY_CONVERT(INT, JSON_VALUE(C.value, '$.productOptionChoiceId')) IS NOT NULL;

      -- B) single OptionChoice object
      INSERT INTO dbo.expenseDetailOptions (expenseDetailId, productOptionId, productOptionChoiceId)
      SELECT
        M.expenseDetailId,
        TRY_CONVERT(INT, JSON_VALUE(P.optionsJson, '$.productOptionId')),
        TRY_CONVERT(INT, JSON_VALUE(JSON_QUERY(P.optionsJson, '$.OptionChoice'), '$.productOptionChoiceId'))
      FROM @Products AS P
      JOIN @ProductMap AS M
        ON M.idx = P.idx
      WHERE ISJSON(P.optionsJson) = 1
        AND JSON_VALUE(JSON_QUERY(P.optionsJson, '$.OptionChoice'), '$.productOptionChoiceId') IS NOT NULL
        AND TRY_CONVERT(INT, JSON_VALUE(P.optionsJson, '$.productOptionId')) IS NOT NULL
        AND TRY_CONVERT(INT, JSON_VALUE(JSON_QUERY(P.optionsJson, '$.OptionChoice'), '$.productOptionChoiceId')) IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM OPENJSON(P.optionsJson, '$.choices'));

      -- Return the expenseId
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@expenseId AS NVARCHAR(20)));
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   N'Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      ;WITH J AS (
        SELECT *
        FROM OPENJSON(@pjsonfile, '$.expenses')
        WITH (
          expenseId      INT            '$.expenseId',
          orderId        INT            '$.orderId',
          total          DECIMAL(10,2)  '$.total',
          paymentMethod  NVARCHAR(50)   '$.paymentMethod',
          paymentDate    DATETIME2      '$.paymentDate',
          userId         INT            '$.userId',
          supplierId     INT            '$.supplierId',
          companyId      INT            '$.companyId'
        )
      )
      UPDATE e
         SET orderId       = COALESCE(j.orderId, e.orderId),
             total         = COALESCE(j.total, e.total),
             paymentMethod = COALESCE(j.paymentMethod, e.paymentMethod),
             paymentDate   = COALESCE(j.paymentDate, e.paymentDate),
             userId        = COALESCE(j.userId, e.userId),
             supplierId    = COALESCE(j.supplierId, e.supplierId),
             companyId     = COALESCE(j.companyId, e.companyId)
      FROM dbo.expenses AS e
      JOIN J AS j ON j.expenseId = e.expenseId;

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', N'Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE e
      FROM dbo.expenses AS e
      JOIN OPENJSON(@pjsonfile, '$.expenses') WITH (expenseId INT '$.expenseId') j
        ON j.expenseId = e.expenseId;

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', N'Deleted Successfully');
    END
    ELSE
    BEGIN
      RAISERROR('Invalid action. Use 1=INSERT, 2=UPDATE, 3=DELETE.', 16, 1);
    END

    COMMIT TRAN;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;

    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH;

  SELECT
      JSON_VALUE(value, '$.value') AS [value],
      JSON_VALUE(value, '$.msg')   AS [msg],
      JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_expense_all
IF OBJECT_ID(N'dbo.sp_expense_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_expense_all];
GO

CREATE   PROC [dbo].[sp_expense_all]
AS
BEGIN
    SET NOCOUNT ON;

    -- Verificar si hay datos en expenses
    IF EXISTS (SELECT 1 FROM [dbo].[expenses])
    BEGIN
        -- Devolver registros de expenses en formato JSON
        SELECT 
            e.expenseId,
            e.orderId,
            e.total,
            e.paymentMethod,
            e.paymentDate,
            e.userId,
            e.supplierId,
            e.companyId
        FROM [dbo].[expenses] e
        FOR JSON AUTO, ROOT('expenses');
    END
    ELSE
    BEGIN
        -- Si no hay datos, regresar JSON vacío con la raíz 'expenses'
        SELECT '[]' AS [expenses]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO

-- dbo.sp_fundingTransactions
IF OBJECT_ID(N'dbo.sp_fundingTransactions', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_fundingTransactions];
GO

CREATE PROCEDURE [dbo].[sp_fundingTransactions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action    NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].action')
    DECLARE @companyId INT          = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].companyId')

    -- ── declare ──────────────────────────────────────────────
    -- Lender already sent the SPEI from their own bank; this just records
    -- it. Requires the paymentIntent (RFC-002 D14) to still be OPEN and of
    -- type FUNDING for this exact loan/lender/borrower -- refuses to create
    -- an orphan declaration nobody expected.
    IF @action = 'declare'
    BEGIN
        DECLARE @loanId           INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].loanId')
        DECLARE @intentId         INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].intentId')
        DECLARE @lenderClientId   INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].lenderClientId')
        DECLARE @borrowerClientId INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].borrowerClientId')
        DECLARE @amountMXN        DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].amountMXN')
        DECLARE @transferDate     DATETIME2     = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].transferDate')

        IF NOT EXISTS (
            SELECT 1 FROM dbo.paymentIntents
            WHERE paymentIntentId = @intentId AND companyId = @companyId AND loanId = @loanId
              AND intentType = 'FUNDING' AND status = 'OPEN'
              AND payerClientId = @lenderClientId AND payeeClientId = @borrowerClientId
        )
        BEGIN
            SELECT '{"error":"No hay un paymentIntent FUNDING abierto para este préstamo/prestamista/prestatario."}' AS [jsonResult]
            RETURN
        END

        IF EXISTS (SELECT 1 FROM dbo.fundingTransactions WHERE loanId = @loanId)
        BEGIN
            SELECT '{"error":"Este préstamo ya tiene una declaración de fondeo."}' AS [jsonResult]
            RETURN
        END

        BEGIN TRANSACTION;

        INSERT INTO dbo.fundingTransactions
            (companyId, loanId, intentId, lenderClientId, borrowerClientId,
             amountMXN, transferDate, status, declaredAt)
        VALUES
            (@companyId, @loanId, @intentId, @lenderClientId, @borrowerClientId,
             @amountMXN, @transferDate, 'PENDING_CONFIRMATION', GETUTCDATE())

        DECLARE @newFundingId INT = SCOPE_IDENTITY()

        -- sp_paymentIntents has no 'declare' action yet (only
        -- create/expire_due/cancel/list) -- direct UPDATE here until that's
        -- added; CK_paymentIntents_status already allows 'DECLARED'.
        UPDATE dbo.paymentIntents
        SET status = 'DECLARED', updated_at = GETUTCDATE()
        WHERE paymentIntentId = @intentId

        -- TODO(paymentHistory, D16): INSERT audit row here once that table
        -- exists — entity='fundingTransactions', action='DECLARE'.

        COMMIT TRANSACTION;

        SELECT (
            SELECT fundingTransactionId, companyId, loanId, intentId, lenderClientId,
                   borrowerClientId, amountMXN,
                   CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                   status,
                   CONVERT(NVARCHAR, declaredAt, 127) AS declaredAt,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM dbo.fundingTransactions WHERE fundingTransactionId = @newFundingId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── confirm ──────────────────────────────────────────────
    -- D5: only the BORROWER confirms — it's their money that arrived, the
    -- system never auto-confirms on the lender's word alone.
    ELSE IF @action = 'confirm'
    BEGIN
        DECLARE @confirmId       INT = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].fundingTransactionId')
        DECLARE @confirmByClient INT = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].confirmedByClientId')

        DECLARE @confirmBorrowerId INT, @confirmLoanId INT
        SELECT @confirmBorrowerId = borrowerClientId, @confirmLoanId = loanId
        FROM dbo.fundingTransactions
        WHERE fundingTransactionId = @confirmId AND companyId = @companyId AND status = 'PENDING_CONFIRMATION'

        IF @confirmBorrowerId IS NULL
        BEGIN
            SELECT '{"error":"Declaración no encontrada o ya resuelta."}' AS [jsonResult]
            RETURN
        END
        IF @confirmByClient <> @confirmBorrowerId
        BEGIN
            SELECT '{"error":"Solo el prestatario puede confirmar la recepción del depósito."}' AS [jsonResult]
            RETURN
        END

        UPDATE dbo.fundingTransactions
        SET status = 'CONFIRMED', confirmedAt = GETUTCDATE(),
            confirmedByClientId = @confirmByClient, updated_at = GETUTCDATE()
        WHERE fundingTransactionId = @confirmId

        -- TODO(paymentHistory, D16) + TODO(sp_loans transition, D13):
        -- orchestrated by the calling Python module, not here — this SP
        -- stays scoped to its own table.

        SELECT (
            SELECT @confirmId AS fundingTransactionId, @confirmLoanId AS loanId, 'CONFIRMED' AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── reject ───────────────────────────────────────────────
    -- Borrower says the money never arrived. Also borrower-only, mirroring
    -- confirm — the payee is the one with standing to dispute non-receipt.
    ELSE IF @action = 'reject'
    BEGIN
        DECLARE @rejectId       INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].fundingTransactionId')
        DECLARE @rejectByClient INT           = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].rejectedByClientId')
        DECLARE @rejectReason   NVARCHAR(300) = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].rejectReason')

        DECLARE @rejectBorrowerId INT
        SELECT @rejectBorrowerId = borrowerClientId
        FROM dbo.fundingTransactions
        WHERE fundingTransactionId = @rejectId AND companyId = @companyId AND status = 'PENDING_CONFIRMATION'

        IF @rejectBorrowerId IS NULL
        BEGIN
            SELECT '{"error":"Declaración no encontrada o ya resuelta."}' AS [jsonResult]
            RETURN
        END
        IF @rejectByClient <> @rejectBorrowerId
        BEGIN
            SELECT '{"error":"Solo el prestatario puede rechazar una declaración de depósito."}' AS [jsonResult]
            RETURN
        END

        UPDATE dbo.fundingTransactions
        SET status = 'REJECTED', rejectReason = @rejectReason, updated_at = GETUTCDATE()
        WHERE fundingTransactionId = @rejectId

        SELECT (
            SELECT @rejectId AS fundingTransactionId, 'REJECTED' AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── escalate_due ─────────────────────────────────────────
    -- Cron-invoked, mirrors sp_paymentIntents' expire_due shape.
    -- @escalateAfterDays is caller-supplied, not hardcoded: RFC-002's own
    -- "Alternativas descartadas" leaves the exact threshold as an open,
    -- business-tunable parameter, not an architecture decision.
    -- NOTE: RFC-002 §6 says this only fires when evidence exists
    -- (transferEvidence, not yet built) — until then this sweeps ALL
    -- overdue PENDING_CONFIRMATION rows regardless of evidence; tighten
    -- this WHERE clause once transferEvidence exists.
    ELSE IF @action = 'escalate_due'
    BEGIN
        DECLARE @escalateAfterDays INT = ISNULL(JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].escalateAfterDays'), 2)
        DECLARE @escalated TABLE (fundingTransactionId INT, loanId INT)

        UPDATE dbo.fundingTransactions
        SET status = 'ESCALATED', escalatedAt = GETUTCDATE(), updated_at = GETUTCDATE()
        OUTPUT inserted.fundingTransactionId, inserted.loanId INTO @escalated
        WHERE status = 'PENDING_CONFIRMATION'
          AND declaredAt IS NOT NULL
          AND declaredAt <= DATEADD(DAY, -@escalateAfterDays, GETUTCDATE())
          AND (@companyId IS NULL OR companyId = @companyId)

        SELECT ISNULL(
            (SELECT fundingTransactionId, loanId FROM @escalated FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── resolve_escalation ───────────────────────────────────
    -- Support/admin only — D5 applies here too: a human resolves with real
    -- evidence (CEP), the system still never auto-confirms.
    ELSE IF @action = 'resolve_escalation'
    BEGIN
        DECLARE @resolveId         INT          = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].fundingTransactionId')
        DECLARE @resolution        NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].resolution')

        IF @resolution NOT IN ('CONFIRMED', 'CANCELLED')
        BEGIN
            SELECT '{"error":"resolution debe ser CONFIRMED o CANCELLED."}' AS [jsonResult]
            RETURN
        END
        IF NOT EXISTS (
            SELECT 1 FROM dbo.fundingTransactions
            WHERE fundingTransactionId = @resolveId AND companyId = @companyId AND status = 'ESCALATED'
        )
        BEGIN
            SELECT '{"error":"Declaración no encontrada o no está escalada."}' AS [jsonResult]
            RETURN
        END

        UPDATE dbo.fundingTransactions
        SET status = @resolution,
            confirmedAt = CASE WHEN @resolution = 'CONFIRMED' THEN GETUTCDATE() ELSE confirmedAt END,
            updated_at = GETUTCDATE()
        WHERE fundingTransactionId = @resolveId

        SELECT (
            SELECT @resolveId AS fundingTransactionId, @resolution AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── list ─────────────────────────────────────────────────
    ELSE IF @action = 'list'
    BEGIN
        DECLARE @listLoanId INT = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].loanId')

        SELECT ISNULL(
            (SELECT fundingTransactionId, loanId, intentId, lenderClientId, borrowerClientId,
                    amountMXN, CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                    status,
                    CONVERT(NVARCHAR, declaredAt, 127) AS declaredAt,
                    CONVERT(NVARCHAR, confirmedAt, 127) AS confirmedAt,
                    confirmedByClientId, rejectReason,
                    CONVERT(NVARCHAR, escalatedAt, 127) AS escalatedAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM dbo.fundingTransactions
             WHERE companyId = @companyId AND (@listLoanId IS NULL OR loanId = @listLoanId)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── one ──────────────────────────────────────────────────
    ELSE IF @action = 'one'
    BEGIN
        DECLARE @oneId INT = JSON_VALUE(@pjsonfile, '$.fundingTransactions[0].fundingTransactionId')

        SELECT (
            SELECT fundingTransactionId, loanId, intentId, lenderClientId, borrowerClientId,
                   amountMXN, CONVERT(NVARCHAR, transferDate, 127) AS transferDate,
                   status,
                   CONVERT(NVARCHAR, declaredAt, 127) AS declaredAt,
                   CONVERT(NVARCHAR, confirmedAt, 127) AS confirmedAt,
                   confirmedByClientId, rejectReason,
                   CONVERT(NVARCHAR, escalatedAt, 127) AS escalatedAt,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM dbo.fundingTransactions
            WHERE fundingTransactionId = @oneId AND companyId = @companyId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF ERROR_NUMBER() IN (2601, 2627)
            SELECT '{"error":"Este préstamo ya tiene una declaración de fondeo."}' AS [jsonResult]
        ELSE
            SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_helpdiagramdefinition
IF OBJECT_ID(N'dbo.sp_helpdiagramdefinition', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_helpdiagramdefinition];
GO

	CREATE PROCEDURE dbo.sp_helpdiagramdefinition
	(
		@diagramname 	sysname,
		@owner_id	int	= null 		
	)
	WITH EXECUTE AS N'dbo'
	AS
	BEGIN
		set nocount on

		declare @theId 		int
		declare @IsDbo 		int
		declare @DiagId		int
		declare @UIDFound	int
	
		if(@diagramname is null)
		begin
			RAISERROR (N'E_INVALIDARG', 16, 1);
			return -1
		end
	
		execute as caller;
		select @theId = DATABASE_PRINCIPAL_ID();
		select @IsDbo = IS_MEMBER(N'db_owner');
		if(@owner_id is null)
			select @owner_id = @theId;
		revert; 
	
		select @DiagId = diagram_id, @UIDFound = principal_id from dbo.sysdiagrams where principal_id = @owner_id and name = @diagramname;
		if(@DiagId IS NULL or (@IsDbo = 0 and @UIDFound <> @theId ))
		begin
			RAISERROR ('Diagram does not exist or you do not have permission.', 16, 1);
			return -3
		end

		select version, definition FROM dbo.sysdiagrams where diagram_id = @DiagId ; 
		return 0
	END
GO

-- dbo.sp_helpdiagrams
IF OBJECT_ID(N'dbo.sp_helpdiagrams', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_helpdiagrams];
GO

	CREATE PROCEDURE dbo.sp_helpdiagrams
	(
		@diagramname sysname = NULL,
		@owner_id int = NULL
	)
	WITH EXECUTE AS N'dbo'
	AS
	BEGIN
		DECLARE @user sysname
		DECLARE @dboLogin bit
		EXECUTE AS CALLER;
			SET @user = USER_NAME();
			SET @dboLogin = CONVERT(bit,IS_MEMBER('db_owner'));
		REVERT;
		SELECT
			[Database] = DB_NAME(),
			[Name] = name,
			[ID] = diagram_id,
			[Owner] = USER_NAME(principal_id),
			[OwnerID] = principal_id
		FROM
			sysdiagrams
		WHERE
			(@dboLogin = 1 OR USER_NAME(principal_id) = @user) AND
			(@diagramname IS NULL OR name = @diagramname) AND
			(@owner_id IS NULL OR principal_id = @owner_id)
		ORDER BY
			4, 5, 1
	END
GO

-- dbo.sp_income
IF OBJECT_ID(N'dbo.sp_income', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_income];
GO

CREATE PROC [dbo].[sp_income]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE
    @Outputmessage NVARCHAR(MAX) = N'{
      "result": [
        { "value": "", "msg": "", "error": "0" }
      ]
    }',
    @action INT;

  SET @action = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.income[0].action'));

  IF @action IS NULL
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Action required');
    GOTO ReturnResult;
  END;

  DECLARE
    @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.income[0].incomeId')),
    @orderId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.income[0].orderId')),
    @total DECIMAL(10,2) = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile,'$.income[0].total')),
    @paymentMethod VARCHAR(50) = JSON_VALUE(@pjsonfile,'$.income[0].paymentMethod'),
    @paymentDate DATETIME = TRY_CONVERT(DATETIME, JSON_VALUE(@pjsonfile,'$.income[0].paymentDate')),
    @userId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.income[0].userId')),
    @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.income[0].clientId')),
    @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.income[0].companyId')),
    @cashPaid DECIMAL(10,2) = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile,'$.income[0].cashPaid')),
    @cashReturn DECIMAL(10,2) = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile,'$.income[0].cashReturn'));

  DECLARE @promotionCode VARCHAR(30) = UPPER(JSON_VALUE(@pjsonfile,'$.income[0].promotionCode'));

  DECLARE @paymentDateRaw NVARCHAR(60) = JSON_VALUE(@pjsonfile,'$.income[0].paymentDate');
  DECLARE @paymentDateUtc DATETIME2(3);

  IF @paymentDateRaw IS NULL OR LTRIM(RTRIM(@paymentDateRaw)) = ''
  BEGIN
    SET @paymentDateUtc = SYSUTCDATETIME();
  END
  ELSE
  BEGIN
    IF @paymentDateRaw LIKE '%Z'
       OR @paymentDateRaw LIKE '%+__:__'
       OR @paymentDateRaw LIKE '%-__:__'
    BEGIN
      SET @paymentDateUtc =
        CONVERT(DATETIME2(3),
          (TRY_CONVERT(DATETIMEOFFSET, @paymentDateRaw) AT TIME ZONE 'UTC')
        );

      IF @paymentDateUtc IS NULL
        SET @paymentDateUtc = SYSUTCDATETIME();
    END
    ELSE
    BEGIN
      SET @paymentDateUtc =
        DATEADD(HOUR, 7, TRY_CONVERT(DATETIME2(3), @paymentDateRaw));

      IF @paymentDateUtc IS NULL
        SET @paymentDateUtc = SYSUTCDATETIME();
    END
  END;

  DECLARE @openSessionId INT;

  DECLARE
    @promotionId INT = NULL,
    @promoType VARCHAR(20) = NULL,
    @discountAmount DECIMAL(10,2) = 0,
    @oldTotal DECIMAL(10,2) = NULL,
    @newTotal DECIMAL(10,2) = NULL;

  BEGIN TRY

    /* =====================================
       ACTION 1: INSERT
       ===================================== */
    IF @action = 1
    BEGIN

      IF @paymentMethod IS NULL
         OR @userId IS NULL
         OR @companyId IS NULL
      BEGIN
        SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Missing required fields');
        GOTO ReturnResult;
      END;

      IF LOWER(@paymentMethod) IN ('cash','efectivo')
      BEGIN
        IF @cashPaid IS NULL AND @total IS NOT NULL
          SET @cashPaid = @total;

        IF @cashReturn IS NULL
           AND @cashPaid IS NOT NULL
           AND @total IS NOT NULL
        BEGIN
          SET @cashReturn =
            CASE
              WHEN @cashPaid > @total
                THEN (@cashPaid - @total)
              ELSE 0
            END;
        END
      END
      ELSE
      BEGIN
        SET @cashPaid = NULL;
        SET @cashReturn = NULL;
      END;

      BEGIN TRAN;

      INSERT INTO dbo.income
      (
        orderId,
        total,
        paymentMethod,
        paymentDate,
        userId,
        clientId,
        companyId,
        cashPaid,
        cashReturn
      )
      VALUES
      (
        @orderId,
        @total,
        LOWER(@paymentMethod),
        CONVERT(DATETIME, @paymentDateUtc),
        @userId,
        @clientId,
        @companyId,
        @cashPaid,
        @cashReturn
      );

      SET @incomeId = SCOPE_IDENTITY();

      DECLARE @Prod TABLE (
        productIndex INT NOT NULL,
        productId INT NOT NULL,
        quantity INT NOT NULL,
        piecesJson NVARCHAR(MAX) NULL
      );

      INSERT INTO @Prod
      (
        productIndex,
        productId,
        quantity,
        piecesJson
      )
      SELECT
        CAST(p.[key] AS INT),
        TRY_CONVERT(INT, JSON_VALUE(p.value,'$.productId')),
        COALESCE(TRY_CONVERT(INT, JSON_VALUE(p.value,'$.quantity')),1),
        JSON_QUERY(p.value,'$.pieces')
      FROM OPENJSON(@pjsonfile,'$.income[0].products') p
      WHERE TRY_CONVERT(INT, JSON_VALUE(p.value,'$.productId')) IS NOT NULL;

      DECLARE @DetailMap TABLE (
        productIndex INT NOT NULL,
        incomeDetailId INT NOT NULL
      );

      DECLARE
        @idx INT,
        @pid INT,
        @qty INT,
        @pieces NVARCHAR(MAX),
        @incomeDetailId INT;

      DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT
          productIndex,
          productId,
          quantity,
          piecesJson
        FROM @Prod
        ORDER BY productIndex;

      OPEN cur;

      FETCH NEXT FROM cur
      INTO @idx, @pid, @qty, @pieces;

      WHILE @@FETCH_STATUS = 0
      BEGIN

        INSERT INTO dbo.incomeDetails
        (
          incomeId,
          productId,
          quantity,
          piecesJson
        )
        VALUES
        (
          @incomeId,
          @pid,
          @qty,
          @pieces
        );

        SET @incomeDetailId = SCOPE_IDENTITY();

        INSERT INTO @DetailMap
        (
          productIndex,
          incomeDetailId
        )
        VALUES
        (
          @idx,
          @incomeDetailId
        );

        FETCH NEXT FROM cur
        INTO @idx, @pid, @qty, @pieces;
      END

      CLOSE cur;
      DEALLOCATE cur;

      ;WITH Opt AS
      (
        SELECT
          CAST(p.[key] AS INT) AS productIndex,
          TRY_CONVERT(INT, JSON_VALUE(o.value,'$.productOptionId')) AS productOptionId,
          TRY_CONVERT(INT, JSON_VALUE(o.value,'$.productOptionChoiceId')) AS productOptionChoiceId,
          COALESCE(TRY_CONVERT(INT, JSON_VALUE(o.value,'$.quantity')),1) AS quantity
        FROM OPENJSON(@pjsonfile,'$.income[0].products') p
        CROSS APPLY OPENJSON(p.value,'$.options') o
      )
      INSERT INTO dbo.incomeDetailOptions
      (
        incomeDetailId,
        productOptionId,
        productOptionChoiceId,
        quantity
      )
      SELECT
        dm.incomeDetailId,
        opt.productOptionId,
        opt.productOptionChoiceId,
        opt.quantity
      FROM Opt opt
      INNER JOIN @DetailMap dm
        ON dm.productIndex = opt.productIndex
      WHERE opt.productOptionId IS NOT NULL
        AND opt.productOptionChoiceId IS NOT NULL;

      IF @promotionCode IS NOT NULL
         AND LTRIM(RTRIM(@promotionCode)) <> ''
      BEGIN

        DECLARE @nowUtc DATETIME2(0) = SYSUTCDATETIME();

        SELECT TOP 1
          @promotionId = p.promotionId,
          @promoType = p.promoType
        FROM dbo.promotions p
        WHERE p.companyId = @companyId
          AND p.code = @promotionCode
          AND p.isActive = 1
          AND (p.startAtUtc IS NULL OR p.startAtUtc <= @nowUtc)
          AND (p.endAtUtc IS NULL OR p.endAtUtc >= @nowUtc);

        IF @promotionId IS NOT NULL
           AND @promoType = 'B2G1'
        BEGIN

          SET @oldTotal = @total;

          ;WITH EligibleDetails AS
          (
            SELECT
              d.incomeDetailId,
              d.productId,
              CAST(ISNULL(d.quantity,1) AS INT) AS qty
            FROM dbo.incomeDetails d
            WHERE d.incomeId = @incomeId
          ),
          LineTotals AS
          (
            SELECT
              e.incomeDetailId,
              e.qty,
              CAST(ISNULL(
              (
                SELECT
                  SUM(CAST(c.price AS DECIMAL(10,2))
                  * ISNULL(ido.quantity,1))
                FROM dbo.incomeDetailOptions ido
                INNER JOIN dbo.productOptionChoices c
                  ON c.productOptionChoiceId = ido.productOptionChoiceId
                WHERE ido.incomeDetailId = e.incomeDetailId
              ),0) AS DECIMAL(10,2)) AS lineTotal
            FROM EligibleDetails e
          ),
          PromoTotals AS
          (
            SELECT
              incomeDetailId,
              qty,
              lineTotal,
              CASE
                WHEN qty <= 0 THEN 0
                ELSE (qty - (qty/2))
              END AS payQty,
              CAST(
                CASE
                  WHEN qty <= 0 THEN 0
                  ELSE ROUND(
                    lineTotal * (
                      1.0 * (qty - (qty/2))
                      / NULLIF(qty,0)
                    ),
                    2
                  )
                END
              AS DECIMAL(10,2)) AS promoLineTotal
            FROM LineTotals
          )
          SELECT
            @newTotal = CAST(ISNULL(SUM(promoLineTotal),0) AS DECIMAL(10,2))
          FROM PromoTotals;

          IF @newTotal IS NOT NULL
             AND @newTotal >= 0
          BEGIN

            SET @total = @newTotal;

            SET @discountAmount =
              CASE
                WHEN @oldTotal >= @newTotal
                  THEN (@oldTotal - @newTotal)
                ELSE 0
              END;

            IF LOWER(@paymentMethod) IN ('cash','efectivo')
            BEGIN

              IF @cashPaid IS NULL
                SET @cashPaid = @total;

              SET @cashReturn =
                CASE
                  WHEN @cashPaid > @total
                    THEN (@cashPaid - @total)
                  ELSE 0
                END;
            END

            UPDATE dbo.income
            SET
              total = @total,
              promotionId = @promotionId,
              promotionCode = @promotionCode,
              discountAmount = @discountAmount,
              cashPaid = @cashPaid,
              cashReturn = @cashReturn
            WHERE incomeId = @incomeId;
          END
        END
      END

      IF LOWER(@paymentMethod) IN ('cash','efectivo')
      BEGIN

        SELECT TOP 1
          @openSessionId = sessionId
        FROM dbo.cashRegisterSessions
        WHERE companyId = @companyId
          AND status = 'open'
        ORDER BY openedAt DESC;

        IF @openSessionId IS NOT NULL
        BEGIN

          INSERT INTO dbo.cashRegisterMovements
          (
            sessionId,
            companyId,
            userId,
            movementType,
            amount,
            incomeId,
            notes,
            createdAt,
            cashPaid,
            cashReturn
          )
          VALUES
          (
            @openSessionId,
            @companyId,
            @userId,
            LOWER(@paymentMethod),
            @total,
            @incomeId,
            N'Venta en efectivo',
            SYSUTCDATETIME(),
            @cashPaid,
            @cashReturn
          );
        END
      END

      COMMIT;

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].value',CONVERT(NVARCHAR(50),@incomeId));
      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Inserted Successfully');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','0');

      GOTO ReturnResult;
    END;

    /* =====================================
       ACTION 2: DELETE
       ===================================== */
    IF @action = 2
    BEGIN

      IF @incomeId IS NULL
      BEGIN
        SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','incomeId required');
        GOTO ReturnResult;
      END;

      BEGIN TRAN;

      DELETE ido
      FROM dbo.incomeDetailOptions ido
      INNER JOIN dbo.incomeDetails id
        ON ido.incomeDetailId = id.incomeDetailId
      WHERE id.incomeId = @incomeId;

      DELETE FROM dbo.incomeDetails
      WHERE incomeId = @incomeId;

      DELETE FROM dbo.cashRegisterMovements
      WHERE incomeId = @incomeId;

      DELETE FROM dbo.income
      WHERE incomeId = @incomeId;

      COMMIT;

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].value',CONVERT(NVARCHAR(50),@incomeId));
      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Deleted Successfully');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','0');

      GOTO ReturnResult;
    END;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Invalid action (1 insert, 2 delete)');

  END TRY
  BEGIN CATCH

    IF @@TRANCOUNT > 0
      ROLLBACK;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',ERROR_MESSAGE());

  END CATCH;

ReturnResult:

  SELECT
    JSON_VALUE(value,'$.value') AS value,
    JSON_VALUE(value,'$.msg') AS msg,
    JSON_VALUE(value,'$.error') AS error
  FROM OPENJSON(@Outputmessage,'$.result');

END
GO

-- dbo.sp_income_all
IF OBJECT_ID(N'dbo.sp_income_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_income_all];
GO

CREATE PROC [dbo].[sp_income_all]
AS
SET NOCOUNT ON;

BEGIN
    -- Verificar si hay datos en income
    IF EXISTS (SELECT 1 FROM [dbo].[income])
    BEGIN
        -- Devolver registros de income en formato JSON
        SELECT 
            i.incomeId,
            i.orderId,
            i.total,
            i.paymentMethod,
            i.paymentDate,
            i.userId,
            i.clientId,
            i.companyId,
            ISNULL(i.discountAmount,0) AS discountAmount
        FROM [dbo].[income] i
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        -- Si no hay datos, regresar JSON vacío con la raíz 'income'
        SELECT '[]' AS [income]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END;
GO

-- dbo.sp_income_apply_promo
IF OBJECT_ID(N'dbo.sp_income_apply_promo', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_income_apply_promo];
GO
CREATE   PROC dbo.sp_income_apply_promo
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  /*
    Input:
    {
      "promo":[
        {"action":1,"incomeId":3192,"companyId":1,"code":"2X1","userId":1}
      ]
    }
  */

  DECLARE
    @Outputmessage NVARCHAR(MAX) = N'{"result":[{"value":"","msg":"","error":"0"}]}',
    @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.promo[0].action')),
    @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.promo[0].incomeId')),
    @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.promo[0].companyId')),
    @code VARCHAR(30) = UPPER(JSON_VALUE(@pjsonfile,'$.promo[0].code'));

  IF @action IS NULL OR @incomeId IS NULL OR @companyId IS NULL OR @code IS NULL
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Missing required fields: action,incomeId,companyId,code');
    GOTO ReturnResult;
  END;

  IF @action <> 1
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Invalid action (1 only)');
    GOTO ReturnResult;
  END;

  DECLARE
    @promotionId INT,
    @promoType VARCHAR(20),
    @nowUtc DATETIME2(0) = SYSUTCDATETIME();

  SELECT TOP 1
    @promotionId = p.promotionId,
    @promoType = p.promoType
  FROM dbo.promotions p
  WHERE p.companyId = @companyId
    AND p.code = @code
    AND p.isActive = 1
    AND (p.startAtUtc IS NULL OR p.startAtUtc <= @nowUtc)
    AND (p.endAtUtc IS NULL OR p.endAtUtc >= @nowUtc);

  IF @promotionId IS NULL
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Promo code not valid or not active');
    GOTO ReturnResult;
  END;

  IF NOT EXISTS (SELECT 1 FROM dbo.income WHERE incomeId=@incomeId AND companyId=@companyId)
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','incomeId not found for company');
    GOTO ReturnResult;
  END;

  BEGIN TRY
    BEGIN TRAN;

    DECLARE
      @oldTotal DECIMAL(10,2),
      @newTotal DECIMAL(10,2),
      @discount DECIMAL(10,2),
      @paymentMethod VARCHAR(50),
      @cashPaid DECIMAL(10,2),
      @cashReturn DECIMAL(10,2);

    SELECT
      @oldTotal = total,
      @paymentMethod = paymentMethod,
      @cashPaid = cashPaid,
      @cashReturn = cashReturn
    FROM dbo.income
    WHERE incomeId=@incomeId;

    /* ===== Compute line totals (service price is from options) ===== */
    ;WITH EligibleDetails AS (
      SELECT d.incomeDetailId, d.productId, CAST(ISNULL(d.quantity,1) AS INT) AS qty
      FROM dbo.incomeDetails d
      WHERE d.incomeId = @incomeId
        AND (
          EXISTS (SELECT 1 FROM dbo.promotion_targets t WHERE t.promotionId=@promotionId AND t.targetType='ALL')
          OR EXISTS (SELECT 1 FROM dbo.promotion_targets t WHERE t.promotionId=@promotionId AND t.targetType='PRODUCT' AND t.productId=d.productId)
        )
    ),
    LineTotals AS (
      SELECT
        e.incomeDetailId,
        e.qty,
        CAST(ISNULL((
          SELECT SUM(CAST(c.price AS DECIMAL(10,2)) * ISNULL(ido.quantity,1))
          FROM dbo.incomeDetailOptions ido
          JOIN dbo.productOptionChoices c ON c.productOptionChoiceId = ido.productOptionChoiceId
          WHERE ido.incomeDetailId = e.incomeDetailId
        ),0) AS DECIMAL(10,2)) AS lineTotal
      FROM EligibleDetails e
    ),
    PromoTotals AS (
      SELECT
        incomeDetailId,
        qty,
        lineTotal,
        CASE WHEN qty <= 0 THEN 0 ELSE (qty - (qty/2)) END AS payQty,
        CAST(
          CASE WHEN qty <= 0 THEN 0
               ELSE ROUND(lineTotal * (1.0 * (qty - (qty/2)) / NULLIF(qty,0)), 2)
          END
          AS DECIMAL(10,2)
        ) AS promoLineTotal
      FROM LineTotals
    )
    SELECT
      @newTotal = CAST(ISNULL(SUM(promoLineTotal),0) AS DECIMAL(10,2))
    FROM PromoTotals;

    -- If nothing eligible, keep old total
    IF @newTotal IS NULL OR @newTotal = 0
      SET @newTotal = @oldTotal;

    SET @discount = CASE WHEN @oldTotal >= @newTotal THEN (@oldTotal - @newTotal) ELSE 0 END;

    -- Update income totals + promo audit fields
    UPDATE dbo.income
    SET total = @newTotal,
        promotionId = @promotionId,
        promotionCode = @code,
        discountAmount = @discount,
        cashReturn =
          CASE
            WHEN LOWER(@paymentMethod) IN ('cash','efectivo')
              THEN CASE WHEN ISNULL(@cashPaid,0) > @newTotal THEN (ISNULL(@cashPaid,0) - @newTotal) ELSE 0 END
            ELSE cashReturn
          END
    WHERE incomeId=@incomeId;

    -- Update cash movement amount to match new total (if exists)
    UPDATE dbo.cashRegisterMovements
    SET amount = @newTotal,
        cashReturn =
          CASE
            WHEN LOWER(@paymentMethod) IN ('cash','efectivo')
              THEN CASE WHEN ISNULL(@cashPaid,0) > @newTotal THEN (ISNULL(@cashPaid,0) - @newTotal) ELSE 0 END
            ELSE cashReturn
          END
    WHERE incomeId=@incomeId;

    COMMIT;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].value',CONVERT(NVARCHAR(50),@incomeId));
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',CONCAT('Promo applied. code=',@code,' discount=',@discount));
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','0');

  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',ERROR_MESSAGE());
  END CATCH;

ReturnResult:
  SELECT
    JSON_VALUE(value,'$.value') AS value,
    JSON_VALUE(value,'$.msg') AS msg,
    JSON_VALUE(value,'$.error') AS error
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_income_delete
IF OBJECT_ID(N'dbo.sp_income_delete', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_income_delete];
GO

/* ============================================================
   dbo.sp_income_delete
   - Deletes a payment (income) and its details/options
   - Also deletes related cash register movements
   - Input follows same JSON structure style
   ============================================================ */
CREATE   PROC [dbo].[sp_income_delete]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;
    /*
  DECLARE @pjsonfile NVARCHAR(MAX) = N'
    {
    "income":[
        {
        "action":4,
        "incomeId":3181,
        "companyId":1,
        "userId":1,
        "reason":"Cancelación de venta"
        }
    ]
    }';
    */

  DECLARE
    @Outputmessage NVARCHAR(MAX) = N'{
      "result": [
        { "value": "", "msg": "", "error": "0" }
      ]
    }',
    @action INT;

  /* action = 4 (delete) to keep same pattern */
  SET @action = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.income[0].action'));

  IF @action IS NULL
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Action required');
    GOTO ReturnResult;
  END;

  IF @action <> 4
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Invalid action (expected 4 for delete)');
    GOTO ReturnResult;
  END;

  DECLARE
    @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.income[0].incomeId')),
    @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.income[0].companyId')),
    @userId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile,'$.income[0].userId')),
    @reason NVARCHAR(250) = JSON_VALUE(@pjsonfile,'$.income[0].reason');

  IF @incomeId IS NULL
  BEGIN
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','incomeId is required');
    GOTO ReturnResult;
  END;

  BEGIN TRY
    BEGIN TRAN;

    /* Validate exists */
    IF NOT EXISTS (SELECT 1 FROM dbo.income WHERE incomeId = @incomeId)
    BEGIN
      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','incomeId not found');
      ROLLBACK;
      GOTO ReturnResult;
    END;

    /* OPTIONAL: Safety check by company */
    IF @companyId IS NOT NULL
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM dbo.income WHERE incomeId=@incomeId AND companyId=@companyId)
      BEGIN
        SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','incomeId does not belong to companyId');
        ROLLBACK;
        GOTO ReturnResult;
      END;
    END;

    /* Collect incomeDetailIds */
    DECLARE @Details TABLE (incomeDetailId INT PRIMARY KEY);

    INSERT INTO @Details(incomeDetailId)
    SELECT incomeDetailId
    FROM dbo.incomeDetails
    WHERE incomeId = @incomeId;

    /* 1) Delete incomeDetailOptions */
    DELETE ido
    FROM dbo.incomeDetailOptions ido
    JOIN @Details d ON d.incomeDetailId = ido.incomeDetailId;

    /* 2) Delete incomeDetails */
    DELETE FROM dbo.incomeDetails
    WHERE incomeId = @incomeId;

    /* 3) Delete cashRegisterMovements linked to this income */
    DELETE FROM dbo.cashRegisterMovements
    WHERE incomeId = @incomeId;

    /* 4) Delete income header */
    DELETE FROM dbo.income
    WHERE incomeId = @incomeId;

    COMMIT;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].value',CONVERT(NVARCHAR(50),@incomeId));
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',
      CONCAT('Deleted incomeId=',@incomeId, COALESCE(CONCAT(' reason=',@reason), ''))
    );
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','0');

  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',ERROR_MESSAGE());
  END CATCH;

ReturnResult:
  SELECT
    JSON_VALUE(value,'$.value') AS value,
    JSON_VALUE(value,'$.msg') AS msg,
    JSON_VALUE(value,'$.error') AS error
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_ingestState_dequeue
IF OBJECT_ID(N'dbo.sp_ingestState_dequeue', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_ingestState_dequeue];
GO

CREATE   PROC dbo.sp_ingestState_dequeue
  @top INT = 10,
  @workerId NVARCHAR(100) = NULL,
  @lockSeconds INT = 300
AS
BEGIN
  SET NOCOUNT ON;

  IF @workerId IS NULL
    SET @workerId = CONVERT(NVARCHAR(100), NEWID());

  ;WITH cte AS (
    SELECT TOP (@top) *
    FROM dbo.ingestState WITH (ROWLOCK, READPAST, UPDLOCK)
    WHERE
      (status IN ('idle','failed'))
      AND (nextRunAt IS NULL OR nextRunAt <= SYSUTCDATETIME())
      AND (lockUntil IS NULL OR lockUntil < SYSUTCDATETIME())
    ORDER BY
      CASE status WHEN 'idle' THEN 0 ELSE 1 END,
      ISNULL(nextRunAt, '19000101'),
      updatedAt DESC
  )
  UPDATE cte
  SET
    status    = 'running',
    attempts  = attempts + 1,
    lockedBy  = @workerId,
    lockUntil = DATEADD(SECOND, @lockSeconds, SYSUTCDATETIME()),
    lastRunAt = SYSUTCDATETIME(),
    updatedAt = SYSUTCDATETIME()
  OUTPUT
    inserted.ingestStateId,
    inserted.targetKey,
    inserted.source,
    inserted.market,
    inserted.channel,
    inserted.pageSize,
    inserted.lastOffset,
    inserted.nextOffset,
    inserted.attempts,
    inserted.lockedBy,
    inserted.lockUntil;
END
GO

-- dbo.sp_ingestState_finish
IF OBJECT_ID(N'dbo.sp_ingestState_finish', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_ingestState_finish];
GO

CREATE   PROC dbo.sp_ingestState_finish
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  UPDATE s
  SET
    s.status     = ISNULL(NULLIF(JSON_VALUE(j.value,'$.status'),''), s.status),
    s.lastOffset = TRY_CONVERT(INT, JSON_VALUE(j.value,'$.lastOffset')),
    s.nextOffset = TRY_CONVERT(INT, JSON_VALUE(j.value,'$.nextOffset')),
    s.nextRunAt  = TRY_CONVERT(DATETIME2, JSON_VALUE(j.value,'$.nextRunAt')),
    s.lastError  = JSON_VALUE(j.value,'$.lastError'),
    s.lockedBy   = NULL,
    s.lockUntil  = NULL,
    s.updatedAt  = SYSUTCDATETIME()
  FROM dbo.ingestState s
  INNER JOIN OPENJSON(@pjsonfile,'$.ingestState') j
    ON s.ingestStateId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.ingestStateId'));
END
GO

-- dbo.sp_integrationLog
IF OBJECT_ID(N'dbo.sp_integrationLog', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_integrationLog];
GO
CREATE PROCEDURE [dbo].[sp_integrationLog] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [dbo].[integrationLogs]
            (correlationId, workflowId, companyId, service, operation, status, httpStatus,
             latencyMs, requestSummary, responseSummary, exception)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            JSON_VALUE(value, '$.service'),
            JSON_VALUE(value, '$.operation'),
            JSON_VALUE(value, '$.status'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.httpStatus')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.latencyMs')),
            JSON_VALUE(value, '$.requestSummary'),
            JSON_VALUE(value, '$.responseSummary'),
            JSON_VALUE(value, '$.exception')
        FROM OPENJSON(@pjsonfile, '$.logs')
        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_inventory_adjust
IF OBJECT_ID(N'dbo.sp_inventory_adjust', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_inventory_adjust];
GO


CREATE   PROC dbo.sp_inventory_adjust
(
    @pjson NVARCHAR(MAX)
)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @companyId INT,
        @productId INT,
        @qty       DECIMAL(18,3),
        @reason    VARCHAR(30),
        @notes     NVARCHAR(300),
        @userId    INT,
        @refType   VARCHAR(30),
        @refId     INT;

    SELECT
        @companyId = JSON_VALUE(@pjson, '$.companyId'),
        @productId = JSON_VALUE(@pjson, '$.productId'),
        @qty       = TRY_CONVERT(DECIMAL(18,3), JSON_VALUE(@pjson, '$.quantity')),
        @reason    = JSON_VALUE(@pjson, '$.reason'),
        @notes     = JSON_VALUE(@pjson, '$.notes'),
        @userId    = JSON_VALUE(@pjson, '$.userId'),
        @refType   = JSON_VALUE(@pjson, '$.refType'),
        @refId     = JSON_VALUE(@pjson, '$.refId');

    IF @companyId IS NULL OR @productId IS NULL OR @qty IS NULL OR @reason IS NULL
    BEGIN
        SELECT 0 AS ok, 'Missing required fields: companyId, productId, quantity, reason' AS message
        FOR JSON PATH, ROOT('result');
        RETURN;
    END

    BEGIN TRAN;

        -- Ensure row exists
        MERGE dbo.inventoryStock AS t
        USING (SELECT @companyId AS companyId, @productId AS productId) AS s
           ON t.companyId = s.companyId AND t.productId = s.productId
        WHEN NOT MATCHED THEN
            INSERT (companyId, productId, stockQuantity)
            VALUES (s.companyId, s.productId, 0);

        -- Apply delta
        UPDATE dbo.inventoryStock
        SET stockQuantity = stockQuantity + @qty,
            updatedAt = SYSUTCDATETIME()
        WHERE companyId = @companyId AND productId = @productId;

        -- Log movement
        INSERT dbo.inventoryMovements
        (
            companyId, productId, quantityDelta, reason, notes, refType, refId, userId
        )
        VALUES
        (
            @companyId, @productId, @qty, @reason, @notes, @refType, @refId, @userId
        );

        -- Return updated stock
        SELECT
            1 AS ok,
            @companyId AS companyId,
            @productId AS productId,
            (SELECT stockQuantity FROM dbo.inventoryStock WHERE companyId=@companyId AND productId=@productId) AS stockQuantity
        FOR JSON PATH, ROOT('result');

    COMMIT;
END
GO

-- dbo.sp_inventory_list
IF OBJECT_ID(N'dbo.sp_inventory_list', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_inventory_list];
GO
CREATE   PROC dbo.sp_inventory_list
(
    @companyId INT
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.productId,
        p.name AS productName,

        ISNULL(s.stockQuantity, 0) AS stockQuantity,
        ISNULL(s.minStockQty, 0)   AS minStockQty,

        pd.unitPrice,
        pd.salePrice,

        p.barCode,
        p.code,
        p.categoryId
    FROM dbo.products p
    LEFT JOIN dbo.productDetails pd
        ON pd.productId = p.productId
    LEFT JOIN dbo.inventoryStock s
        ON s.companyId = @companyId
       AND s.productId = p.productId
    WHERE p.companyId = @companyId
    ORDER BY p.name
    FOR JSON PATH, ROOT('result');
END
GO

-- dbo.sp_led_status
IF OBJECT_ID(N'dbo.sp_led_status', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_led_status];
GO

CREATE PROC [dbo].[sp_led_status]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @status   NVARCHAR(10),
        @deviceId NVARCHAR(64) = N'default',
        @source   NVARCHAR(50);

    -- Read the first object in led_status[]
    SELECT TOP (1)
        @status   = JSON_VALUE(value, '$.status'),
        @deviceId = COALESCE(JSON_VALUE(value, '$.deviceId'), @deviceId),
        @source   = JSON_VALUE(value, '$.source')
    FROM OPENJSON(@pjsonfile, '$.led_status');

    -- Normalize
    SET @status = LOWER(LTRIM(RTRIM(@status)));

    -- If request asks to CHANGE state
    IF (@status IN (N'on', N'off'))
    BEGIN
        MERGE [dbo].[LedStatus] AS t
        USING (SELECT @deviceId AS deviceId, @status AS status) AS s
        ON (t.deviceId = s.deviceId)
        WHEN MATCHED THEN
            UPDATE SET
                t.status     = s.status,
                t.updated_at = SYSUTCDATETIME(),
                t.updated_by = COALESCE(@source, N'api')
        WHEN NOT MATCHED THEN
            INSERT (deviceId, status, updated_at, updated_by)
            VALUES (s.deviceId, s.status, SYSUTCDATETIME(), COALESCE(@source, N'api'));
    END
    ELSE
    BEGIN
        -- check/unknown: ensure row exists but don't change state
        IF NOT EXISTS (SELECT 1 FROM [dbo].[LedStatus] WHERE deviceId = @deviceId)
            INSERT INTO [dbo].[LedStatus] (deviceId, status, updated_by)
            VALUES (@deviceId, N'off', N'init');
    END

    -- Return current state for the requested device
    SELECT status AS [status]
    FROM [dbo].[LedStatus]
    WHERE deviceId = @deviceId
    FOR JSON PATH, ROOT('led_status');
END
GO

-- dbo.sp_legalCases
IF OBJECT_ID(N'dbo.sp_legalCases', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_legalCases];
GO

CREATE PROCEDURE [dbo].[sp_legalCases]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.case[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.case[0].companyId')
    DECLARE @caseId          INT           = JSON_VALUE(@pjsonfile, '$.case[0].caseId')
    DECLARE @loanId          INT           = JSON_VALUE(@pjsonfile, '$.case[0].loanId')
    DECLARE @clientId        INT           = JSON_VALUE(@pjsonfile, '$.case[0].clientId')

    IF @action = 'open_case'
    BEGIN
        DECLARE @borrowerClientId INT          = JSON_VALUE(@pjsonfile, '$.case[0].borrowerClientId')
        DECLARE @lenderClientId   INT          = JSON_VALUE(@pjsonfile, '$.case[0].lenderClientId')
        DECLARE @lenderUserId     INT          = JSON_VALUE(@pjsonfile, '$.case[0].lenderUserId')
        DECLARE @overdueAmount    DECIMAL(14,2)= JSON_VALUE(@pjsonfile, '$.case[0].overdueAmount')
        DECLARE @openStatusNote   NVARCHAR(MAX)= JSON_VALUE(@pjsonfile, '$.case[0].statusNote')

        IF EXISTS (SELECT 1 FROM legalCases WHERE loanId = @loanId AND caseStatus NOT IN ('closed'))
        BEGIN
            SELECT (SELECT TOP 1 caseId, caseStatus, loanId
                    FROM legalCases WHERE loanId = @loanId AND caseStatus NOT IN ('closed')
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
            RETURN
        END

        INSERT INTO legalCases
            (companyId, loanId, borrowerClientId, lenderClientId, lenderUserId,
             overdueAmount, statusNote)
        VALUES
            (@companyId, @loanId, @borrowerClientId, @lenderClientId, @lenderUserId,
             @overdueAmount, @openStatusNote)

        DECLARE @newCaseId INT = SCOPE_IDENTITY()

        INSERT INTO legalCaseNotes (caseId, authorClientId, authorRole, noteText)
        VALUES (@newCaseId, @lenderClientId, 'system', 'Caso de recuperación abierto automáticamente por incumplimiento de pago.')

        SELECT (
            SELECT caseId, companyId, loanId, caseStatus, overdueAmount, lenderUserId,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM legalCases WHERE caseId = @newCaseId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'assign_lawyer'
    BEGIN
        DECLARE @lawyerClientId INT          = JSON_VALUE(@pjsonfile, '$.case[0].lawyerClientId')
        DECLARE @lawyerUserId   INT          = JSON_VALUE(@pjsonfile, '$.case[0].lawyerUserId')
        DECLARE @lawyerName     NVARCHAR(200)= JSON_VALUE(@pjsonfile, '$.case[0].lawyerName')

        UPDATE legalCases SET
            lawyerClientId = @lawyerClientId,
            lawyerUserId   = @lawyerUserId,
            lawyerName     = @lawyerName,
            caseStatus     = 'demand_filed',
            updated_at     = GETUTCDATE()
        WHERE caseId = @caseId AND companyId = @companyId

        INSERT INTO legalCaseNotes (caseId, authorClientId, authorRole, noteText)
        VALUES (@caseId, @lawyerClientId, 'system',
                'Abogado ' + ISNULL(@lawyerName, '') + ' asignado al caso.')

        SELECT (
            SELECT @caseId AS caseId, 'demand_filed' AS caseStatus,
                   @lawyerUserId AS lawyerUserId, @lawyerName AS lawyerName,
                   @lenderUserId AS lenderUserId, @lawyerUserId AS lawyerUserId2
            FROM legalCases WHERE caseId = @caseId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'get_expediente'
    BEGIN
        SELECT ISNULL(
            (SELECT
                lc.caseId, lc.caseStatus, lc.caseStage, lc.overdueAmount, lc.recoveredAmount,
                lc.lawyerName,
                CONVERT(NVARCHAR, lc.created_At, 127) AS caseOpenedAt,
                (SELECT TOP 1 loanId, loanNumber, principalAmount, interestRate,
                              termMonths, paymentFrequency, loanStatus,
                              CONVERT(NVARCHAR, disbursementDate, 127) AS disbursementDate,
                              CONVERT(NVARCHAR, maturityDate, 127) AS maturityDate
                 FROM dbo.loans WHERE loanId = lc.loanId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS loan,
                (SELECT TOP 1 clientId, first_name, last_name, cellphone, email
                 FROM dbo.clients WHERE clientId = lc.borrowerClientId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS borrower,
                (SELECT contractId, contractType, contractStatus, principalAmount,
                        interestRate, termMonths, pdfBlobUrl,
                        CONVERT(NVARCHAR, created_At, 127) AS created_At,
                        (SELECT signatureId, signerRole, biometricVerified,
                                CONVERT(NVARCHAR, signedAt, 127) AS signedAt
                         FROM dbo.loanContractSignatures
                         WHERE contractId = dc.contractId
                         FOR JSON PATH) AS signatures
                 FROM dbo.loanContracts dc
                 WHERE dc.loanId = lc.loanId
                 FOR JSON PATH) AS contracts,
                (SELECT TOP 50 *
                 FROM dbo.walletTransactions
                 WHERE loanId = lc.loanId
                 ORDER BY created_At
                 FOR JSON PATH) AS payments,
                (SELECT noteId, authorRole, noteText,
                        CONVERT(NVARCHAR, created_At, 127) AS created_At
                 FROM dbo.legalCaseNotes WHERE caseId = lc.caseId
                 ORDER BY created_At
                 FOR JSON PATH) AS notes
             FROM legalCases lc
             WHERE lc.caseId = @caseId AND lc.companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    ELSE IF @action = 'list_cases'
    BEGIN
        DECLARE @lawyerClientIdFilter INT         = JSON_VALUE(@pjsonfile, '$.case[0].lawyerClientId')
        DECLARE @statusFilter         NVARCHAR(30)= JSON_VALUE(@pjsonfile, '$.case[0].caseStatus')

        SELECT ISNULL(
            (SELECT caseId, companyId, loanId, caseStatus, caseStage, lawyerName,
                    overdueAmount, recoveredAmount,
                    borrowerClientId, lenderClientId, lawyerClientId,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM legalCases
             WHERE companyId = @companyId
               AND (@lawyerClientIdFilter IS NULL OR lawyerClientId = @lawyerClientIdFilter)
               AND (@clientId IS NULL OR lenderClientId = @clientId OR borrowerClientId = @clientId)
               AND (@statusFilter IS NULL OR caseStatus = @statusFilter)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    ELSE IF @action = 'get_case'
    BEGIN
        SELECT ISNULL(
            (SELECT lc.caseId, lc.companyId, lc.loanId, lc.borrowerClientId, lc.lenderClientId,
                    lc.lenderUserId, lc.lawyerClientId, lc.lawyerUserId, lc.lawyerName,
                    lc.caseStatus, lc.caseStage, lc.overdueAmount, lc.recoveredAmount,
                    lc.statusNote,
                    CONVERT(NVARCHAR, lc.embargoExecutedAt, 127) AS embargoExecutedAt,
                    CONVERT(NVARCHAR, lc.closedAt, 127) AS closedAt,
                    CONVERT(NVARCHAR, lc.created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, lc.updated_at, 127) AS updated_at,
                    (SELECT noteId, authorRole, noteText,
                            CONVERT(NVARCHAR, created_At, 127) AS created_At
                     FROM dbo.legalCaseNotes WHERE caseId = lc.caseId
                     ORDER BY created_At
                     FOR JSON PATH) AS notes
             FROM legalCases lc
             WHERE lc.caseId = @caseId AND lc.companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    ELSE IF @action = 'update_status'
    BEGIN
        DECLARE @newCaseStatus NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.case[0].caseStatus')
        DECLARE @caseStage     NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.case[0].caseStage')
        DECLARE @statusNote    NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.case[0].statusNote')

        UPDATE legalCases SET
            caseStatus  = ISNULL(@newCaseStatus, caseStatus),
            caseStage   = ISNULL(@caseStage, caseStage),
            statusNote  = ISNULL(@statusNote, statusNote),
            updated_at  = GETUTCDATE()
        WHERE caseId = @caseId AND companyId = @companyId

        DECLARE @updateLenderUserId INT
        SELECT @updateLenderUserId = lenderUserId FROM legalCases WHERE caseId = @caseId

        SELECT (
            SELECT @caseId AS caseId, @newCaseStatus AS caseStatus,
                   @statusNote AS statusNote, @updateLenderUserId AS lenderUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'add_case_note'
    BEGIN
        DECLARE @noteAuthorClientId INT          = JSON_VALUE(@pjsonfile, '$.case[0].authorClientId')
        DECLARE @noteAuthorRole     NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.case[0].authorRole')
        DECLARE @noteText           NVARCHAR(MAX)= JSON_VALUE(@pjsonfile, '$.case[0].noteText')

        INSERT INTO legalCaseNotes (caseId, authorClientId, authorRole, noteText)
        VALUES (@caseId, @noteAuthorClientId, @noteAuthorRole, @noteText)

        SELECT (
            SELECT SCOPE_IDENTITY() AS noteId, @caseId AS caseId,
                   @noteAuthorRole AS authorRole, @noteText AS noteText,
                   CONVERT(NVARCHAR, GETUTCDATE(), 127) AS created_At
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'close_case'
    BEGIN
        DECLARE @closeNote       NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.case[0].statusNote')
        DECLARE @recoveredAmount DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.case[0].recoveredAmount')

        UPDATE legalCases SET
            caseStatus       = 'closed',
            recoveredAmount  = ISNULL(@recoveredAmount, recoveredAmount),
            statusNote       = ISNULL(@closeNote, statusNote),
            closedAt         = GETUTCDATE(),
            updated_at       = GETUTCDATE()
        WHERE caseId = @caseId AND companyId = @companyId

        DECLARE @closeLenderUserId INT
        DECLARE @closeLawyerUserId INT
        SELECT @closeLenderUserId = lenderUserId, @closeLawyerUserId = lawyerUserId
        FROM legalCases WHERE caseId = @caseId

        SELECT (
            SELECT @caseId AS caseId, 'closed' AS caseStatus,
                   @recoveredAmount AS recoveredAmount,
                   @closeLenderUserId AS lenderUserId, @closeLawyerUserId AS lawyerUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    ELSE IF @action = 'embargo_executed'
    BEGIN
        DECLARE @embargoRecovered DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.case[0].recoveredAmount')
        DECLARE @embargoNote      NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.case[0].statusNote')

        UPDATE legalCases SET
            caseStatus         = 'embargo',
            recoveredAmount    = ISNULL(@embargoRecovered, recoveredAmount),
            statusNote         = ISNULL(@embargoNote, statusNote),
            embargoExecutedAt  = GETUTCDATE(),
            updated_at         = GETUTCDATE()
        WHERE caseId = @caseId AND companyId = @companyId

        INSERT INTO legalCaseNotes (caseId, authorClientId, authorRole, noteText)
        VALUES (@caseId, @clientId, 'system',
                'Embargo ejecutado. Monto recuperado: $' + CAST(ISNULL(@embargoRecovered, 0) AS NVARCHAR))

        DECLARE @embargoLenderUserId INT
        DECLARE @embargoLawyerUserId INT
        SELECT @embargoLenderUserId = lenderUserId, @embargoLawyerUserId = lawyerUserId
        FROM legalCases WHERE caseId = @caseId

        SELECT (
            SELECT @caseId AS caseId, 'embargo' AS caseStatus,
                   @embargoRecovered AS recoveredAmount,
                   @embargoLenderUserId AS lenderUserId, @embargoLawyerUserId AS lawyerUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_listingDrafts
IF OBJECT_ID(N'dbo.sp_listingDrafts', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_listingDrafts];
GO

CREATE PROC [dbo].[sp_listingDrafts] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "listingDrafts": [
        {
        "unifiedProductId": 1,
        "channel": "amazon",
        "market": "US",
        "payloadJson": {
            "title": "Apple iPhone 15 128GB",
            "condition": "new",
            "quantity": 1,
            "brand": "Apple",
            "model": "A2890",
            "images": ["https://example.com/img1.jpg"]
        },
        "suggestedPriceUsd": 799.99,
        "minPriceUsd": 749.99,
        "maxPriceUsd": 849.99,
        "status": "draft",
        "approvedBy": null,
        "approvedAt": null,
        "errorMessage": null,
        "action": "1"
        }
    ]
    }';
    */

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value,'$.action')) FROM OPENJSON(@pjsonfile,'$.listingDrafts'));

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.listingDrafts (
        unifiedProductId, channel, market, payloadJson,
        suggestedPriceUsd, minPriceUsd, maxPriceUsd,
        status, approvedBy, approvedAt, errorMessage
      )
      SELECT
        TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.unifiedProductId')),
        JSON_VALUE(value,'$.channel'),
        ISNULL(NULLIF(JSON_VALUE(value,'$.market'),''),'US'),
        JSON_QUERY(value,'$.payloadJson'),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value,'$.suggestedPriceUsd')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value,'$.minPriceUsd')),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value,'$.maxPriceUsd')),
        ISNULL(NULLIF(JSON_VALUE(value,'$.status'),''),'draft'),
        JSON_VALUE(value,'$.approvedBy'),
        TRY_CONVERT(DATETIME2, JSON_VALUE(value,'$.approvedAt')),
        JSON_VALUE(value,'$.errorMessage')
      FROM OPENJSON(@pjsonfile,'$.listingDrafts');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE d
      SET
        d.unifiedProductId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.unifiedProductId')),
        d.channel = JSON_VALUE(j.value,'$.channel'),
        d.market  = ISNULL(NULLIF(JSON_VALUE(j.value,'$.market'),''),'US'),
        d.payloadJson = JSON_QUERY(j.value,'$.payloadJson'),
        d.suggestedPriceUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value,'$.suggestedPriceUsd')),
        d.minPriceUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value,'$.minPriceUsd')),
        d.maxPriceUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value,'$.maxPriceUsd')),
        d.status = ISNULL(NULLIF(JSON_VALUE(j.value,'$.status'),''), d.status),
        d.approvedBy = JSON_VALUE(j.value,'$.approvedBy'),
        d.approvedAt = TRY_CONVERT(DATETIME2, JSON_VALUE(j.value,'$.approvedAt')),
        d.errorMessage = JSON_VALUE(j.value,'$.errorMessage'),
        d.updatedAt = SYSUTCDATETIME()
      FROM dbo.listingDrafts d
      INNER JOIN OPENJSON(@pjsonfile,'$.listingDrafts') j
        ON d.draftId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.draftId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.listingDrafts
      WHERE draftId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.draftId'))
        FROM OPENJSON(@pjsonfile,'$.listingDrafts')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);
  END CATCH

  SELECT
    JSON_VALUE(value,'$.value') AS [value],
    JSON_VALUE(value,'$.msg') AS [msg],
    JSON_VALUE(value,'$.error') AS [error]
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_loanChat
IF OBJECT_ID(N'dbo.sp_loanChat', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanChat];
GO

CREATE PROCEDURE [dbo].[sp_loanChat]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)   = JSON_VALUE(@pjsonfile, '$.chat[0].action')
    DECLARE @companyId       INT            = JSON_VALUE(@pjsonfile, '$.chat[0].companyId')
    DECLARE @conversationId  INT            = JSON_VALUE(@pjsonfile, '$.chat[0].conversationId')
    DECLARE @clientId        INT            = JSON_VALUE(@pjsonfile, '$.chat[0].clientId')
    DECLARE @userId          INT            = JSON_VALUE(@pjsonfile, '$.chat[0].userId')

    -- ── start_conversation ───────────────────────────────────
    IF @action = 'start_conversation'
    BEGIN
        DECLARE @borrowerId      INT           = JSON_VALUE(@pjsonfile, '$.chat[0].borrowerId')
        DECLARE @lenderId        INT           = JSON_VALUE(@pjsonfile, '$.chat[0].lenderId')
        DECLARE @borrowerUserId  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].borrowerUserId')
        DECLARE @lenderUserId    INT           = JSON_VALUE(@pjsonfile, '$.chat[0].lenderUserId')
        DECLARE @requestedAmt    DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.chat[0].requestedAmount')
        DECLARE @title           NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.chat[0].title')

        -- The frontend often only knows clientIds (the clients API carries no
        -- userId). Push notifications target the stored *userIds*, so resolve
        -- missing/zero ones from users here — otherwise a conversation started
        -- with only lenderId would silently never notify the lender.
        IF ISNULL(@borrowerUserId, 0) = 0
            SELECT TOP 1 @borrowerUserId = userId FROM users WHERE clientId = @borrowerId
        IF ISNULL(@lenderUserId, 0) = 0
            SELECT TOP 1 @lenderUserId = userId FROM users WHERE clientId = @lenderId

        -- Reuse existing open conversation between these two parties
        IF EXISTS (
            SELECT 1 FROM loanConversations
            WHERE companyId = @companyId AND borrowerId = @borrowerId
              AND lenderId = @lenderId AND status = 'open'
        )
        BEGIN
            SELECT (SELECT TOP 1 conversationId, companyId, borrowerId, lenderId,
                borrowerUserId, lenderUserId, status, requestedAmount, title,
                lastMessageAt, created_At
                FROM loanConversations
                WHERE companyId = @companyId AND borrowerId = @borrowerId
                  AND lenderId = @lenderId AND status = 'open'
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
        ELSE
        BEGIN
            INSERT INTO loanConversations
                (companyId, borrowerId, lenderId, borrowerUserId, lenderUserId,
                 requestedAmount, title, lastMessageAt)
            VALUES
                (@companyId, @borrowerId, @lenderId, @borrowerUserId, @lenderUserId,
                 @requestedAmt, @title, GETUTCDATE())

            DECLARE @newConvId INT = SCOPE_IDENTITY()
            SELECT (SELECT conversationId, companyId, borrowerId, lenderId,
                borrowerUserId, lenderUserId, status, requestedAmount, title, created_At
                FROM loanConversations WHERE conversationId = @newConvId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
    END

    -- ── send_message ─────────────────────────────────────────
    ELSE IF @action = 'send_message'
    BEGIN
        DECLARE @senderId    INT           = JSON_VALUE(@pjsonfile, '$.chat[0].senderId')
        DECLARE @senderRole  NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')
        DECLARE @msgType     NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.chat[0].msgType'), 'text')
        DECLARE @body        NVARCHAR(2000)= JSON_VALUE(@pjsonfile, '$.chat[0].body')
        DECLARE @amount      DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.chat[0].amount')
        DECLARE @rate        DECIMAL(6,4)  = JSON_VALUE(@pjsonfile, '$.chat[0].rate')
        DECLARE @termMonths  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].termMonths')
        DECLARE @senderUserId INT          = JSON_VALUE(@pjsonfile, '$.chat[0].senderUserId')

        INSERT INTO loanMessages
            (conversationId, senderId, senderUserId, senderRole, msgType, body, amount, rate, termMonths)
        VALUES
            (@conversationId, @senderId, @senderUserId, @senderRole, @msgType, @body, @amount, @rate, @termMonths)

        DECLARE @newMsgId INT = SCOPE_IDENTITY()

        UPDATE loanConversations
        SET lastMessageAt = GETUTCDATE(), updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId

        -- Return message + target userId for push
        DECLARE @targetUserId INT
        SELECT @targetUserId =
            CASE WHEN borrowerId = @senderId THEN lenderUserId ELSE borrowerUserId END
        FROM loanConversations WHERE conversationId = @conversationId

        SELECT (SELECT @newMsgId AS messageId, @conversationId AS conversationId,
            @msgType AS msgType, @body AS body, @amount AS amount,
            @rate AS rate, @termMonths AS termMonths,
            @targetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    -- ── list_messages ─────────────────────────────────────────
    ELSE IF @action = 'list_messages'
    BEGIN
        SELECT ISNULL(
            (SELECT messageId, conversationId, senderId, senderRole, msgType,
                body, amount, rate, termMonths, isRead, pushSent, created_At
                FROM loanMessages
                WHERE conversationId = @conversationId
                ORDER BY messageId
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── mark_read ─────────────────────────────────────────────
    ELSE IF @action = 'mark_read'
    BEGIN
        UPDATE loanMessages
        SET isRead = 1
        WHERE conversationId = @conversationId AND senderId <> @clientId AND isRead = 0
        SELECT '{"updated":true}' AS [jsonResult]
    END

    -- ── accept_proposal ───────────────────────────────────────
    ELSE IF @action = 'accept_proposal'
    BEGIN
        DECLARE @agreedAmount    DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.chat[0].amount')
        DECLARE @agreedRate      DECIMAL(6,4)  = JSON_VALUE(@pjsonfile, '$.chat[0].rate')
        DECLARE @agreedTerm      INT           = JSON_VALUE(@pjsonfile, '$.chat[0].termMonths')
        DECLARE @acceptSenderId  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].senderId')
        DECLARE @acceptSenderRole NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')

        UPDATE loanConversations SET
            status          = 'accepted',
            agreedAmount    = @agreedAmount,
            agreedRate      = @agreedRate,
            agreedTermMonths = @agreedTerm,
            updated_at      = GETUTCDATE()
        WHERE conversationId = @conversationId

        INSERT INTO loanMessages
            (conversationId, senderId, senderUserId, senderRole, msgType, body, amount, rate, termMonths)
        VALUES
            (@conversationId, @acceptSenderId, @userId, @acceptSenderRole,
             'accept', '✅ Propuesta aceptada — préstamo en proceso.', @agreedAmount, @agreedRate, @agreedTerm)

        DECLARE @acceptTargetUserId INT
        SELECT @acceptTargetUserId =
            CASE WHEN borrowerId = @acceptSenderId THEN lenderUserId ELSE borrowerUserId END
        FROM loanConversations WHERE conversationId = @conversationId

        SELECT (SELECT @conversationId AS conversationId, 'accepted' AS status,
            @agreedAmount AS agreedAmount, @agreedRate AS agreedRate, @agreedTerm AS agreedTermMonths,
            @acceptTargetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    -- ── reject_proposal ───────────────────────────────────────
    ELSE IF @action = 'reject_proposal'
    BEGIN
        DECLARE @rejectSenderId   INT          = JSON_VALUE(@pjsonfile, '$.chat[0].senderId')
        DECLARE @rejectSenderRole NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')

        UPDATE loanConversations SET status = 'rejected', updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId

        INSERT INTO loanMessages
            (conversationId, senderId, senderUserId, senderRole, msgType, body)
        VALUES
            (@conversationId, @rejectSenderId, @userId, @rejectSenderRole,
             'reject', '❌ Propuesta rechazada.')

        DECLARE @rejectTargetUserId INT
        SELECT @rejectTargetUserId =
            CASE WHEN borrowerId = @rejectSenderId THEN lenderUserId ELSE borrowerUserId END
        FROM loanConversations WHERE conversationId = @conversationId

        SELECT (SELECT @conversationId AS conversationId, 'rejected' AS status,
            @rejectTargetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    -- ── list_conversations ────────────────────────────────────
    ELSE IF @action = 'list_conversations'
    BEGIN
        SELECT ISNULL(
            (SELECT conversationId, companyId, borrowerId, lenderId,
                borrowerUserId, lenderUserId, loanProposalId,
                status, requestedAmount, agreedAmount, agreedRate, agreedTermMonths,
                title, lastMessageAt, created_At
                FROM loanConversations
                WHERE companyId = @companyId
                  AND (borrowerId = @clientId OR lenderId = @clientId)
                ORDER BY lastMessageAt DESC
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── get_conversation ──────────────────────────────────────
    ELSE IF @action = 'get_conversation'
    BEGIN
        SELECT ISNULL(
            (SELECT conversationId, companyId, borrowerId, lenderId,
                borrowerUserId, lenderUserId, loanProposalId,
                status, requestedAmount, agreedAmount, agreedRate, agreedTermMonths,
                title, lastMessageAt, created_At, updated_at
                FROM loanConversations
                WHERE conversationId = @conversationId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loanInstallments
IF OBJECT_ID(N'dbo.sp_loanInstallments', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanInstallments];
GO

CREATE PROCEDURE [dbo].[sp_loanInstallments]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action          NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.installments[0].action')
        DECLARE @installmentId   INT           = JSON_VALUE(@pjsonfile, '$.installments[0].installmentId')
        DECLARE @loanId          INT           = JSON_VALUE(@pjsonfile, '$.installments[0].loanId')
        DECLARE @clientId        INT           = JSON_VALUE(@pjsonfile, '$.installments[0].clientId')
        DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.installments[0].companyId')
        DECLARE @lenderId        INT           = JSON_VALUE(@pjsonfile, '$.installments[0].lenderId')
        DECLARE @instNum         INT           = JSON_VALUE(@pjsonfile, '$.installments[0].installmentNumber')
        DECLARE @dueDate         DATE          = JSON_VALUE(@pjsonfile, '$.installments[0].dueDate')
        DECLARE @amount          DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.installments[0].amount')
        DECLARE @principal       DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.installments[0].principal')
        DECLARE @interest        DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.installments[0].interest')
        DECLARE @remaining       DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.installments[0].remainingBalance')
        DECLARE @status          NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.installments[0].status')
        DECLARE @intentId        NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.installments[0].stripePaymentIntentId')
        DECLARE @failReason      NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.installments[0].failureReason')
        DECLARE @attemptCount    INT           = JSON_VALUE(@pjsonfile, '$.installments[0].attemptCount')
        DECLARE @paidAt          DATETIME2     = JSON_VALUE(@pjsonfile, '$.installments[0].paidAt')
        DECLARE @lastAttemptAt   DATETIME2     = JSON_VALUE(@pjsonfile, '$.installments[0].lastAttemptAt')
        DECLARE @asOfDate        DATE          = ISNULL(JSON_VALUE(@pjsonfile, '$.installments[0].asOfDate'), CAST(GETUTCDATE() AS DATE))

        IF @action = 'insert'
        BEGIN
            INSERT INTO [dbo].[loanInstallments]
                (loanId, clientId, companyId, lenderId, installmentNumber, dueDate,
                 amount, principal, interest, remainingBalance, status)
            VALUES
                (@loanId, @clientId, @companyId, @lenderId, @instNum, @dueDate,
                 @amount, @principal, @interest, @remaining, ISNULL(@status,'pending'))

            SELECT (SELECT SCOPE_IDENTITY() AS installmentId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'update_status'
        BEGIN
            UPDATE [dbo].[loanInstallments]
            SET status                  = ISNULL(@status, status),
                stripePaymentIntentId   = ISNULL(@intentId, stripePaymentIntentId),
                failureReason           = ISNULL(@failReason, failureReason),
                attemptCount            = ISNULL(@attemptCount, attemptCount),
                lastAttemptAt           = ISNULL(@lastAttemptAt, lastAttemptAt),
                paidAt                  = ISNULL(@paidAt, paidAt)
            WHERE installmentId = @installmentId

            SELECT '{"message":"updated"}' AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT installmentId, loanId, installmentNumber,
                        CONVERT(NVARCHAR,dueDate,23) AS dueDate,
                        amount, principal, interest, remainingBalance, status,
                        attemptCount,
                        CONVERT(NVARCHAR,paidAt,127) AS paidAt
                 FROM [dbo].[loanInstallments]
                 WHERE loanId=@loanId AND companyId=@companyId
                 ORDER BY installmentNumber
                 FOR JSON PATH, ROOT('installments')),
                '{"installments":[]}'
            ) AS [jsonResult]
        END

        ELSE IF @action = 'due'
        BEGIN
            -- Return all pending/failed installments due today or earlier (for auto-charge)
            SELECT ISNULL(
                (SELECT installmentId, loanId, clientId, lenderId, companyId,
                        installmentNumber,
                        CONVERT(NVARCHAR,dueDate,23) AS dueDate,
                        amount, attemptCount
                 FROM [dbo].[loanInstallments]
                 WHERE companyId = @companyId
                   AND dueDate <= @asOfDate
                   AND status IN ('pending','failed')
                   AND attemptCount < 3
                 ORDER BY dueDate
                 FOR JSON PATH, ROOT('installments')),
                '{"installments":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loanOffers
IF OBJECT_ID(N'dbo.sp_loanOffers', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanOffers];
GO

CREATE PROCEDURE [dbo].[sp_loanOffers]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         INT            = JSON_VALUE(@pjsonfile, '$.loanOffers[0].action')
        DECLARE @offerId        INT            = JSON_VALUE(@pjsonfile, '$.loanOffers[0].offerId')
        DECLARE @companyId      INT            = JSON_VALUE(@pjsonfile, '$.loanOffers[0].companyId')
        DECLARE @lenderId       INT            = JSON_VALUE(@pjsonfile, '$.loanOffers[0].lenderId')
        DECLARE @availableCapital DECIMAL(18,2)= JSON_VALUE(@pjsonfile, '$.loanOffers[0].availableCapital')
        DECLARE @minRate        DECIMAL(5,2)   = JSON_VALUE(@pjsonfile, '$.loanOffers[0].minRate')
        DECLARE @maxRate        DECIMAL(5,2)   = JSON_VALUE(@pjsonfile, '$.loanOffers[0].maxRate')
        DECLARE @minTermMonths  INT            = ISNULL(JSON_VALUE(@pjsonfile, '$.loanOffers[0].minTermMonths'), 1)
        DECLARE @maxTermMonths  INT            = ISNULL(JSON_VALUE(@pjsonfile, '$.loanOffers[0].maxTermMonths'), 24)
        DECLARE @description    NVARCHAR(500)  = JSON_VALUE(@pjsonfile, '$.loanOffers[0].description')
        DECLARE @isActive       BIT            = ISNULL(JSON_VALUE(@pjsonfile, '$.loanOffers[0].isActive'), 1)
        DECLARE @expiresAt      DATETIME2      = JSON_VALUE(@pjsonfile, '$.loanOffers[0].expiresAt')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[loanOffers]
                (companyId, lenderId, availableCapital, minRate, maxRate,
                 minTermMonths, maxTermMonths, description, isActive, expiresAt)
            VALUES
                (@companyId, @lenderId, @availableCapital, @minRate, @maxRate,
                 @minTermMonths, @maxTermMonths, @description, @isActive, @expiresAt)

            SELECT (SELECT TOP 1 * FROM [dbo].[loanOffers]
                    WHERE offerId = SCOPE_IDENTITY() FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE / CLOSE
        BEGIN
            -- availableCapital actualizable: al aceptarse una propuesta el
            -- capital anunciado se consume — la oferta debe reflejarlo (y
            -- desactivarse en 0) para no anunciar dinero ya prestado.
            UPDATE [dbo].[loanOffers]
            SET isActive         = ISNULL(@isActive, isActive),
                description      = ISNULL(@description, description),
                availableCapital = ISNULL(@availableCapital, availableCapital)
            WHERE offerId = @offerId AND companyId = @companyId

            SELECT '{"message":"updated","offerId":' + CAST(@offerId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[loanOffers] WHERE offerId = @offerId AND companyId = @companyId
            SELECT '{"message":"deleted","offerId":' + CAST(@offerId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loanOffers_all
IF OBJECT_ID(N'dbo.sp_loanOffers_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanOffers_all];
GO

CREATE PROCEDURE [dbo].[sp_loanOffers_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.loanOffers[0].companyId')
        DECLARE @isActive  BIT = JSON_VALUE(@pjsonfile, '$.loanOffers[0].isActive')

        SELECT ISNULL(
            (SELECT offerId, companyId, lenderId, availableCapital, minRate, maxRate,
                    minTermMonths, maxTermMonths, description, isActive,
                    CONVERT(NVARCHAR, expiresAt, 127) AS expiresAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM [dbo].[loanOffers]
             WHERE companyId = @companyId
               AND (@isActive IS NULL OR isActive = @isActive)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('loanOffers')),
            '{"loanOffers":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loanOffers_one
IF OBJECT_ID(N'dbo.sp_loanOffers_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanOffers_one];
GO
CREATE PROCEDURE [dbo].[sp_loanOffers_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @offerId INT = JSON_VALUE(@pjsonfile, '$.loanOffers[0].offerId')

        SELECT ISNULL(
            (SELECT TOP 1 * FROM [dbo].[loanOffers]
             WHERE offerId = @offerId
             FOR JSON PATH, ROOT('loanOffers')),
            '{"loanOffers":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loanProposals
IF OBJECT_ID(N'dbo.sp_loanProposals', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanProposals];
GO

CREATE PROCEDURE [dbo].[sp_loanProposals]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].action')
        DECLARE @proposalId     INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].proposalId')
        DECLARE @companyId      INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].companyId')
        DECLARE @lenderId       INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].lenderId')
        DECLARE @borrowerId     INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].borrowerId')
        DECLARE @requestedAmount DECIMAL(18,2)  = JSON_VALUE(@pjsonfile, '$.loanProposals[0].requestedAmount')
        DECLARE @proposedRate   DECIMAL(5,2)    = JSON_VALUE(@pjsonfile, '$.loanProposals[0].proposedRate')
        DECLARE @termMonths     INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].termMonths')
        DECLARE @status         NVARCHAR(20)    = ISNULL(JSON_VALUE(@pjsonfile, '$.loanProposals[0].status'), 'pending')
        DECLARE @borrowerNote   NVARCHAR(500)   = JSON_VALUE(@pjsonfile, '$.loanProposals[0].borrowerNote')
        DECLARE @lenderNote     NVARCHAR(500)   = JSON_VALUE(@pjsonfile, '$.loanProposals[0].lenderNote')
        DECLARE @pushNotificationId INT         = JSON_VALUE(@pjsonfile, '$.loanProposals[0].pushNotificationId')
        DECLARE @respondedAt    DATETIME2       = JSON_VALUE(@pjsonfile, '$.loanProposals[0].respondedAt')
        DECLARE @expiresAt      DATETIME2       = JSON_VALUE(@pjsonfile, '$.loanProposals[0].expiresAt')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[loanProposals]
                (companyId, lenderId, borrowerId, requestedAmount, proposedRate, termMonths,
                 status, borrowerNote, lenderNote, pushNotificationId, expiresAt)
            VALUES
                (@companyId, @lenderId, @borrowerId, @requestedAmount, @proposedRate, @termMonths,
                 @status, @borrowerNote, @lenderNote, @pushNotificationId, @expiresAt)

            SELECT (SELECT TOP 1 proposalId, companyId, lenderId, borrowerId,
                           requestedAmount, proposedRate, termMonths, status,
                           borrowerNote, lenderNote,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[loanProposals]
                    WHERE proposalId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (accept / reject / cancel)
        BEGIN
            UPDATE [dbo].[loanProposals]
            SET status       = ISNULL(@status, status),
                lenderNote   = ISNULL(@lenderNote, lenderNote),
                respondedAt  = ISNULL(@respondedAt, respondedAt),
                updated_at   = GETUTCDATE()
            WHERE proposalId = @proposalId

            SELECT '{"message":"updated","proposalId":' + CAST(@proposalId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[loanProposals] WHERE proposalId = @proposalId
            SELECT '{"message":"deleted","proposalId":' + CAST(@proposalId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loanProposals_all
IF OBJECT_ID(N'dbo.sp_loanProposals_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanProposals_all];
GO

CREATE PROCEDURE [dbo].[sp_loanProposals_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile, '$.loanProposals[0].companyId')
        DECLARE @lenderId   INT          = JSON_VALUE(@pjsonfile, '$.loanProposals[0].lenderId')
        DECLARE @borrowerId INT          = JSON_VALUE(@pjsonfile, '$.loanProposals[0].borrowerId')
        DECLARE @status     NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.loanProposals[0].status')

        SELECT ISNULL(
            (SELECT proposalId, companyId, lenderId, borrowerId,
                    requestedAmount, proposedRate, termMonths, status,
                    borrowerNote, lenderNote, pushNotificationId,
                    CONVERT(NVARCHAR, respondedAt, 127) AS respondedAt,
                    CONVERT(NVARCHAR, expiresAt, 127)   AS expiresAt,
                    CONVERT(NVARCHAR, created_At, 127)  AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127)  AS updated_at
             FROM [dbo].[loanProposals]
             WHERE companyId = @companyId
               AND (@lenderId   IS NULL OR lenderId   = @lenderId)
               AND (@borrowerId IS NULL OR borrowerId = @borrowerId)
               AND (@status     IS NULL OR status     = @status)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('loanProposals')),
            '{"loanProposals":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loanProposals_one
IF OBJECT_ID(N'dbo.sp_loanProposals_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanProposals_one];
GO

CREATE PROCEDURE [dbo].[sp_loanProposals_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @proposalId INT = JSON_VALUE(@pjsonfile, '$.loanProposals[0].proposalId')

        SELECT ISNULL(
            (SELECT TOP 1 * FROM [dbo].[loanProposals]
             WHERE proposalId = @proposalId
             FOR JSON PATH, ROOT('loanProposals')),
            '{"loanProposals":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loans
IF OBJECT_ID(N'dbo.sp_loans', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loans];
GO

CREATE PROCEDURE [dbo].[sp_loans]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action              INT            = JSON_VALUE(@pjsonfile, '$.loans[0].action')
        DECLARE @loanId              INT            = JSON_VALUE(@pjsonfile, '$.loans[0].loanId')
        DECLARE @companyId           INT            = JSON_VALUE(@pjsonfile, '$.loans[0].companyId')
        DECLARE @loanNumber          NVARCHAR(50)   = JSON_VALUE(@pjsonfile, '$.loans[0].loanNumber')
        DECLARE @clientId            INT            = JSON_VALUE(@pjsonfile, '$.loans[0].clientId')
        DECLARE @principalAmount     DECIMAL(18,2)  = JSON_VALUE(@pjsonfile, '$.loans[0].principalAmount')
        DECLARE @interestRate        DECIMAL(5,2)   = JSON_VALUE(@pjsonfile, '$.loans[0].interestRate')
        DECLARE @termMonths          INT            = JSON_VALUE(@pjsonfile, '$.loans[0].termMonths')
        DECLARE @paymentFrequency    NVARCHAR(20)   = ISNULL(JSON_VALUE(@pjsonfile, '$.loans[0].paymentFrequency'), 'monthly')
        DECLARE @approvedAmount      DECIMAL(18,2)  = JSON_VALUE(@pjsonfile, '$.loans[0].approvedAmount')
        DECLARE @totalRepaymentAmount DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.loans[0].totalRepaymentAmount')
        DECLARE @disbursementDate    DATETIME2      = JSON_VALUE(@pjsonfile, '$.loans[0].disbursementDate')
        DECLARE @maturityDate        DATETIME2      = JSON_VALUE(@pjsonfile, '$.loans[0].maturityDate')
        DECLARE @loanStatus          NVARCHAR(30)   = ISNULL(JSON_VALUE(@pjsonfile, '$.loans[0].loanStatus'), 'pending')
        DECLARE @notes               NVARCHAR(MAX)  = JSON_VALUE(@pjsonfile, '$.loans[0].notes')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[loans]
                (companyId, loanNumber, clientId, principalAmount, interestRate, termMonths,
                 paymentFrequency, approvedAmount, totalRepaymentAmount, disbursementDate,
                 maturityDate, loanStatus, notes)
            VALUES
                (@companyId, @loanNumber, @clientId, @principalAmount, @interestRate, @termMonths,
                 @paymentFrequency, @approvedAmount, @totalRepaymentAmount, @disbursementDate,
                 @maturityDate, @loanStatus, @notes)

            SELECT (SELECT TOP 1 loanId, companyId, loanNumber, clientId, principalAmount,
                           interestRate, termMonths, paymentFrequency, approvedAmount,
                           totalRepaymentAmount,
                           CONVERT(NVARCHAR, disbursementDate, 127) AS disbursementDate,
                           CONVERT(NVARCHAR, maturityDate, 127) AS maturityDate,
                           loanStatus, notes,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At,
                           CONVERT(NVARCHAR, updated_at, 127) AS updated_at
                    FROM [dbo].[loans]
                    WHERE loanId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE
        BEGIN
            UPDATE [dbo].[loans]
            SET loanNumber           = ISNULL(@loanNumber, loanNumber),
                principalAmount      = ISNULL(@principalAmount, principalAmount),
                interestRate         = ISNULL(@interestRate, interestRate),
                termMonths           = ISNULL(@termMonths, termMonths),
                paymentFrequency     = ISNULL(@paymentFrequency, paymentFrequency),
                approvedAmount       = ISNULL(@approvedAmount, approvedAmount),
                totalRepaymentAmount = ISNULL(@totalRepaymentAmount, totalRepaymentAmount),
                disbursementDate     = ISNULL(@disbursementDate, disbursementDate),
                maturityDate         = ISNULL(@maturityDate, maturityDate),
                loanStatus           = ISNULL(@loanStatus, loanStatus),
                notes                = ISNULL(@notes, notes),
                updated_at           = GETUTCDATE()
            WHERE loanId = @loanId AND companyId = @companyId

            SELECT '{"message":"updated","loanId":' + CAST(@loanId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[loans] WHERE loanId = @loanId AND companyId = @companyId
            SELECT '{"message":"deleted","loanId":' + CAST(@loanId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loans_all
IF OBJECT_ID(N'dbo.sp_loans_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loans_all];
GO

CREATE PROCEDURE [dbo].[sp_loans_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile, '$.loans[0].companyId')
        DECLARE @loanNumber NVARCHAR(50) = JSON_VALUE(@pjsonfile, '$.loans[0].loanNumber')

        SELECT ISNULL(
            (SELECT loanId, companyId, loanNumber, clientId, principalAmount,
                    interestRate, termMonths, paymentFrequency, approvedAmount,
                    totalRepaymentAmount,
                    CONVERT(NVARCHAR, disbursementDate, 127) AS disbursementDate,
                    CONVERT(NVARCHAR, maturityDate, 127) AS maturityDate,
                    loanStatus, notes,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM [dbo].[loans]
             WHERE companyId = @companyId
               AND (@loanNumber IS NULL OR loanNumber LIKE '%' + @loanNumber + '%')
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('loans')),
            '{"loans":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loans_matchLenders
IF OBJECT_ID(N'dbo.sp_loans_matchLenders', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loans_matchLenders];
GO

CREATE PROCEDURE [dbo].[sp_loans_matchLenders]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT           = JSON_VALUE(@pjsonfile, '$.companyId')
        DECLARE @amount    DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.amount')

        SELECT ISNULL(
            (SELECT c.clientId, u.userId
             FROM dbo.clients c
             INNER JOIN dbo.clientWallets w ON w.clientId = c.clientId AND w.companyId = c.companyId
             INNER JOIN dbo.users u ON u.clientId = c.clientId
             WHERE c.companyId = @companyId
               AND c.clientType IN ('lender', 'both')
               AND w.availableBalance >= @amount
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_loans_one
IF OBJECT_ID(N'dbo.sp_loans_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loans_one];
GO

CREATE PROCEDURE [dbo].[sp_loans_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @loanId    INT = JSON_VALUE(@pjsonfile, '$.loans[0].loanId')
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.loans[0].companyId')

        SELECT ISNULL(
            (SELECT TOP 1 loanId, companyId, loanNumber, clientId, principalAmount,
                          interestRate, termMonths, paymentFrequency, approvedAmount,
                          totalRepaymentAmount,
                          CONVERT(NVARCHAR, disbursementDate, 127) AS disbursementDate,
                          CONVERT(NVARCHAR, maturityDate, 127) AS maturityDate,
                          loanStatus, notes,
                          CONVERT(NVARCHAR, created_At, 127) AS created_At,
                          CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM [dbo].[loans]
             WHERE loanId = @loanId AND companyId = @companyId
             FOR JSON PATH, ROOT('loans')),
            '{"loans":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_login
IF OBJECT_ID(N'dbo.sp_login', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_login];
GO

CREATE PROC [dbo].[sp_login]
(
    @pjsonfile VARCHAR(MAX)
)
AS
BEGIN

    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
      "logins": [
        {
          "username": "admin",
          "password": "123"
        }
      ]
    }'
    */

    DECLARE
        @Outputmessage VARCHAR(MAX) = '
        {
            "result": [
                {
                    "userId": "",
                    "companyId": "",
                    "branchId": "",
                    "roleCode": "",
                    "roleName": "",
                    "clientId": "",
                    "employeeId": "",
                    "msg": "",
                    "error": ""
                }
            ]
        }',
        @userId INT = NULL,
        @companyId INT = NULL,
        @branchId INT = NULL,
        @clientId INT = NULL,
        @employeeId INT = NULL,
        @roleCode VARCHAR(50) = '',
        @roleName VARCHAR(100) = '';

    ---------------------------------------
    -- Parse Login JSON
    ---------------------------------------
    ;WITH CTE_login AS
    (
        SELECT
            JSON_VALUE(value, '$.username') AS username,
            JSON_VALUE(value, '$.password') AS password
        FROM OPENJSON(@pjsonfile, '$.logins')
    )

    ---------------------------------------
    -- Validate User
    ---------------------------------------
    SELECT
        @userId = u.userId,
        @clientId = u.clientId,
        @employeeId = u.employeeId
    FROM dbo.users u
    INNER JOIN CTE_login l
        ON u.name = l.username
       AND u.password = l.password
    WHERE u.active = 1;

    ---------------------------------------
    -- Get company/branch/role from userCompanies
    ---------------------------------------
    IF @userId IS NOT NULL
    BEGIN

        SELECT TOP 1
            @companyId = uc.companyId,
            @branchId = uc.branchId,
            @roleCode = ISNULL(r.code, 'employee'),
            @roleName = ISNULL(r.name, 'Empleado')
        FROM dbo.userCompanies uc
        LEFT JOIN dbo.roles r
            ON r.roleId = uc.roleId
           AND r.active = 1
        WHERE uc.userId = @userId
          AND uc.active = 1
        ORDER BY
            uc.isDefault DESC,
            uc.companyId;

        ---------------------------------------
        -- Fallback to users.companyId
        ---------------------------------------
        IF @companyId IS NULL
        BEGIN
            SELECT
                @companyId = companyId
            FROM dbo.users
            WHERE userId = @userId;
        END

        ---------------------------------------
        -- Default role if none found
        ---------------------------------------
        IF ISNULL(@roleCode, '') = ''
        BEGIN
            SET @roleCode = 'employee';
            SET @roleName = 'Empleado';
        END

    END

    ---------------------------------------
    -- Fallback branch
    ---------------------------------------
    IF @userId IS NOT NULL
       AND @companyId IS NOT NULL
       AND ISNULL(@branchId, 0) = 0
    BEGIN

        SELECT TOP 1
            @branchId = cb.branchId
        FROM dbo.companiesBranch cb
        WHERE cb.companyId = @companyId
          AND ISNULL(cb.active, 1) = 1
        ORDER BY cb.branchId;

    END

    ---------------------------------------
    -- Success Response
    ---------------------------------------
    IF @userId IS NOT NULL
    BEGIN

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].userId',
                CAST(@userId AS VARCHAR(50))
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].companyId',
                CAST(ISNULL(@companyId, 0) AS VARCHAR(50))
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].branchId',
                CAST(ISNULL(@branchId, 0) AS VARCHAR(50))
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].roleCode',
                @roleCode
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].roleName',
                @roleName
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].clientId',
                CAST(ISNULL(@clientId, 0) AS VARCHAR(50))
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].employeeId',
                CAST(ISNULL(@employeeId, 0) AS VARCHAR(50))
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].msg',
                'User Valid'
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].error',
                ''
            );

    END
    ELSE
    BEGIN

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].msg',
                'User Invalid'
            );

        SET @Outputmessage =
            JSON_MODIFY(
                @Outputmessage,
                '$.result[0].error',
                '-1'
            );

    END

    SELECT @Outputmessage AS Outputmessage;

END
GO

-- dbo.sp_logs_all
IF OBJECT_ID(N'dbo.sp_logs_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_logs_all];
GO

CREATE PROC [dbo].[sp_logs_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [logId],
        [tableName],
        [recordId],
        [action],
        [actionTime]
    FROM [montanogilberto_smartloans].[dbo].[logs]
    FOR JSON AUTO, ROOT('logs');
END
GO

-- dbo.sp_machines
IF OBJECT_ID(N'dbo.sp_machines', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_machines];
GO
CREATE PROCEDURE [dbo].[sp_machines]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         NVARCHAR(20)  = JSON_VALUE(@pjsonfile,'$.machines[0].action')
        DECLARE @machineId      INT           = JSON_VALUE(@pjsonfile,'$.machines[0].machineId')
        DECLARE @companyId      INT           = JSON_VALUE(@pjsonfile,'$.machines[0].companyId')
        DECLARE @name           NVARCHAR(100) = JSON_VALUE(@pjsonfile,'$.machines[0].name')
        DECLARE @machineType    NVARCHAR(30)  = JSON_VALUE(@pjsonfile,'$.machines[0].machineType')
        DECLARE @capacityKg     DECIMAL(8,2)  = JSON_VALUE(@pjsonfile,'$.machines[0].capacityKg')
        DECLARE @kwhPerCycle    DECIMAL(8,4)  = JSON_VALUE(@pjsonfile,'$.machines[0].kwhPerCycle')
        DECLARE @litersPerCycle DECIMAL(8,2)  = JSON_VALUE(@pjsonfile,'$.machines[0].litersPerCycle')
        DECLARE @cycleMinutes   INT           = JSON_VALUE(@pjsonfile,'$.machines[0].cycleMinutes')
        DECLARE @purchaseCost   DECIMAL(18,2) = JSON_VALUE(@pjsonfile,'$.machines[0].purchaseCost')
        DECLARE @lifetimeCycles INT           = JSON_VALUE(@pjsonfile,'$.machines[0].lifetimeCycles')
        DECLARE @maintenanceEvery INT         = JSON_VALUE(@pjsonfile,'$.machines[0].maintenanceEvery')
        DECLARE @status         NVARCHAR(20)  = JSON_VALUE(@pjsonfile,'$.machines[0].status')
        DECLARE @location       NVARCHAR(100) = JSON_VALUE(@pjsonfile,'$.machines[0].location')
        DECLARE @serialNumber   NVARCHAR(100) = JSON_VALUE(@pjsonfile,'$.machines[0].serialNumber')
        DECLARE @notes          NVARCHAR(500) = JSON_VALUE(@pjsonfile,'$.machines[0].notes')
        DECLARE @cycleIncrement INT           = JSON_VALUE(@pjsonfile,'$.machines[0].cycleIncrement')
        DECLARE @wearScore      INT           = JSON_VALUE(@pjsonfile,'$.machines[0].wearScore')

        IF @action = 'insert'
        BEGIN
            INSERT INTO [dbo].[machines]
                (companyId, name, machineType, capacityKg, kwhPerCycle, litersPerCycle,
                 cycleMinutes, purchaseCost, lifetimeCycles, maintenanceEvery, status, location, serialNumber, notes)
            VALUES
                (@companyId, @name, ISNULL(@machineType,'washer'), ISNULL(@capacityKg,0),
                 ISNULL(@kwhPerCycle,0), ISNULL(@litersPerCycle,0), ISNULL(@cycleMinutes,45),
                 ISNULL(@purchaseCost,0), ISNULL(@lifetimeCycles,5000), ISNULL(@maintenanceEvery,200),
                 ISNULL(@status,'available'), @location, @serialNumber, @notes)

            SELECT (SELECT SCOPE_IDENTITY() AS machineId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'update'
        BEGIN
            UPDATE [dbo].[machines] SET
                name            = ISNULL(@name, name),
                machineType     = ISNULL(@machineType, machineType),
                capacityKg      = ISNULL(@capacityKg, capacityKg),
                kwhPerCycle     = ISNULL(@kwhPerCycle, kwhPerCycle),
                litersPerCycle  = ISNULL(@litersPerCycle, litersPerCycle),
                cycleMinutes    = ISNULL(@cycleMinutes, cycleMinutes),
                purchaseCost    = ISNULL(@purchaseCost, purchaseCost),
                lifetimeCycles  = ISNULL(@lifetimeCycles, lifetimeCycles),
                maintenanceEvery= ISNULL(@maintenanceEvery, maintenanceEvery),
                status          = ISNULL(@status, status),
                location        = ISNULL(@location, location),
                serialNumber    = ISNULL(@serialNumber, serialNumber),
                notes           = ISNULL(@notes, notes),
                -- increment cycle counter if provided
                currentCycleCount = currentCycleCount + ISNULL(@cycleIncrement, 0),
                lastMaintenanceCycle = CASE WHEN @wearScore IS NOT NULL AND @wearScore < wearScore
                                           THEN currentCycleCount + ISNULL(@cycleIncrement,0)
                                           ELSE lastMaintenanceCycle END,
                wearScore       = ISNULL(@wearScore, wearScore),
                updatedAt       = GETUTCDATE()
            WHERE machineId = @machineId

            SELECT '{"message":"updated"}' AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT machineId, companyId, name, machineType, capacityKg, kwhPerCycle,
                        litersPerCycle, cycleMinutes, purchaseCost, lifetimeCycles,
                        currentCycleCount, maintenanceEvery, lastMaintenanceCycle, wearScore,
                        status, location, serialNumber, notes,
                        CONVERT(NVARCHAR, createdAt, 127) AS createdAt,
                        CONVERT(NVARCHAR, updatedAt, 127) AS updatedAt
                 FROM [dbo].[machines]
                 WHERE companyId = @companyId
                 ORDER BY name
                 FOR JSON PATH, ROOT('machines')),
                '{"machines":[]}'
            ) AS [jsonResult]
        END

        ELSE IF @action = 'one'
        BEGIN
            SELECT ISNULL(
                (SELECT machineId, companyId, name, machineType, capacityKg, kwhPerCycle,
                        litersPerCycle, cycleMinutes, purchaseCost, lifetimeCycles,
                        currentCycleCount, maintenanceEvery, lastMaintenanceCycle, wearScore,
                        status, location, serialNumber, notes,
                        CONVERT(NVARCHAR, createdAt, 127) AS createdAt
                 FROM [dbo].[machines]
                 WHERE machineId = @machineId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_maintenanceLogs
IF OBJECT_ID(N'dbo.sp_maintenanceLogs', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_maintenanceLogs];
GO
CREATE PROCEDURE [dbo].[sp_maintenanceLogs]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         NVARCHAR(10)  = JSON_VALUE(@pjsonfile,'$.logs[0].action')
        DECLARE @companyId      INT           = JSON_VALUE(@pjsonfile,'$.logs[0].companyId')
        DECLARE @machineId      INT           = JSON_VALUE(@pjsonfile,'$.logs[0].machineId')
        DECLARE @logType        NVARCHAR(30)  = JSON_VALUE(@pjsonfile,'$.logs[0].logType')
        DECLARE @description    NVARCHAR(500) = JSON_VALUE(@pjsonfile,'$.logs[0].description')
        DECLARE @techName       NVARCHAR(100) = JSON_VALUE(@pjsonfile,'$.logs[0].technicianName')
        DECLARE @costMXN        DECIMAL(10,2) = JSON_VALUE(@pjsonfile,'$.logs[0].costMXN')
        DECLARE @wearBefore     INT           = JSON_VALUE(@pjsonfile,'$.logs[0].wearBefore')
        DECLARE @wearAfter      INT           = JSON_VALUE(@pjsonfile,'$.logs[0].wearAfter')
        DECLARE @parts          NVARCHAR(500) = JSON_VALUE(@pjsonfile,'$.logs[0].partsReplaced')

        IF @action = 'insert'
        BEGIN
            DECLARE @currCycle INT = ISNULL((SELECT currentCycleCount FROM [dbo].[machines] WHERE machineId=@machineId), 0)
            DECLARE @nextService INT = @currCycle + ISNULL((SELECT maintenanceEvery FROM [dbo].[machines] WHERE machineId=@machineId), 200)

            INSERT INTO [dbo].[maintenanceLogs]
                (companyId, machineId, logType, description, technicianName, costMXN,
                 cycleAtMaintenance, wearBefore, wearAfter, partsReplaced, nextServiceCycle, completedAt)
            VALUES
                (@companyId, @machineId, ISNULL(@logType,'scheduled'), @description, @techName,
                 ISNULL(@costMXN,0), @currCycle, ISNULL(@wearBefore,0), ISNULL(@wearAfter,0),
                 @parts, @nextService, GETUTCDATE())

            -- Reset machine wear and update last maintenance
            UPDATE [dbo].[machines]
            SET wearScore=ISNULL(@wearAfter,0),
                lastMaintenanceCycle=@currCycle,
                status='available',
                updatedAt=GETUTCDATE()
            WHERE machineId=@machineId

            SELECT (SELECT SCOPE_IDENTITY() AS logId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT l.logId, l.machineId, l.logType, l.description, l.technicianName,
                        l.costMXN, l.cycleAtMaintenance, l.wearBefore, l.wearAfter,
                        l.partsReplaced, l.nextServiceCycle,
                        CONVERT(NVARCHAR, l.completedAt, 127) AS completedAt,
                        CONVERT(NVARCHAR, l.createdAt, 127)   AS createdAt,
                        m.name AS machineName
                 FROM [dbo].[maintenanceLogs] l
                 JOIN [dbo].[machines] m ON m.machineId=l.machineId
                 WHERE l.companyId=@companyId
                   AND (@machineId IS NULL OR l.machineId=@machineId)
                 ORDER BY l.createdAt DESC
                 FOR JSON PATH, ROOT('logs')),
                '{"logs":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_marketplaceOrders
IF OBJECT_ID(N'dbo.sp_marketplaceOrders', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_marketplaceOrders];
GO

CREATE PROC [dbo].[sp_marketplaceOrders] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

/*
  DECLARE @pjsonfile VARCHAR(MAX) = '{
  "marketplaceOrders": [
    {
      "channel": "amazon",
      "market": "US",
      "channelOrderId": "AMZ-ORDER-000001",
      "unifiedProductId": 1,
      "quantity": 1,
      "soldPriceUsd": 799.99,
      "buyerAddressJson": {
        "name": "John Doe",
        "email": "john@example.com",
        "phone": "+1-555-0100",
        "address1": "123 Main St",
        "address2": "Apt 5",
        "city": "Phoenix",
        "state": "AZ",
        "postalCode": "85001",
        "country": "US"
      },
      "status": "ORDER_NEW",
      "action": "1"
    }
  ]
}';
*/

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value,'$.action')) FROM OPENJSON(@pjsonfile,'$.marketplaceOrders'));

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.marketplaceOrders (
        channel, market, channelOrderId,
        unifiedProductId, quantity, soldPriceUsd,
        buyerAddressJson, status
      )
      SELECT
        JSON_VALUE(value,'$.channel'),
        ISNULL(NULLIF(JSON_VALUE(value,'$.market'),''),'US'),
        JSON_VALUE(value,'$.channelOrderId'),
        TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.unifiedProductId')),
        ISNULL(TRY_CONVERT(INT, JSON_VALUE(value,'$.quantity')), 1),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value,'$.soldPriceUsd')),
        JSON_QUERY(value,'$.buyerAddressJson'),
        ISNULL(NULLIF(JSON_VALUE(value,'$.status'),''),'ORDER_NEW')
      FROM OPENJSON(@pjsonfile,'$.marketplaceOrders');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE o
      SET
        o.channel = JSON_VALUE(j.value,'$.channel'),
        o.market  = ISNULL(NULLIF(JSON_VALUE(j.value,'$.market'),''),'US'),
        o.channelOrderId = JSON_VALUE(j.value,'$.channelOrderId'),
        o.unifiedProductId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.unifiedProductId')),
        o.quantity = COALESCE(TRY_CONVERT(INT, JSON_VALUE(j.value,'$.quantity')), o.quantity),
        o.soldPriceUsd = COALESCE(TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value,'$.soldPriceUsd')), o.soldPriceUsd),
        o.buyerAddressJson = JSON_QUERY(j.value,'$.buyerAddressJson'),
        o.status = ISNULL(NULLIF(JSON_VALUE(j.value,'$.status'),''), o.status),
        o.updatedAt = SYSUTCDATETIME()
      FROM dbo.marketplaceOrders o
      INNER JOIN OPENJSON(@pjsonfile,'$.marketplaceOrders') j
        ON o.marketplaceOrderId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.marketplaceOrderId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.marketplaceOrders
      WHERE marketplaceOrderId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.marketplaceOrderId'))
        FROM OPENJSON(@pjsonfile,'$.marketplaceOrders')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);
  END CATCH

  SELECT
    JSON_VALUE(value,'$.value') AS [value],
    JSON_VALUE(value,'$.msg') AS [msg],
    JSON_VALUE(value,'$.error') AS [error]
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_mercadolibre_webhook
IF OBJECT_ID(N'dbo.sp_mercadolibre_webhook', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_mercadolibre_webhook];
GO

CREATE   PROC dbo.sp_mercadolibre_webhook
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  INSERT INTO dbo.mercadolibreWebhookLogs(payload)
  VALUES (@pjsonfile);

  SELECT '{"saved": true}' AS result;
END
GO

-- dbo.sp_messageTickets
IF OBJECT_ID(N'dbo.sp_messageTickets', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_messageTickets];
GO

CREATE PROC [dbo].[sp_messageTickets] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

/*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "messageTickets": [
        {
        "channel": "amazon",
        "market": "US",
        "threadId": "THREAD-001",
        "marketplaceOrderId": 1,
        "customerMessage": "Hi, when will my order ship?",
        "suggestedReply": "Hello! Your order is being processed and will ship soon. We will share the tracking once available.",
        "finalReply": null,
        "status": "pending",
        "action": "1"
        }
    ]
    }';
    */

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value,'$.action')) FROM OPENJSON(@pjsonfile,'$.messageTickets'));

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.messageTickets (
        channel, market, threadId, marketplaceOrderId,
        customerMessage, suggestedReply, finalReply,
        status
      )
      SELECT
        JSON_VALUE(value,'$.channel'),
        ISNULL(NULLIF(JSON_VALUE(value,'$.market'),''),'US'),
        JSON_VALUE(value,'$.threadId'),
        TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.marketplaceOrderId')),
        JSON_VALUE(value,'$.customerMessage'),
        JSON_VALUE(value,'$.suggestedReply'),
        JSON_VALUE(value,'$.finalReply'),
        ISNULL(NULLIF(JSON_VALUE(value,'$.status'),''),'pending')
      FROM OPENJSON(@pjsonfile,'$.messageTickets');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE mt
      SET
        mt.channel = JSON_VALUE(j.value,'$.channel'),
        mt.market  = ISNULL(NULLIF(JSON_VALUE(j.value,'$.market'),''),'US'),
        mt.threadId = JSON_VALUE(j.value,'$.threadId'),
        mt.marketplaceOrderId  = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.marketplaceOrderId')),
        mt.customerMessage = JSON_VALUE(j.value,'$.customerMessage'),
        mt.suggestedReply = JSON_VALUE(j.value,'$.suggestedReply'),
        mt.finalReply = JSON_VALUE(j.value,'$.finalReply'),
        mt.status = ISNULL(NULLIF(JSON_VALUE(j.value,'$.status'),''), mt.status),
        mt.updatedAt = SYSUTCDATETIME()
      FROM dbo.messageTickets mt
      INNER JOIN OPENJSON(@pjsonfile,'$.messageTickets') j
        ON mt.ticketId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.ticketId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.messageTickets
      WHERE ticketId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.ticketId'))
        FROM OPENJSON(@pjsonfile,'$.messageTickets')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);
  END CATCH

  SELECT
    JSON_VALUE(value,'$.value') AS [value],
    JSON_VALUE(value,'$.msg') AS [msg],
    JSON_VALUE(value,'$.error') AS [error]
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_messageTickets_next
IF OBJECT_ID(N'dbo.sp_messageTickets_next', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_messageTickets_next];
GO
CREATE   PROC dbo.sp_messageTickets_next
  @batchSize INT = 10
AS
BEGIN
  SET NOCOUNT ON;

  ;WITH cte AS (
    SELECT TOP (@batchSize)
      mt.ticketId
    FROM dbo.messageTickets mt WITH (READPAST, UPDLOCK, ROWLOCK)
    WHERE mt.status IN ('pending')
    ORDER BY mt.updatedAt ASC, mt.ticketId ASC
  )
  UPDATE mt
    SET mt.status = 'processing',
        mt.updatedAt = SYSUTCDATETIME()
  OUTPUT
    inserted.ticketId,
    inserted.channel,
    inserted.market,
    inserted.threadId,
    inserted.marketplaceOrderId,
    inserted.customerMessage,
    inserted.suggestedReply,
    inserted.finalReply,
    inserted.status
  FROM dbo.messageTickets mt
  JOIN cte ON cte.ticketId = mt.ticketId;
END
GO

-- dbo.sp_ml_jobs
IF OBJECT_ID(N'dbo.sp_ml_jobs', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_ml_jobs];
GO

CREATE   PROC dbo.sp_ml_jobs
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE
    @out NVARCHAR(MAX) = N'{"result":[{"value":"","msg":"","error":"0","job_id":null,"status":null,"job_json":null,"payload_json":null}]}',
    @err NVARCHAR(4000) = N'';

  DECLARE @action INT =
    (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
     FROM OPENJSON(@pjsonfile, '$.jobs'));

  IF @action IS NULL
  BEGIN
    SET @out = JSON_MODIFY(@out, '$.result[0].error', '1');
    SET @out = JSON_MODIFY(@out, '$.result[0].msg', 'Invalid input: $.jobs[0].action is required.');
    SELECT 0 AS [ok], @out AS [output_json];
    RETURN;
  END

  BEGIN TRY
    BEGIN TRANSACTION;

    /* =========================
       ACTION 1: ENQUEUE
       ========================= */
    IF @action = 1
    BEGIN
      DECLARE
        @a1_job_type NVARCHAR(30) = COALESCE((SELECT TOP 1 JSON_VALUE(value,'$.job_type') FROM OPENJSON(@pjsonfile,'$.jobs')), N'generic'),
        @a1_status NVARCHAR(20) = COALESCE((SELECT TOP 1 JSON_VALUE(value,'$.status') FROM OPENJSON(@pjsonfile,'$.jobs')), N'queued'),
        @a1_payload_json NVARCHAR(MAX) = COALESCE((SELECT TOP 1 JSON_QUERY(value,'$.payload_json') FROM OPENJSON(@pjsonfile,'$.jobs')), N'{}'),
        @a1_job_id BIGINT;

      -- Ensure payload_json contains max_attempts (used by dequeue logic)
      IF JSON_VALUE(@a1_payload_json,'$.max_attempts') IS NULL
        SET @a1_payload_json = JSON_MODIFY(@a1_payload_json,'$.max_attempts', 6);

      INSERT INTO dbo.ml_jobs
        (job_type, payload_json, [status], attempts, last_error, locked_by, locked_until, created_at, updated_at)
      VALUES
        (@a1_job_type, @a1_payload_json, @a1_status, 0, NULL, NULL, NULL, SYSUTCDATETIME(), SYSUTCDATETIME());

      SET @a1_job_id = SCOPE_IDENTITY();

      DECLARE @a1_job_json NVARCHAR(MAX) =
      (
        SELECT
          j.job_id,
          j.job_type,
          j.[status],
          j.attempts,
          j.locked_by,
          j.locked_until,
          JSON_QUERY(j.last_error) AS last_error,
          j.created_at,
          j.updated_at
        FROM dbo.ml_jobs j
        WHERE j.job_id = @a1_job_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
      );

      SET @out = JSON_MODIFY(@out, '$.result[0].value', '1');
      SET @out = JSON_MODIFY(@out, '$.result[0].msg', 'enqueued');
      SET @out = JSON_MODIFY(@out, '$.result[0].job_id', @a1_job_id);
      SET @out = JSON_MODIFY(@out, '$.result[0].status', @a1_status);
      SET @out = JSON_MODIFY(@out, '$.result[0].job_json', JSON_QUERY(@a1_job_json));
      SET @out = JSON_MODIFY(@out, '$.result[0].payload_json', JSON_QUERY(@a1_payload_json));

      COMMIT TRANSACTION;
      SELECT 1 AS [ok], @out AS [output_json];
      RETURN;
    END

    /* =========================
       ACTION 4: DEQUEUE + LOCK
       - FIFO by created_at
       - payload_json.not_before (ISO datetime) for backoff scheduling
       - payload_json.max_attempts (default 6)
       ========================= */
    IF @action = 4
    BEGIN
      DECLARE
        @a4_locked_by NVARCHAR(80) = COALESCE((SELECT TOP 1 JSON_VALUE(value,'$.locked_by') FROM OPENJSON(@pjsonfile,'$.jobs')), N'ml_worker_01'),
        @a4_lock_seconds INT = COALESCE(TRY_CONVERT(INT,(SELECT TOP 1 JSON_VALUE(value,'$.lock_seconds') FROM OPENJSON(@pjsonfile,'$.jobs'))), 120),
        @a4_now DATETIME2(3) = SYSUTCDATETIME(),
        @a4_job_id BIGINT = NULL;

      DECLARE @picked TABLE (job_id BIGINT);

      ;WITH candidates AS (
        SELECT TOP 1 j.job_id
        FROM dbo.ml_jobs j WITH (READPAST, UPDLOCK, ROWLOCK)
        WHERE j.[status] IN ('queued','retry')
          AND (j.locked_until IS NULL OR j.locked_until < @a4_now)
          AND j.attempts < COALESCE(TRY_CONVERT(INT, JSON_VALUE(j.payload_json,'$.max_attempts')), 6)
          AND (
            JSON_VALUE(j.payload_json,'$.not_before') IS NULL
            OR TRY_CONVERT(DATETIME2(3), JSON_VALUE(j.payload_json,'$.not_before')) <= @a4_now
          )
        ORDER BY j.created_at ASC
      )
      UPDATE j
        SET
          j.[status] = 'running',
          j.locked_by = @a4_locked_by,
          j.locked_until = DATEADD(SECOND, @a4_lock_seconds, @a4_now),
          j.attempts = j.attempts + 1,
          j.updated_at = @a4_now
      OUTPUT inserted.job_id INTO @picked(job_id)
      FROM dbo.ml_jobs j
      INNER JOIN candidates c ON c.job_id = j.job_id;

      SELECT TOP 1 @a4_job_id = job_id FROM @picked;

      IF @a4_job_id IS NULL
      BEGIN
        SET @out = JSON_MODIFY(@out, '$.result[0].value', '0');
        SET @out = JSON_MODIFY(@out, '$.result[0].msg', 'no jobs available');

        COMMIT TRANSACTION;
        SELECT 1 AS [ok], @out AS [output_json];
        RETURN;
      END

      DECLARE @a4_job_json NVARCHAR(MAX) =
      (
        SELECT
          j.job_id,
          j.job_type,
          j.[status],
          j.attempts,
          j.locked_by,
          j.locked_until,
          JSON_QUERY(j.last_error) AS last_error,
          j.created_at,
          j.updated_at
        FROM dbo.ml_jobs j
        WHERE j.job_id = @a4_job_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
      );

      DECLARE @a4_payload_json NVARCHAR(MAX) =
        (SELECT payload_json FROM dbo.ml_jobs WHERE job_id = @a4_job_id);

      SET @out = JSON_MODIFY(@out, '$.result[0].value', '1');
      SET @out = JSON_MODIFY(@out, '$.result[0].msg', 'dequeued');
      SET @out = JSON_MODIFY(@out, '$.result[0].job_id', @a4_job_id);
      SET @out = JSON_MODIFY(@out, '$.result[0].status', 'running');
      SET @out = JSON_MODIFY(@out, '$.result[0].job_json', JSON_QUERY(@a4_job_json));
      SET @out = JSON_MODIFY(@out, '$.result[0].payload_json', JSON_QUERY(COALESCE(@a4_payload_json, N'{}')));

      COMMIT TRANSACTION;
      SELECT 1 AS [ok], @out AS [output_json];
      RETURN;
    END

    /* =========================
       ACTION 2: UPDATE STATUS + last_error + optional unlock
       + optional payload_patch (not_before, max_attempts)
       ========================= */
    IF @action = 2
    BEGIN
      DECLARE
        @a2_job_id BIGINT = TRY_CONVERT(BIGINT,(SELECT TOP 1 JSON_VALUE(value,'$.job_id') FROM OPENJSON(@pjsonfile,'$.jobs'))),
        @a2_status NVARCHAR(20) = (SELECT TOP 1 JSON_VALUE(value,'$.status') FROM OPENJSON(@pjsonfile,'$.jobs')),
        @a2_last_error NVARCHAR(MAX) = (SELECT TOP 1 JSON_QUERY(value,'$.last_error') FROM OPENJSON(@pjsonfile,'$.jobs')),
        @a2_unlock BIT = COALESCE(TRY_CONVERT(BIT,(SELECT TOP 1 JSON_VALUE(value,'$.unlock') FROM OPENJSON(@pjsonfile,'$.jobs'))), 1),
        @a2_payload_patch NVARCHAR(MAX) = (SELECT TOP 1 JSON_QUERY(value,'$.payload_patch') FROM OPENJSON(@pjsonfile,'$.jobs'));

      IF @a2_job_id IS NULL
      BEGIN
        SET @out = JSON_MODIFY(@out, '$.result[0].error', '1');
        SET @out = JSON_MODIFY(@out, '$.result[0].msg', 'Invalid input: $.jobs[0].job_id is required for action=2.');
        ROLLBACK TRANSACTION;
        SELECT 0 AS [ok], @out AS [output_json];
        RETURN;
      END

      -- Merge patch keys into payload_json (supports not_before + max_attempts)
      DECLARE @new_payload NVARCHAR(MAX) = NULL;

      IF @a2_payload_patch IS NOT NULL
      BEGIN
        SELECT @new_payload = payload_json FROM dbo.ml_jobs WHERE job_id = @a2_job_id;

        IF JSON_VALUE(@a2_payload_patch,'$.not_before') IS NOT NULL
          SET @new_payload = JSON_MODIFY(@new_payload,'$.not_before', JSON_VALUE(@a2_payload_patch,'$.not_before'));

        IF JSON_VALUE(@a2_payload_patch,'$.max_attempts') IS NOT NULL
          SET @new_payload = JSON_MODIFY(@new_payload,'$.max_attempts', TRY_CONVERT(INT, JSON_VALUE(@a2_payload_patch,'$.max_attempts')));
      END

      UPDATE dbo.ml_jobs
      SET
        [status] = COALESCE(@a2_status, [status]),
        last_error = COALESCE(@a2_last_error, last_error),
        payload_json = COALESCE(@new_payload, payload_json),
        locked_by = IIF(@a2_unlock = 1 OR @a2_status IN ('succeeded','failed','dead'), NULL, locked_by),
        locked_until = IIF(@a2_unlock = 1 OR @a2_status IN ('succeeded','failed','dead'), NULL, locked_until),
        updated_at = SYSUTCDATETIME()
      WHERE job_id = @a2_job_id;

      DECLARE @a2_updated INT = @@ROWCOUNT;

      DECLARE @a2_job_json NVARCHAR(MAX) =
      (
        SELECT
          j.job_id,
          j.job_type,
          j.[status],
          j.attempts,
          j.locked_by,
          j.locked_until,
          JSON_QUERY(j.last_error) AS last_error,
          j.created_at,
          j.updated_at
        FROM dbo.ml_jobs j
        WHERE j.job_id = @a2_job_id
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
      );

      DECLARE @a2_payload_json NVARCHAR(MAX) =
        (SELECT payload_json FROM dbo.ml_jobs WHERE job_id = @a2_job_id);

      SET @out = JSON_MODIFY(@out, '$.result[0].value', IIF(@a2_updated>0,'1','0'));
      SET @out = JSON_MODIFY(@out, '$.result[0].msg', IIF(@a2_updated>0,'updated','not found'));
      SET @out = JSON_MODIFY(@out, '$.result[0].job_id', @a2_job_id);
      SET @out = JSON_MODIFY(@out, '$.result[0].status', @a2_status);
      SET @out = JSON_MODIFY(@out, '$.result[0].job_json', JSON_QUERY(@a2_job_json));
      SET @out = JSON_MODIFY(@out, '$.result[0].payload_json', JSON_QUERY(COALESCE(@a2_payload_json, N'{}')));

      COMMIT TRANSACTION;
      SELECT 1 AS [ok], @out AS [output_json];
      RETURN;
    END

    /* =========================
       ACTION 3: DELETE
       ========================= */
    IF @action = 3
    BEGIN
      DECLARE @a3_job_id BIGINT = TRY_CONVERT(BIGINT,(SELECT TOP 1 JSON_VALUE(value,'$.job_id') FROM OPENJSON(@pjsonfile,'$.jobs')));

      IF @a3_job_id IS NULL
      BEGIN
        SET @out = JSON_MODIFY(@out, '$.result[0].error', '1');
        SET @out = JSON_MODIFY(@out, '$.result[0].msg', 'Invalid input: $.jobs[0].job_id is required for action=3.');
        ROLLBACK TRANSACTION;
        SELECT 0 AS [ok], @out AS [output_json];
        RETURN;
      END

      DELETE FROM dbo.ml_jobs WHERE job_id = @a3_job_id;

      SET @out = JSON_MODIFY(@out, '$.result[0].value', IIF(@@ROWCOUNT>0,'1','0'));
      SET @out = JSON_MODIFY(@out, '$.result[0].msg', 'deleted');
      SET @out = JSON_MODIFY(@out, '$.result[0].job_id', @a3_job_id);

      COMMIT TRANSACTION;
      SELECT 1 AS [ok], @out AS [output_json];
      RETURN;
    END

    SET @out = JSON_MODIFY(@out, '$.result[0].error', '1');
    SET @out = JSON_MODIFY(@out, '$.result[0].msg', CONCAT('Unsupported action: ', @action));
    ROLLBACK TRANSACTION;
    SELECT 0 AS [ok], @out AS [output_json];
    RETURN;

  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    SET @err = CONCAT('SQL Error ', ERROR_NUMBER(), ' (line ', ERROR_LINE(), '): ', ERROR_MESSAGE());
    SET @out = JSON_MODIFY(@out, '$.result[0].error', '1');
    SET @out = JSON_MODIFY(@out, '$.result[0].msg', @err);

    SELECT 0 AS [ok], @out AS [output_json];
    RETURN;
  END CATCH
END
GO

-- dbo.sp_ml_search_runs
IF OBJECT_ID(N'dbo.sp_ml_search_runs', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_ml_search_runs];
GO

CREATE   PROC dbo.sp_ml_search_runs
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE
    @out NVARCHAR(MAX) =
      N'{"result":[{"value":"","msg":"","error":"0","search_run_id":null,"inserted_results":0,"skipped_duplicates":0,"updated_runs":0,"returned_rows":0,"page":1,"page_size":50,"total_rows":0,"data":null}]}',
    @err NVARCHAR(4000) = N'';

  DECLARE @action INT =
    (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
     FROM OPENJSON(@pjsonfile, '$.search_runs'));

  IF @action IS NULL
  BEGIN
    SET @out = JSON_MODIFY(@out,'$.result[0].error','1');
    SET @out = JSON_MODIFY(@out,'$.result[0].msg','Invalid input: $.search_runs[0].action is required.');
    SELECT 0 AS ok, @out AS output_json;
    RETURN;
  END

  BEGIN TRY
    BEGIN TRANSACTION;

    /* =====================================================
       ACTION 1: CREATE SEARCH RUN
       ===================================================== */
    IF @action = 1
    BEGIN
      DECLARE
        @site_id NVARCHAR(10) = COALESCE(JSON_VALUE(@pjsonfile,'$.search_runs[0].site_id'),'MLM'),
        @query_text NVARCHAR(400) = JSON_VALUE(@pjsonfile,'$.search_runs[0].query_text'),
        @domain_id NVARCHAR(80) = JSON_VALUE(@pjsonfile,'$.search_runs[0].domain_id'),
        @status NVARCHAR(30) = COALESCE(JSON_VALUE(@pjsonfile,'$.search_runs[0].status'),'created'),
        @http_status INT = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.search_runs[0].http_status')),
        @error_json NVARCHAR(MAX) = JSON_QUERY(@pjsonfile,'$.search_runs[0].error_json'),
        @finished_at DATETIME2(3) = TRY_CONVERT(DATETIME2(3),JSON_VALUE(@pjsonfile,'$.search_runs[0].finished_at')),
        @search_run_id BIGINT;

      -- Required field
      IF @query_text IS NULL OR LTRIM(RTRIM(@query_text)) = ''
      BEGIN
        SET @out = JSON_MODIFY(@out,'$.result[0].error','1');
        SET @out = JSON_MODIFY(@out,'$.result[0].msg','Invalid input: query_text is required.');
        ROLLBACK TRANSACTION;
        SELECT 0 AS ok, @out AS output_json;
        RETURN;
      END

      /* ---------- optional domain cache ---------- */
      IF JSON_QUERY(@pjsonfile,'$.search_runs[0].domain_cache') IS NOT NULL
      BEGIN
        INSERT INTO dbo.ml_domains_cache
          (site_id, query_text, domain_id, category_id, attributes_json, raw_json, created_at, updated_at)
        SELECT
          COALESCE(JSON_VALUE(value,'$.site_id'),@site_id),
          COALESCE(JSON_VALUE(value,'$.query_text'),@query_text),
          JSON_VALUE(value,'$.domain_id'),
          JSON_VALUE(value,'$.category_id'),
          JSON_QUERY(value,'$.attributes_json'),
          JSON_QUERY(value,'$.raw_json'),
          SYSUTCDATETIME(),
          SYSUTCDATETIME()
        FROM OPENJSON(@pjsonfile,'$.search_runs[0].domain_cache');
      END

      /* ---------- insert search run ---------- */
      INSERT INTO dbo.ml_search_runs
        (site_id, query_text, domain_id, status, http_status, error_json, finished_at, created_at, updated_at)
      VALUES
        (@site_id,@query_text,@domain_id,@status,@http_status,@error_json,@finished_at,
         SYSUTCDATETIME(),SYSUTCDATETIME());

      SET @search_run_id = SCOPE_IDENTITY();

      /* ---------- optional results ---------- */
      DECLARE @inserted INT = 0, @duplicates INT = 0;

      IF JSON_QUERY(@pjsonfile,'$.search_runs[0].results') IS NOT NULL
      BEGIN
        -- count duplicates BEFORE insert
        ;WITH src AS (
          SELECT DISTINCT JSON_VALUE(value,'$.item_id') AS item_id
          FROM OPENJSON(@pjsonfile,'$.search_runs[0].results')
          WHERE JSON_VALUE(value,'$.item_id') IS NOT NULL
        )
        SELECT @duplicates = COUNT(*)
        FROM src s
        WHERE EXISTS (
          SELECT 1 FROM dbo.ml_search_results r
          WHERE r.search_run_id = @search_run_id
            AND r.item_id = s.item_id
        );

        -- insert new rows
        INSERT INTO dbo.ml_search_results
          (search_run_id,item_id,title,price,currency_id,[condition],permalink,
           seller_id,thumbnail,raw_json,created_at,updated_at)
        SELECT
          @search_run_id,
          JSON_VALUE(value,'$.item_id'),
          JSON_VALUE(value,'$.title'),
          TRY_CONVERT(DECIMAL(18,2),JSON_VALUE(value,'$.price')),
          JSON_VALUE(value,'$.currency_id'),
          JSON_VALUE(value,'$.condition'),
          JSON_VALUE(value,'$.permalink'),
          TRY_CONVERT(BIGINT,JSON_VALUE(value,'$.seller_id')),
          JSON_VALUE(value,'$.thumbnail'),
          JSON_QUERY(value,'$.raw_json'),
          SYSUTCDATETIME(),
          SYSUTCDATETIME()
        FROM OPENJSON(@pjsonfile,'$.search_runs[0].results') v
        WHERE JSON_VALUE(value,'$.item_id') IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM dbo.ml_search_results r
            WHERE r.search_run_id = @search_run_id
              AND r.item_id = JSON_VALUE(value,'$.item_id')
          );

        SET @inserted = @@ROWCOUNT;
      END

      SET @out = JSON_MODIFY(@out,'$.result[0].value','1');
      SET @out = JSON_MODIFY(@out,'$.result[0].msg','search_run created');
      SET @out = JSON_MODIFY(@out,'$.result[0].search_run_id',@search_run_id);
      SET @out = JSON_MODIFY(@out,'$.result[0].inserted_results',@inserted);
      SET @out = JSON_MODIFY(@out,'$.result[0].skipped_duplicates',@duplicates);

      COMMIT TRANSACTION;
      SELECT 1 AS ok, @out AS output_json;
      RETURN;
    END

    /* =====================================================
       ACTION 2: UPDATE RUN
       ===================================================== */
    IF @action = 2
    BEGIN
      DECLARE
        @run_id BIGINT = TRY_CONVERT(BIGINT,JSON_VALUE(@pjsonfile,'$.search_runs[0].search_run_id')),
        @u_status NVARCHAR(30) = JSON_VALUE(@pjsonfile,'$.search_runs[0].status'),
        @u_http INT = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.search_runs[0].http_status')),
        @u_error NVARCHAR(MAX) = JSON_QUERY(@pjsonfile,'$.search_runs[0].error_json'),
        @u_finished DATETIME2(3) = COALESCE(
          TRY_CONVERT(DATETIME2(3),JSON_VALUE(@pjsonfile,'$.search_runs[0].finished_at')),
          SYSUTCDATETIME()
        );

      IF @run_id IS NULL
      BEGIN
        SET @out = JSON_MODIFY(@out,'$.result[0].error','1');
        SET @out = JSON_MODIFY(@out,'$.result[0].msg','search_run_id required.');
        ROLLBACK TRANSACTION;
        SELECT 0 AS ok, @out AS output_json;
        RETURN;
      END

      UPDATE dbo.ml_search_runs
      SET
        status = COALESCE(@u_status,status),
        http_status = COALESCE(@u_http,http_status),
        error_json = COALESCE(@u_error,error_json),
        finished_at = COALESCE(@u_finished,finished_at),
        updated_at = SYSUTCDATETIME()
      WHERE search_run_id = @run_id;

      SET @out = JSON_MODIFY(@out,'$.result[0].value',IIF(@@ROWCOUNT>0,'1','0'));
      SET @out = JSON_MODIFY(@out,'$.result[0].msg','run updated');
      SET @out = JSON_MODIFY(@out,'$.result[0].updated_runs',@@ROWCOUNT);
      SET @out = JSON_MODIFY(@out,'$.result[0].search_run_id',@run_id);

      COMMIT TRANSACTION;
      SELECT 1 AS ok, @out AS output_json;
      RETURN;
    END

    /* =====================================================
       ACTION 3: LIST RUNS
       ===================================================== */
    IF @action = 3
    BEGIN
      DECLARE
        @site NVARCHAR(10) = COALESCE(JSON_VALUE(@pjsonfile,'$.search_runs[0].site_id'),'MLM'),
        @q NVARCHAR(400) = JSON_VALUE(@pjsonfile,'$.search_runs[0].query_text'),
        @st NVARCHAR(30) = JSON_VALUE(@pjsonfile,'$.search_runs[0].status'),
        @page INT = COALESCE(TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.search_runs[0].page')),1),
        @ps INT = COALESCE(TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.search_runs[0].page_size')),50);

      IF @ps > 200 SET @ps = 200;
      DECLARE @off INT = (@page-1)*@ps;

      DECLARE @total INT =
        (SELECT COUNT(*) FROM dbo.ml_search_runs r
         WHERE r.site_id=@site
           AND (@st IS NULL OR r.status=@st)
           AND (@q IS NULL OR r.query_text LIKE '%' + @q + '%'));

      DECLARE @data NVARCHAR(MAX) =
      (
        SELECT
          r.search_run_id,r.site_id,r.query_text,r.domain_id,
          r.status,r.http_status,r.finished_at,r.created_at,r.updated_at
        FROM dbo.ml_search_runs r
        WHERE r.site_id=@site
          AND (@st IS NULL OR r.status=@st)
          AND (@q IS NULL OR r.query_text LIKE '%' + @q + '%')
        ORDER BY r.created_at DESC
        OFFSET @off ROWS FETCH NEXT @ps ROWS ONLY
        FOR JSON PATH
      );

      SET @out = JSON_MODIFY(@out,'$.result[0].value','1');
      SET @out = JSON_MODIFY(@out,'$.result[0].msg','runs listed');
      SET @out = JSON_MODIFY(@out,'$.result[0].page',@page);
      SET @out = JSON_MODIFY(@out,'$.result[0].page_size',@ps);
      SET @out = JSON_MODIFY(@out,'$.result[0].total_rows',@total);
      SET @out = JSON_MODIFY(@out,'$.result[0].data',JSON_QUERY(COALESCE(@data,'[]')));

      COMMIT TRANSACTION;
      SELECT 1 AS ok, @out AS output_json;
      RETURN;
    END

    SET @out = JSON_MODIFY(@out,'$.result[0].error','1');
    SET @out = JSON_MODIFY(@out,'$.result[0].msg','Unsupported action');
    ROLLBACK TRANSACTION;
    SELECT 0 AS ok, @out AS output_json;
    RETURN;

  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SET @err = CONCAT('SQL Error ',ERROR_NUMBER(),' line ',ERROR_LINE(),': ',ERROR_MESSAGE());
    SET @out = JSON_MODIFY(@out,'$.result[0].error','1');
    SET @out = JSON_MODIFY(@out,'$.result[0].msg',@err);
    SELECT 0 AS ok, @out AS output_json;
  END CATCH
END
GO

-- dbo.sp_name_tables
IF OBJECT_ID(N'dbo.sp_name_tables', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_name_tables];
GO
CREATE PROC [dbo].[sp_name_tables](@table_name VARCHAR(50))

AS

SET NOCOUNT ON

BEGIN

 

       --DECLARE @table_name VARCHAR(50) = 'users'

       DECLARE @sql NVARCHAR(MAX)

 

       -- Construct the dynamic SQL statement

       SET @sql = N'

              SELECT * FROM [dbo].' + QUOTENAME(@table_name) + '

              FOR JSON PATH, ROOT(''' + @table_name + ''')'

 

       -- Execute the dynamic SQL statement

       EXEC sp_executesql @sql

END
GO

-- dbo.sp_observability_logBatch
IF OBJECT_ID(N'dbo.sp_observability_logBatch', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_observability_logBatch];
GO
CREATE PROCEDURE [dbo].[sp_observability_logBatch] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- workflow
        INSERT INTO [dbo].[workflowLogs]
            (workflowId, correlationId, companyId, clientId, userId, entityName, entityId,
             workflowName, stepName, actionName, status, message, durationMs,
             requestJson, responseJson, exception, ipAddress, deviceInfo, appVersion, apiEndpoint)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.userId')),
            JSON_VALUE(value, '$.entityName'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.entityId')),
            JSON_VALUE(value, '$.workflowName'),
            JSON_VALUE(value, '$.stepName'),
            JSON_VALUE(value, '$.actionName'),
            JSON_VALUE(value, '$.status'),
            JSON_VALUE(value, '$.message'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.durationMs')),
            JSON_VALUE(value, '$.requestJson'),
            JSON_VALUE(value, '$.responseJson'),
            JSON_VALUE(value, '$.exception'),
            JSON_VALUE(value, '$.ipAddress'),
            JSON_VALUE(value, '$.deviceInfo'),
            JSON_VALUE(value, '$.appVersion'),
            JSON_VALUE(value, '$.apiEndpoint')
        FROM OPENJSON(@pjsonfile, '$.logs') WHERE JSON_VALUE(value, '$.logType') = 'workflow';

        -- application
        INSERT INTO [dbo].[applicationLogs]
            (correlationId, workflowId, companyId, [level], source, message, exception,
             apiEndpoint, httpStatus, durationMs, ipAddress)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            ISNULL(JSON_VALUE(value, '$.level'), 'INFO'),
            JSON_VALUE(value, '$.source'),
            JSON_VALUE(value, '$.message'),
            JSON_VALUE(value, '$.exception'),
            JSON_VALUE(value, '$.apiEndpoint'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.httpStatus')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.durationMs')),
            JSON_VALUE(value, '$.ipAddress')
        FROM OPENJSON(@pjsonfile, '$.logs') WHERE JSON_VALUE(value, '$.logType') = 'application';

        -- integration
        INSERT INTO [dbo].[integrationLogs]
            (correlationId, workflowId, companyId, service, operation, status, httpStatus,
             latencyMs, requestSummary, responseSummary, exception)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            JSON_VALUE(value, '$.service'),
            JSON_VALUE(value, '$.operation'),
            JSON_VALUE(value, '$.status'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.httpStatus')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.latencyMs')),
            JSON_VALUE(value, '$.requestSummary'),
            JSON_VALUE(value, '$.responseSummary'),
            JSON_VALUE(value, '$.exception')
        FROM OPENJSON(@pjsonfile, '$.logs') WHERE JSON_VALUE(value, '$.logType') = 'integration';

        -- audit (also accepted via batch when non-critical; durable path uses sp_auditLog)
        INSERT INTO [dbo].[auditLogs]
            (correlationId, companyId, actorUserId, actorClientId, entityName, entityId,
             fieldName, oldValue, newValue, action, ipAddress, deviceInfo)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.actorUserId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.actorClientId')),
            JSON_VALUE(value, '$.entityName'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.entityId')),
            JSON_VALUE(value, '$.fieldName'),
            JSON_VALUE(value, '$.oldValue'),
            JSON_VALUE(value, '$.newValue'),
            JSON_VALUE(value, '$.action'),
            JSON_VALUE(value, '$.ipAddress'),
            JSON_VALUE(value, '$.deviceInfo')
        FROM OPENJSON(@pjsonfile, '$.logs') WHERE JSON_VALUE(value, '$.logType') = 'audit';

        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_onboardingReminders
IF OBJECT_ID(N'dbo.sp_onboardingReminders', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_onboardingReminders];
GO

CREATE PROCEDURE [dbo].[sp_onboardingReminders]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action       NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.onboardingReminders[0].action')
        DECLARE @companyId    INT           = JSON_VALUE(@pjsonfile, '$.onboardingReminders[0].companyId')
        DECLARE @clientId     INT           = JSON_VALUE(@pjsonfile, '$.onboardingReminders[0].clientId')
        DECLARE @missingSteps NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.onboardingReminders[0].missingSteps')

        -- Returns every client in the company who hasn't already been
        -- reminded (LEFT JOIN ... IS NULL), with the raw per-step
        -- completion flags. The caller decides what "missing" text to
        -- show and whether the client counts as complete overall.
        IF @action = 'getIncomplete'
        BEGIN
            SELECT ISNULL(
                (SELECT c.clientId,
                        CASE WHEN c.qrBlobUrl IS NULL OR c.qrBlobUrl = '' THEN 0 ELSE 1 END AS hasQr,
                        CASE WHEN f.id_front_image_blob_url IS NULL OR f.id_back_image_blob_url IS NULL THEN 0 ELSE 1 END AS hasDocuments,
                        CASE WHEN f.is_verified = 1 THEN 1 ELSE 0 END AS isVerified,
                        CASE WHEN f.contract_accepted = 1 AND f.pagare_accepted = 1 THEN 1 ELSE 0 END AS hasContract,
                        CASE WHEN sca.hasExternalAccount = 1 THEN 1 ELSE 0 END AS hasBankAccount,
                        CASE WHEN spm.stripePaymentMethodId IS NULL THEN 0 ELSE 1 END AS hasSavedCard
                 FROM [dbo].[clients] c
                 LEFT JOIN [dbo].[clientFaceRecognitions] f ON f.clientId = c.clientId AND f.companyId = c.companyId
                 LEFT JOIN [dbo].[stripeConnectedAccounts] sca ON sca.clientId = c.clientId AND sca.companyId = c.companyId
                 LEFT JOIN [dbo].[savedPaymentMethods] spm ON spm.clientId = c.clientId AND spm.companyId = c.companyId
                 LEFT JOIN [dbo].[onboardingReminders] r ON r.clientId = c.clientId AND r.companyId = c.companyId
                 WHERE c.companyId = @companyId AND r.reminderId IS NULL
                 FOR JSON PATH, ROOT('clients')),
                '{"clients":[]}'
            ) AS [jsonResult]
        END

        -- Idempotent: the UNIQUE constraint means a client can only ever
        -- be marked once, matching the "remind once, then stop" behavior.
        ELSE IF @action = 'markReminded'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[onboardingReminders] WHERE clientId = @clientId AND companyId = @companyId)
            BEGIN
                INSERT INTO [dbo].[onboardingReminders] (clientId, companyId, missingSteps)
                VALUES (@clientId, @companyId, @missingSteps)
            END

            SELECT '{"message":"marked"}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_opportunities
IF OBJECT_ID(N'dbo.sp_opportunities', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_opportunities];
GO

CREATE PROC [dbo].[sp_opportunities] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "opportunities": [
        { "asOfDate": "2026-01-17", "action": "1" }
    ]
    }';
    */

  /*
    action:
      1 = Recompute (MERGE) desde buyOffers + sellListings + costRules
      2 = Update status/score manual (por opportunityId)
      3 = Delete (por opportunityId)
  */

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT,
  @asOfDate DATE;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action')) FROM OPENJSON(@pjsonfile, '$.opportunities'));
  SET @asOfDate = TRY_CONVERT(DATE, (SELECT TOP 1 JSON_VALUE(value, '$.asOfDate') FROM OPENJSON(@pjsonfile, '$.opportunities')));
  IF @asOfDate IS NULL SET @asOfDate = CAST(SYSUTCDATETIME() AS DATE);

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      ;WITH LatestRule AS (
        SELECT cr.*,
               ROW_NUMBER() OVER (
                 PARTITION BY cr.channel, cr.market, ISNULL(cr.category,'')
                 ORDER BY cr.effectiveFrom DESC
               ) AS rn
        FROM dbo.costRules cr
        WHERE cr.effectiveFrom <= @asOfDate
          AND (cr.effectiveTo IS NULL OR cr.effectiveTo >= @asOfDate)
      ),
      Rules AS (
        SELECT * FROM LatestRule WHERE rn = 1
      ),
      Candidates AS (
        SELECT
          b.buyOfferId,
          s.sellListingId,
          s.channel,
          s.market,
          COALESCE(b.unifiedProductId, s.unifiedProductId) AS unifiedProductId,
          b.buyPriceUsd,
          ISNULL(b.shippingBuyUsd,0) AS shippingBuyUsd,
          ISNULL(b.taxBuyUsd,0) AS taxBuyUsd,
          s.sellPriceUsd AS sellGrossUsd
        FROM dbo.buyOffers b
        JOIN dbo.sellListings s
          ON b.unifiedProductId IS NOT NULL
         AND s.unifiedProductId = b.unifiedProductId
      ),
      Calc AS (
        SELECT
          c.*,
          r.feePercent,
          r.fixedFeeUsd,
          r.adsPercent,
          r.returnsRate,
          r.avgReturnCostUsd,
          r.packagingCostUsd,
          r.otherCostUsd,
          (c.buyPriceUsd + c.shippingBuyUsd + c.taxBuyUsd + r.packagingCostUsd + r.otherCostUsd) AS buyTotalCostUsd,
          (c.sellGrossUsd * (r.feePercent + r.adsPercent) + r.fixedFeeUsd) AS sellFeesUsd,
          (r.returnsRate * r.avgReturnCostUsd) AS returnsRiskUsd
        FROM Candidates c
        JOIN Rules r
          ON r.channel = c.channel
         AND r.market  = c.market
      )
      MERGE dbo.opportunities AS t
      USING (
        SELECT
          c.unifiedProductId,
          c.buyOfferId,
          c.sellListingId,
          c.channel,
          c.market,
          c.buyTotalCostUsd,
          c.sellGrossUsd,
          c.sellFeesUsd,
          c.returnsRiskUsd,
          (c.sellGrossUsd - c.sellFeesUsd - c.returnsRiskUsd) AS sellNetUsd,
          ((c.sellGrossUsd - c.sellFeesUsd - c.returnsRiskUsd) - c.buyTotalCostUsd) AS netMarginUsd,
          CASE WHEN c.buyTotalCostUsd = 0 THEN 0
               ELSE (((c.sellGrossUsd - c.sellFeesUsd - c.returnsRiskUsd) - c.buyTotalCostUsd) / c.buyTotalCostUsd)
          END AS roi,
          SYSUTCDATETIME() AS calculatedAt
        FROM Calc c
      ) AS s
      ON (t.buyOfferId = s.buyOfferId AND t.sellListingId = s.sellListingId)
      WHEN MATCHED THEN
        UPDATE SET
          t.unifiedProductId = s.unifiedProductId,
          t.channel = s.channel,
          t.market = s.market,
          t.buyTotalCostUsd = s.buyTotalCostUsd,
          t.sellGrossUsd = s.sellGrossUsd,
          t.sellFeesUsd = s.sellFeesUsd,
          t.returnsRiskUsd = s.returnsRiskUsd,
          t.sellNetUsd = s.sellNetUsd,
          t.netMarginUsd = s.netMarginUsd,
          t.roi = s.roi,
          t.calculatedAt = s.calculatedAt,
          t.updatedAt = SYSUTCDATETIME()
      WHEN NOT MATCHED THEN
        INSERT (
          unifiedProductId, buyOfferId, sellListingId, channel, market,
          buyTotalCostUsd, sellGrossUsd, sellFeesUsd, returnsRiskUsd,
          sellNetUsd, netMarginUsd, roi, calculatedAt
        )
        VALUES (
          s.unifiedProductId, s.buyOfferId, s.sellListingId, s.channel, s.market,
          s.buyTotalCostUsd, s.sellGrossUsd, s.sellFeesUsd, s.returnsRiskUsd,
          s.sellNetUsd, s.netMarginUsd, s.roi, s.calculatedAt
        );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Recomputed Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      -- Update status/score manual
      UPDATE o
      SET
        o.status = ISNULL(NULLIF(JSON_VALUE(j.value, '$.status'),''), o.status),
        o.velocityScore = COALESCE(TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(j.value, '$.velocityScore')), o.velocityScore),
        o.confidenceScore = COALESCE(TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(j.value, '$.confidenceScore')), o.confidenceScore),
        o.finalScore = COALESCE(TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(j.value, '$.finalScore')), o.finalScore),
        o.updatedAt = SYSUTCDATETIME()
      FROM dbo.opportunities o
      INNER JOIN OPENJSON(@pjsonfile, '$.opportunities') j
        ON o.opportunityId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.opportunityId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.opportunities
      WHERE opportunityId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.opportunityId'))
        FROM OPENJSON(@pjsonfile, '$.opportunities')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH

  SELECT
    JSON_VALUE(value, '$.value') AS [value],
    JSON_VALUE(value, '$.msg')   AS [msg],
    JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_orders
IF OBJECT_ID(N'dbo.sp_orders', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_orders];
GO

CREATE PROCEDURE [dbo].[sp_orders] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OutputMessage NVARCHAR(MAX) = '{
      "result": [
        { "value": "", "msg": "", "error": "" }
      ]
    }',
    @Error NVARCHAR(500) = '';

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @orderCursor CURSOR;
        SET @orderCursor = CURSOR FOR
        SELECT [value]
        FROM OPENJSON(@pjsonfile, '$.orders');

        DECLARE @order NVARCHAR(MAX);

        OPEN @orderCursor;
        FETCH NEXT FROM @orderCursor INTO @order;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Parse order fields
            DECLARE @productId INT = JSON_VALUE(@order, '$.productId');
            DECLARE @quantity INT = JSON_VALUE(@order, '$.quantity');
            DECLARE @paymentMethod NVARCHAR(50) = JSON_VALUE(@order, '$.paymentMethod');
            DECLARE @orderNumber INT = JSON_VALUE(@order, '$.orderNumber');
            DECLARE @tableNumber INT = JSON_VALUE(@order, '$.tableNumber');
            DECLARE @userId INT = JSON_VALUE(@order, '$.userId');
            DECLARE @total DECIMAL(10,2) = JSON_VALUE(@order, '$.total');
            DECLARE @clientId INT = JSON_VALUE(@order, '$.clientId');
            DECLARE @comments NVARCHAR(MAX) = JSON_VALUE(@order, '$.comments');

            -- Insert into orders table
            INSERT INTO [dbo].[orders] (
                productId, quantity, paymentMethod, orderNumber, tableNumber, userId,
                total, clientId, comments, orderDate, createdAt
            )
            VALUES (
                @productId, @quantity, @paymentMethod, @orderNumber, @tableNumber, @userId,
                @total, @clientId, @comments, GETDATE(), GETDATE()
            );

            DECLARE @orderId INT = SCOPE_IDENTITY();

            -- Insert into orderDetails table using OPENJSON
            INSERT INTO [dbo].[orderDetails] (orderId, productOptionId, productOptionChoiceId)
            SELECT 
                @orderId,
                JSON_VALUE([value], '$.productOptionId'),
                JSON_VALUE([value], '$.productOptionChoiceId')
            FROM OPENJSON(@order, '$.selections');

            -- Insert into orderTracking table for initial status
            -- Assuming 1 = "Pending"
            INSERT INTO [dbo].[orderTracking] (
                orderId,
                orderStatusId,
                changedBy,
                notes
            )
            VALUES (
                @orderId,
                1,           -- OrderStatusId = 1 ("Pending")
                @userId,
                'Order created'
            );

            FETCH NEXT FROM @orderCursor INTO @order;
        END

        CLOSE @orderCursor;
        DEALLOCATE @orderCursor;

        COMMIT TRAN;

        SET @OutputMessage = JSON_MODIFY(@OutputMessage, '$.result[0].msg', 'Orders inserted successfully');

    END TRY
    BEGIN CATCH
        ROLLBACK;

        SET @Error = ERROR_MESSAGE();
        SET @OutputMessage = JSON_MODIFY(@OutputMessage, '$.result[0].error', '1');
        SET @OutputMessage = JSON_MODIFY(@OutputMessage, '$.result[0].msg', @Error);
    END CATCH;

    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@OutputMessage, '$.result');
END
GO

-- dbo.sp_orders_all
IF OBJECT_ID(N'dbo.sp_orders_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_orders_all];
GO

--EXEC [sp_orders_all]

CREATE PROCEDURE [dbo].[sp_orders_all]
AS
BEGIN
    SET NOCOUNT ON;

        SELECT
        o_main.orderId,
        o_main.clientId,
        o_main.total,
        o_main.paymentMethod,
        o_main.comments,
        o_main.createdAt,
        (
            SELECT 
                p.productId AS [id],
                p.name,
                p.description,
                --pd.saleprice AS price,
                NULL AS [image],
                p.categoryId,
                (
                    SELECT 
                        po.productOptionId AS [id],
                        po.name,
                        po.type,
                        (
                            SELECT 
                                poc.choiceKey AS [id],
                                poc.name,
                                poc.price
                            FROM productOptionChoices poc
                            WHERE poc.productOptionId = po.productOptionId
                            FOR JSON PATH
                        ) AS choices
                    FROM productOptions po
                    WHERE po.productId = p.productId
                    FOR JSON PATH
                ) AS options
            FROM orders o
            INNER JOIN products p ON o.productId = p.productId
            LEFT JOIN productsDescription pd ON pd.productId = p.productId
            WHERE o.orderId = o_main.orderId
            GROUP BY p.productId, p.name, p.description,  p.categoryId
            FOR JSON PATH
        ) AS products_food
    FROM orders o_main
    GROUP BY o_main.orderId, o_main.clientId, o_main.total, o_main.paymentMethod, o_main.comments, o_main.createdAt
    FOR JSON PATH;


END
GO

-- dbo.sp_orders_list
IF OBJECT_ID(N'dbo.sp_orders_list', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_orders_list];
GO
CREATE PROC [dbo].[sp_orders_list]
AS
BEGIN
    SELECT 
    orders.orderId,
    orders.orderNumber,
    orders.tableNumber,
    orders.userId,
    orders.total,
    orders.paymentMethod,
    orders.orderDate,
    orders.comments,
    orderStatuses.name AS orderStatusName,
    orderStatuses.color AS orderStatusColor,
    orderTracking.changedAt AS statusChangedAt,
    orderTracking.notes AS statusNotes
    FROM orders
    LEFT JOIN orderTracking ON orders.orderId = orderTracking.orderId
    LEFT JOIN orderStatuses ON orderStatuses.orderStatusId = orderTracking.orderStatusId
    WHERE 
        CAST(orderDate AS DATE) = CAST(GETDATE() AS DATE)
    ORDER BY 
        orders.orderDate DESC, orderTracking.changedAt DESC
    FOR JSON AUTO, ROOT('orders');
END
GO

-- dbo.sp_orders_one
IF OBJECT_ID(N'dbo.sp_orders_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_orders_one];
GO
CREATE PROCEDURE [dbo].[sp_orders_one] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /* 
    DECLARE @pjsonfile NVARCHAR(MAX) = N'{
      "orders": [
        {
          "orderId": 1
        }
      ]
    }'
   */

    DECLARE @OutputMessage NVARCHAR(MAX) = '{
    "result": [
        { "value": "", "msg": "", "error": "" }
    ]
    }',
    @orderId INT;

    -- Extract orderId from JSON input
    SET @orderId = CAST((
        SELECT JSON_VALUE(value, '$.orderId') 
        FROM OPENJSON(@pjsonfile, '$.orders')
    ) AS INT);

    SELECT
        o_main.orderId,
        o_main.clientId,
        o_main.total,
        o_main.paymentMethod,
        o_main.comments,
        o_main.createdAt,
        (
            SELECT 
                p.productId AS [id],
                p.name,
                p.description,
                --pd.saleprice AS price,
                NULL AS [image],
                p.categoryId,
                (
                    SELECT 
                        po.productOptionId AS [id],
                        po.name,
                        po.type,
                        (
                            SELECT 
                                poc.choiceKey AS [id],
                                poc.name,
                                poc.price
                            FROM productOptionChoices poc
                            WHERE poc.productOptionId = po.productOptionId
                            FOR JSON PATH
                        ) AS choices
                    FROM productOptions po
                    WHERE po.productId = p.productId
                    FOR JSON PATH
                ) AS options
            FROM orders o
            INNER JOIN products p ON o.productId = p.productId
            LEFT JOIN productsDescription pd ON pd.productId = p.productId
            WHERE o.orderId = o_main.orderId
            GROUP BY p.productId, p.name, p.description,  p.categoryId
            FOR JSON PATH
        ) AS products_food
    FROM orders o_main
    WHERE o_main.orderId = @orderId
    GROUP BY o_main.orderId, o_main.clientId, o_main.total, o_main.paymentMethod, o_main.comments, o_main.createdAt
    FOR JSON PATH;



END
GO

-- dbo.sp_orders_products_one
IF OBJECT_ID(N'dbo.sp_orders_products_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_orders_products_one];
GO

create PROCEDURE [dbo].[sp_orders_products_one] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile NVARCHAR(MAX) = N'{
      "orders": [
        {
          "orderId": 20
        }
      ]
    }'
    */

    DECLARE @OutputMessage NVARCHAR(MAX) = '{
        "result": [
            { "value": "", "msg": "", "error": "" }
        ]
    }',

    @orderId INT;

    -- Extract orderId from JSON input
    SET @orderId = CAST((
        SELECT JSON_VALUE(value, '$.orderId') 
        FROM OPENJSON(@pjsonfile, '$.orders')
    ) AS INT);

    SELECT
        o.orderId,
        o.orderNumber,
        o.quantity,
        products.name AS productName,
        po.productOptionId,
        po.name AS optionName,
        po.optionKey,
        poc.productOptionChoiceId,
        poc.name AS choiceName,
        poc.price AS choicePrice
    FROM orders o
    INNER JOIN products as products ON products.productId = o.productId
    LEFT JOIN orderDetails od ON od.orderId = o.orderId
    LEFT JOIN productOptions po ON po.productOptionId = od.productOptionId
    LEFT JOIN productOptionChoices poc ON poc.productOptionChoiceId = od.productOptionChoiceId
    WHERE o.orderId = @orderId
    FOR JSON AUTO, ROOT('orderedProducts');

END
GO

-- dbo.sp_orders_tracking_status
IF OBJECT_ID(N'dbo.sp_orders_tracking_status', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_orders_tracking_status];
GO
CREATE PROCEDURE [dbo].[sp_orders_tracking_status]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile nvarchar(max) = '{
        "ordersTraking": [
            {
                "orderId": 17,
                "userId": 1,
                "statusTrakingId": 2
            }
        ]
    }'
    */

    DECLARE @OutputMessage NVARCHAR(MAX) = '{
      "result": [
        { "value": "", "msg": "", "error": "" }
      ]
    }',
    @Error NVARCHAR(500) = '';

    BEGIN TRY
        BEGIN TRAN;

        -- Temp table to hold JSON input
        DECLARE @orders TABLE (
            orderId INT,
            userId INT,
            statusTrakingId INT
        );

        -- Parse input JSON
        INSERT INTO @orders (orderId, userId, statusTrakingId)
        SELECT 
            JSON_VALUE([value], '$.orderId') AS orderId,
            JSON_VALUE([value], '$.userId') AS userId,
            JSON_VALUE([value], '$.statusTrakingId') AS statusTrakingId
        FROM OPENJSON(@pjsonfile, '$.ordersTraking');

        -- Insert into orderTracking using joined status name for note
        INSERT INTO [dbo].[orderTracking] (
            orderId,
            orderStatusId,
            changedBy,
            changedAt,
            notes
        )
        SELECT 
            o.orderId,
            o.statusTrakingId,
            o.userId,
            GETDATE(),
            CONCAT('Status changed set to ', s.name)
        FROM @orders o
        JOIN [dbo].[orderStatuses] s ON o.statusTrakingId = s.orderStatusId;

        COMMIT;

        SET @OutputMessage = JSON_MODIFY(@OutputMessage, '$.result[0].msg', 'Order tracking updated based on flow logic');

    END TRY
    BEGIN CATCH
        ROLLBACK;

        SET @Error = ERROR_MESSAGE();
        SET @OutputMessage = JSON_MODIFY(@OutputMessage, '$.result[0].error', '1');
        SET @OutputMessage = JSON_MODIFY(@OutputMessage, '$.result[0].msg', @Error);
    END CATCH;

    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@OutputMessage, '$.result');
END
GO

-- dbo.sp_paymentIntents
IF OBJECT_ID(N'dbo.sp_paymentIntents', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_paymentIntents];
GO

CREATE PROCEDURE [dbo].[sp_paymentIntents]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action    NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].action')
    DECLARE @companyId INT          = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].companyId')

    -- ── create ───────────────────────────────────────────────
    -- database.hints: idempotency for FUNDING is the unique filtered index
    -- above (UQ_paymentIntents_openFunding) -- violating it raises SQL
    -- error 2601, surfaced as a friendly duplicate message below rather
    -- than a raw constraint-violation string.
    IF @action = 'create'
    BEGIN
        DECLARE @loanId                INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].loanId')
        DECLARE @installmentId         INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].installmentId')
        DECLARE @intentType            NVARCHAR(12)   = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].intentType')
        DECLARE @expectedAmountMXN     DECIMAL(10,2)  = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].expectedAmountMXN')
        DECLARE @payerClientId         INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].payerClientId')
        DECLARE @payeeClientId         INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].payeeClientId')
        DECLARE @beneficiarySnapshotId INT            = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].beneficiarySnapshotId')
        DECLARE @suggestedReference    NVARCHAR(40)   = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].suggestedReference')
        DECLARE @expiresAt             DATETIME2      = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].expiresAt')

        IF @intentType = 'FUNDING' AND EXISTS (
            SELECT 1 FROM dbo.paymentIntents
            WHERE companyId = @companyId AND loanId = @loanId
              AND intentType = 'FUNDING' AND status = 'OPEN'
        )
        BEGIN
            SELECT '{"error":"An OPEN FUNDING intent already exists for this loan."}' AS [jsonResult]
            RETURN
        END

        INSERT INTO dbo.paymentIntents
            (companyId, loanId, installmentId, intentType, expectedAmountMXN,
             payerClientId, payeeClientId, beneficiarySnapshotId,
             suggestedReference, expiresAt, status)
        VALUES
            (@companyId, @loanId, @installmentId, @intentType, @expectedAmountMXN,
             @payerClientId, @payeeClientId, @beneficiarySnapshotId,
             @suggestedReference, @expiresAt, 'OPEN')

        DECLARE @newIntentId INT = SCOPE_IDENTITY()

        SELECT (
            SELECT paymentIntentId, companyId, loanId, installmentId, intentType,
                   expectedAmountMXN, payerClientId, payeeClientId,
                   beneficiarySnapshotId, suggestedReference,
                   CONVERT(NVARCHAR, expiresAt, 127) AS expiresAt,
                   status,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM dbo.paymentIntents WHERE paymentIntentId = @newIntentId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── expire_due ───────────────────────────────────────────
    -- database.hints: "marks OPEN intents with expiresAt <= GETUTCDATE()
    -- as EXPIRED and returns the affected loanIds so the caller can
    -- transition loans to 'expired'." Cron-invoked; @companyId optional
    -- (a global sweep when omitted, matching how other cron sweeps in this
    -- codebase run -- see modules/automatedPayments.py charge_due_installments).
    ELSE IF @action = 'expire_due'
    BEGIN
        DECLARE @expired TABLE (paymentIntentId INT, loanId INT)

        UPDATE dbo.paymentIntents
        SET status = 'EXPIRED', updated_at = GETUTCDATE()
        OUTPUT inserted.paymentIntentId, inserted.loanId INTO @expired
        WHERE status = 'OPEN'
          AND expiresAt IS NOT NULL
          AND expiresAt <= GETUTCDATE()
          AND (@companyId IS NULL OR companyId = @companyId)

        SELECT ISNULL(
            (SELECT paymentIntentId, loanId FROM @expired FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── cancel ───────────────────────────────────────────────
    -- database.hints: "Any other transition must return an error." Only
    -- OPEN -> CANCELLED is valid here -- a DECLARED intent means the real
    -- SPEI may already be in flight (see fundingTransaction/loanPayment's
    -- own escalate/dispute flow for that case instead).
    ELSE IF @action = 'cancel'
    BEGIN
        DECLARE @cancelIntentId INT = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].paymentIntentId')

        IF NOT EXISTS (
            SELECT 1 FROM dbo.paymentIntents
            WHERE paymentIntentId = @cancelIntentId AND companyId = @companyId AND status = 'OPEN'
        )
        BEGIN
            SELECT '{"error":"Intent not found, not OPEN, or belongs to a different company -- cannot cancel."}' AS [jsonResult]
            RETURN
        END

        UPDATE dbo.paymentIntents
        SET status = 'CANCELLED', updated_at = GETUTCDATE()
        WHERE paymentIntentId = @cancelIntentId AND companyId = @companyId

        SELECT (
            SELECT @cancelIntentId AS paymentIntentId, 'CANCELLED' AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── list ─────────────────────────────────────────────────
    -- database.hints origin term: "list_for_loan" -- every intent for one
    -- loan, newest first.
    ELSE IF @action = 'list'
    BEGIN
        DECLARE @listLoanId INT = JSON_VALUE(@pjsonfile, '$.paymentIntents[0].loanId')

        SELECT ISNULL(
            (SELECT paymentIntentId, loanId, installmentId, intentType,
                    expectedAmountMXN, payerClientId, payeeClientId,
                    beneficiarySnapshotId, suggestedReference,
                    CONVERT(NVARCHAR, expiresAt, 127) AS expiresAt,
                    status,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM dbo.paymentIntents
             WHERE companyId = @companyId AND loanId = @listLoanId
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            SELECT '{"error":"An OPEN FUNDING intent already exists for this loan."}' AS [jsonResult]
        ELSE
            SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_pos_laundry
IF OBJECT_ID(N'dbo.sp_pos_laundry', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pos_laundry];
GO

CREATE PROC [dbo].[sp_pos_laundry] (@pjsonfile VARCHAR(MAX))
-- action: INSERT=1, UPDATE=2, DELETE=3
AS
SET NOCOUNT ON;
/*
DECLARE @jsonfile_new VARCHAR(MAX) = '{
  "pos_laundry": [
    {
      "total": 420.50,
      "companyId": 1,
      "action": 1,
      "details": [
        {"productId": 201, "cantidad": 4, "precio_unitario": 40.00},
        {"productId": 202, "cantidad": 2, "precio_unitario": 50.25},
        {"productId": 203, "cantidad": 1, "precio_unitario": 60.00}
      ]
    }
  ]
}';
*/

DECLARE @Outputmessage NVARCHAR(MAX) = '
{
  "result": [
  {
     "value": "",
     "msg": "",
     "error": ""
   }
  ]
}',
@Error NVARCHAR(500) = '',
@action INT,
@companyId INT,
@laundryId INT;

BEGIN
    -- Leer action y companyId del JSON
    SET @action = (
        SELECT TOP 1 JSON_VALUE(value, '$.action')
        FROM OPENJSON(@pjsonfile, '$.pos_laundry')
    );

    SET @companyId = (
        SELECT TOP 1 TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.pos_laundry')
    );

    BEGIN TRY
        -- Validar companyId
        IF @companyId IS NULL
            RAISERROR('companyId is required.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM [dbo].[companies] WHERE [companyId] = @companyId)
            RAISERROR('The specified companyId does not exist.', 16, 1);

        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- INSERT pos_laundry
            INSERT INTO [dbo].[pos_laundry] (total)
            SELECT JSON_VALUE(value, '$.total')
            FROM OPENJSON(@pjsonfile, '$.pos_laundry');

            SET @laundryId = SCOPE_IDENTITY();

            -- INSERT pos_laundry_detail
            INSERT INTO [dbo].[pos_laundry_detail] (laundryId, productId, cantidad, precio_unitario)
            SELECT
                @laundryId,
                JSON_VALUE(d.value, '$.productId'),
                JSON_VALUE(d.value, '$.cantidad'),
                JSON_VALUE(d.value, '$.precio_unitario')
            FROM OPENJSON(@pjsonfile, '$.pos_laundry.details') d;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@laundryId AS NVARCHAR(50)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- UPDATE pos_laundry
            UPDATE l
            SET l.total = JSON_VALUE(j.value, '$.total'),
                l.update_at = GETDATE()
            FROM [dbo].[pos_laundry] l
            INNER JOIN OPENJSON(@pjsonfile, '$.pos_laundry') j
                ON l.laundryId = TRY_CAST(JSON_VALUE(j.value, '$.laundryId') AS INT);

            -- UPDATE pos_laundry_detail
            UPDATE d
            SET 
                d.cantidad = JSON_VALUE(jd.value, '$.cantidad'),
                d.precio_unitario = JSON_VALUE(jd.value, '$.precio_unitario'),
                d.update_at = GETDATE()
            FROM [dbo].[pos_laundry_detail] d
            INNER JOIN OPENJSON(@pjsonfile, '$.pos_laundry.details') jd
                ON d.laundryDetailId = TRY_CAST(JSON_VALUE(jd.value, '$.laundryDetailId') AS INT);

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- DELETE pos_laundry_detail
            DELETE d
            FROM [dbo].[pos_laundry_detail] d
            INNER JOIN OPENJSON(@pjsonfile, '$.pos_laundry.details') jd
                ON d.laundryDetailId = TRY_CAST(JSON_VALUE(jd.value, '$.laundryDetailId') AS INT);

            -- DELETE pos_laundry
            DELETE l
            FROM [dbo].[pos_laundry] l
            INNER JOIN OPENJSON(@pjsonfile, '$.pos_laundry') j
                ON l.laundryId = TRY_CAST(JSON_VALUE(j.value, '$.laundryId') AS INT);

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
            RAISERROR('Invalid action. Use 1=INSERT, 2=UPDATE, 3=DELETE.', 16, 1);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH;

    -- Retornar resultado
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg')   AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_pos_laundry_all
IF OBJECT_ID(N'dbo.sp_pos_laundry_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pos_laundry_all];
GO

CREATE  PROC [dbo].[sp_pos_laundry_all]
AS
SET NOCOUNT ON;

BEGIN
    -- Verificar si hay datos en pos_laundry
    IF EXISTS (SELECT 1 FROM [dbo].[pos_laundry])
    BEGIN
        -- Devolver registros de lavandería con sus detalles en JSON
        SELECT 
            l.laundryId,
            l.total,
            l.create_at,
            l.update_at,
            (
                SELECT 
                    d.laundryDetailId,
                    d.productId,
                    d.cantidad,
                    d.precio_unitario,
                    d.subtotal,
                    d.create_at,
                    d.update_at
                FROM [dbo].[pos_laundry_detail] d
                WHERE d.laundryId = l.laundryId
                FOR JSON AUTO
            ) AS details
        FROM [dbo].[pos_laundry] l
        FOR JSON AUTO, ROOT('pos_laundry');
    END
    ELSE
    BEGIN
        -- Si no hay datos, regresar JSON vacío con la raíz 'pos_laundry'
        SELECT '[]' AS [pos_laundry]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END;
GO

-- dbo.sp_procurementJobs
IF OBJECT_ID(N'dbo.sp_procurementJobs', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_procurementJobs];
GO

CREATE PROC [dbo].[sp_procurementJobs] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

/*
  DECLARE @pjsonfile VARCHAR(MAX) = '{
  "procurementJobs": [
    {
      "marketplaceOrderId": 1,
      "supplierCandidate": "Walmart",
      "maxBuyCostUsd": 650.00,
      "decision": "",
      "reason": "Best price found within SLA",
      "action": "1"
    }
  ]
}';
*/

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value,'$.action')) FROM OPENJSON(@pjsonfile,'$.procurementJobs'));

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.procurementJobs (
        marketplaceOrderId, supplierCandidate, maxBuyCostUsd, decision, reason
      )
      SELECT
        TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.marketplaceOrderId')),
        JSON_VALUE(value,'$.supplierCandidate'),
        TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(value,'$.maxBuyCostUsd')),
        NULLIF(JSON_VALUE(value,'$.decision'),''),
        JSON_VALUE(value,'$.reason')
      FROM OPENJSON(@pjsonfile,'$.procurementJobs');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE pj
      SET
        pj.marketplaceOrderId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.marketplaceOrderId')),
        pj.supplierCandidate = JSON_VALUE(j.value,'$.supplierCandidate'),
        pj.maxBuyCostUsd = TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value,'$.maxBuyCostUsd')),
        pj.decision = NULLIF(JSON_VALUE(j.value,'$.decision'),''),
        pj.reason = JSON_VALUE(j.value,'$.reason'),
        pj.updatedAt = SYSUTCDATETIME()
      FROM dbo.procurementJobs pj
      INNER JOIN OPENJSON(@pjsonfile,'$.procurementJobs') j
        ON pj.procJobId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.procJobId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.procurementJobs
      WHERE procJobId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.procJobId'))
        FROM OPENJSON(@pjsonfile,'$.procurementJobs')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);
  END CATCH

  SELECT
    JSON_VALUE(value,'$.value') AS [value],
    JSON_VALUE(value,'$.msg') AS [msg],
    JSON_VALUE(value,'$.error') AS [error]
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_productMatches
IF OBJECT_ID(N'dbo.sp_productMatches', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_productMatches];
GO

CREATE PROC [dbo].[sp_productMatches] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

/*
  DECLARE @pjsonfile VARCHAR(MAX) = '{
  "productMatches": [
    {
      "unifiedProductId": 1,
      "entityType": "buy",
      "entityId": 10,
      "confidence": 0.9450,
      "matchMethod": "embedding",
      "action": "1"
    }
  ]
}';

*/

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (
    SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
    FROM OPENJSON(@pjsonfile, '$.productMatches')
  );

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.productMatches (
        unifiedProductId, entityType, entityId,
        confidence, matchMethod
      )
      SELECT
        TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.unifiedProductId')),
        JSON_VALUE(value, '$.entityType'),
        TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.entityId')),
        TRY_CONVERT(DECIMAL(5,4), JSON_VALUE(value, '$.confidence')),
        JSON_VALUE(value, '$.matchMethod')
      FROM OPENJSON(@pjsonfile, '$.productMatches');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE pm
      SET
        pm.unifiedProductId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.unifiedProductId')),
        pm.entityType = JSON_VALUE(j.value, '$.entityType'),
        pm.entityId   = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.entityId')),
        pm.confidence = TRY_CONVERT(DECIMAL(5,4), JSON_VALUE(j.value, '$.confidence')),
        pm.matchMethod = JSON_VALUE(j.value, '$.matchMethod')
      FROM dbo.productMatches pm
      INNER JOIN OPENJSON(@pjsonfile, '$.productMatches') j
        ON pm.matchId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.matchId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.productMatches
      WHERE matchId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.matchId'))
        FROM OPENJSON(@pjsonfile, '$.productMatches')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH

  SELECT
    JSON_VALUE(value, '$.value') AS [value],
    JSON_VALUE(value, '$.msg')   AS [msg],
    JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_productionOrders
IF OBJECT_ID(N'dbo.sp_productionOrders', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_productionOrders];
GO
CREATE PROCEDURE [dbo].[sp_productionOrders]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         NVARCHAR(20)  = JSON_VALUE(@pjsonfile,'$.orders[0].action')
        DECLARE @orderId        INT           = JSON_VALUE(@pjsonfile,'$.orders[0].orderId')
        DECLARE @companyId      INT           = JSON_VALUE(@pjsonfile,'$.orders[0].companyId')
        DECLARE @clientId       INT           = JSON_VALUE(@pjsonfile,'$.orders[0].clientId')
        DECLARE @ticketId       INT           = JSON_VALUE(@pjsonfile,'$.orders[0].ticketId')
        DECLARE @machineId      INT           = JSON_VALUE(@pjsonfile,'$.orders[0].machineId')
        DECLARE @assignedBy     INT           = JSON_VALUE(@pjsonfile,'$.orders[0].assignedBy')
        DECLARE @cycleType      NVARCHAR(30)  = JSON_VALUE(@pjsonfile,'$.orders[0].cycleType')
        DECLARE @weightKg       DECIMAL(8,2)  = JSON_VALUE(@pjsonfile,'$.orders[0].weightKg')
        DECLARE @detergentGrams DECIMAL(8,2)  = JSON_VALUE(@pjsonfile,'$.orders[0].detergentGrams')
        DECLARE @extraDetergent BIT           = JSON_VALUE(@pjsonfile,'$.orders[0].extraDetergent')
        DECLARE @status         NVARCHAR(20)  = JSON_VALUE(@pjsonfile,'$.orders[0].status')
        DECLARE @startedAt      DATETIME2     = JSON_VALUE(@pjsonfile,'$.orders[0].startedAt')
        DECLARE @completedAt    DATETIME2     = JSON_VALUE(@pjsonfile,'$.orders[0].completedAt')
        DECLARE @actualMinutes  INT           = JSON_VALUE(@pjsonfile,'$.orders[0].actualMinutes')
        DECLARE @notes          NVARCHAR(500) = JSON_VALUE(@pjsonfile,'$.orders[0].notes')
        DECLARE @ticketPrice    DECIMAL(10,2) = JSON_VALUE(@pjsonfile,'$.orders[0].ticketPrice')
        DECLARE @realCostTotal  DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostTotal')
        DECLARE @realCostElec   DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostElec')
        DECLARE @realCostWater  DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostWater')
        DECLARE @realCostDet    DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostDetergent')
        DECLARE @realCostLabor  DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostLabor')
        DECLARE @realCostDeprec DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostDepreciation')
        DECLARE @realCostOvrh   DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostOverhead')
        DECLARE @margin         DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].margin')
        DECLARE @marginPct      DECIMAL(6,2)  = JSON_VALUE(@pjsonfile,'$.orders[0].marginPct')
        DECLARE @alertSent      BIT           = JSON_VALUE(@pjsonfile,'$.orders[0].alertSent')
        DECLARE @periodDays     INT           = ISNULL(JSON_VALUE(@pjsonfile,'$.orders[0].periodDays'), 30)

        IF @action = 'insert'
        BEGIN
            -- Validate machine is available
            IF NOT EXISTS (SELECT 1 FROM [dbo].[machines] WHERE machineId=@machineId AND status='available')
            BEGIN
                SELECT '{"error":"Machine not available"}' AS [jsonResult]
                RETURN
            END

            INSERT INTO [dbo].[productionOrders]
                (companyId, clientId, ticketId, machineId, assignedBy, cycleType,
                 weightKg, detergentGrams, extraDetergent, status, notes,
                 estimatedMinutes)
            SELECT @companyId, @clientId, @ticketId, @machineId, @assignedBy,
                   ISNULL(@cycleType,'normal'), ISNULL(@weightKg,0), ISNULL(@detergentGrams,0),
                   ISNULL(@extraDetergent,0), 'queued', @notes, cycleMinutes
            FROM [dbo].[machines] WHERE machineId = @machineId

            -- Mark machine as in_use
            UPDATE [dbo].[machines] SET status='in_use', updatedAt=GETUTCDATE() WHERE machineId=@machineId

            SELECT (SELECT SCOPE_IDENTITY() AS orderId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'start'
        BEGIN
            UPDATE [dbo].[productionOrders]
            SET status='running', startedAt=GETUTCDATE(), updatedAt=GETUTCDATE()
            WHERE orderId=@orderId
            SELECT '{"message":"started"}' AS [jsonResult]
        END

        ELSE IF @action = 'complete'
        BEGIN
            DECLARE @startTime DATETIME2 = (SELECT startedAt FROM [dbo].[productionOrders] WHERE orderId=@orderId)
            DECLARE @mins INT = DATEDIFF(MINUTE, @startTime, GETUTCDATE())

            UPDATE [dbo].[productionOrders]
            SET status='done', completedAt=GETUTCDATE(), actualMinutes=@mins,
                realCostElec=@realCostElec, realCostWater=@realCostWater,
                realCostDetergent=@realCostDet, realCostLabor=@realCostLabor,
                realCostDepreciation=@realCostDeprec, realCostOverhead=@realCostOvrh,
                realCostTotal=@realCostTotal, ticketPrice=@ticketPrice,
                margin=@margin, marginPct=@marginPct,
                updatedAt=GETUTCDATE()
            WHERE orderId=@orderId

            -- Free machine, increment cycle
            UPDATE [dbo].[machines]
            SET status='available',
                currentCycleCount = currentCycleCount + 1,
                updatedAt=GETUTCDATE()
            WHERE machineId = (SELECT machineId FROM [dbo].[productionOrders] WHERE orderId=@orderId)

            SELECT '{"message":"completed"}' AS [jsonResult]
        END

        ELSE IF @action = 'alert_sent'
        BEGIN
            UPDATE [dbo].[productionOrders] SET alertSent=1, updatedAt=GETUTCDATE() WHERE orderId=@orderId
            SELECT '{"message":"alert_sent"}' AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT o.orderId, o.companyId, o.clientId, o.ticketId, o.machineId,
                        o.cycleType, o.weightKg, o.detergentGrams, o.status,
                        o.estimatedMinutes, o.actualMinutes,
                        o.realCostTotal, o.ticketPrice, o.margin, o.marginPct,
                        o.alertSent,
                        CONVERT(NVARCHAR,o.startedAt,127)   AS startedAt,
                        CONVERT(NVARCHAR,o.completedAt,127) AS completedAt,
                        CONVERT(NVARCHAR,o.createdAt,127)   AS createdAt,
                        m.name AS machineName, m.machineType
                 FROM [dbo].[productionOrders] o
                 LEFT JOIN [dbo].[machines] m ON m.machineId = o.machineId
                 WHERE o.companyId = @companyId
                   AND o.createdAt >= DATEADD(DAY, -@periodDays, GETUTCDATE())
                 ORDER BY o.createdAt DESC
                 FOR JSON PATH, ROOT('orders')),
                '{"orders":[]}'
            ) AS [jsonResult]
        END

        ELSE IF @action = 'active'
        BEGIN
            -- Orders currently running or queued
            SELECT ISNULL(
                (SELECT o.orderId, o.machineId, o.clientId, o.cycleType, o.status,
                        o.estimatedMinutes, o.alertSent,
                        CONVERT(NVARCHAR,o.startedAt,127) AS startedAt,
                        m.name AS machineName, m.cycleMinutes
                 FROM [dbo].[productionOrders] o
                 JOIN [dbo].[machines] m ON m.machineId = o.machineId
                 WHERE o.companyId = @companyId AND o.status IN ('queued','running')
                 ORDER BY o.createdAt
                 FOR JSON PATH, ROOT('orders')),
                '{"orders":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_products
IF OBJECT_ID(N'dbo.sp_products', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products];
GO

CREATE PROC [dbo].[sp_products] (@pjsonfile VARCHAR(MAX))
-- INSERT --> 1
-- UPDATE --> 2
-- DELETE --> 3
AS
SET NOCOUNT ON;

/*
DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
            "productId": 1,
            "name": "exaliv",
            "barCode": "",
            "code": "",
            "dateOfExpire": "2024-03-12",
            "productFormId": 1,
            "manufactureId": 1,
            "description": "",
            "createdAt": "2024-03-12T20:31:06.490",
            "updatedAt": "1900-01-01T00:00:00",
            "companyId": 1,
            "action": 1
            
        }
    ]
}'
*/

DECLARE @Outputmessage NVARCHAR(MAX) = '
{
  "result": [
  {
     "value": "",
     "msg": "",
     "error": ""
   }
  ]
}',
@Error NVARCHAR(500) = '',
@action INT,
@product_id INT,
@companyId INT;

BEGIN
    -- Read action and companyId from the JSON payload
    SET @action = (
        SELECT TOP 1 JSON_VALUE(value, '$.action')
        FROM OPENJSON(@pjsonfile, '$.products')
    );

    SET @companyId = (
        SELECT TOP 1 TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.products')
    );

    BEGIN TRY
        -- Validate companyId is present and equals 1
        IF @companyId IS NULL
        BEGIN
            RAISERROR('companyId is required.', 16, 1);
        END;

        IF @companyId <> 1
        BEGIN
            RAISERROR('Invalid companyId. ', 16, 1);
        END;

        -- Validate company exists
        IF NOT EXISTS (SELECT 1 FROM [dbo].[companies] WHERE [companyId] = @companyId)
        BEGIN
            RAISERROR('The specified companyId does not exist.', 16, 1);
        END;

        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- INSERT (scoped to companyId)
            INSERT INTO [dbo].[products] (
                [name],
                [barCode],
                [code],
                [dateOfExpire],
                [productFormId],
                [manufactureId],
                [description],
                [createdAt],
                [updatedAt],
                [categoryId],
                [companyId]
            )
            SELECT
                JSON_VALUE(value, '$.name'),
                JSON_VALUE(value, '$.barCode'),
                JSON_VALUE(value, '$.code'),
                JSON_VALUE(value, '$.dateOfExpire'),
                JSON_VALUE(value, '$.productFormId'),
                JSON_VALUE(value, '$.manufactureId'),
                JSON_VALUE(value, '$.description'),
                GETDATE(),
                NULL,
                JSON_VALUE(value, '$.categoryId'),
                @companyId
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @product_id = SCOPE_IDENTITY();
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@product_id AS NVARCHAR(50)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- UPDATE (only update rows that belong to companyId)
            UPDATE p
            SET 
                p.[name]          = JSON_VALUE(j.value, '$.name'),
                p.[barCode]       = JSON_VALUE(j.value, '$.barCode'),
                p.[code]          = JSON_VALUE(j.value, '$.code'),
                p.[dateOfExpire]  = JSON_VALUE(j.value, '$.dateOfExpire'),
                p.[productFormId] = JSON_VALUE(j.value, '$.productFormId'),
                p.[manufactureId] = JSON_VALUE(j.value, '$.manufactureId'),
                p.[description]   = JSON_VALUE(j.value, '$.description'),
                p.[createdAt]     = COALESCE(JSON_VALUE(j.value, '$.createdAt'), p.[createdAt]),
                p.[updatedAt]     = COALESCE(JSON_VALUE(j.value, '$.updatedAt'), GETDATE()),
                p.[categoryId]    = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.categoryId') AS INT), p.[categoryId]),
                p.[companyId]     = @companyId -- keep product scoped to this company
            FROM [dbo].[products] p
            INNER JOIN OPENJSON(@pjsonfile, '$.products') j
                ON p.[productId] = TRY_CAST(JSON_VALUE(j.value, '$.productId') AS INT)
               AND p.[companyId] = @companyId;  -- scope by company

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- DELETE (only delete rows that belong to companyId)
            DELETE p
            FROM [dbo].[products] p
            INNER JOIN OPENJSON(@pjsonfile, '$.products') j
                ON p.[productId] = TRY_CAST(JSON_VALUE(j.value, '$.productId') AS INT)
               AND p.[companyId] = @companyId; -- scope by company

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            RAISERROR('Invalid action. Use 1=INSERT, 2=UPDATE, 3=DELETE.', 16, 1);
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg')   AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_products_all
IF OBJECT_ID(N'dbo.sp_products_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products_all];
GO
CREATE PROC [dbo].[sp_products_all]
AS
SET NOCOUNT ON

BEGIN

    SELECT
        [productId]
        ,[name]
        ,ISNULL([barCode],'') AS barCode
        ,ISNULL([code],'') AS code
        ,ISNULL([dateOfExpire],'') AS dateOfExpire
        ,[productFormId]
        ,[manufactureId]
        ,ISNULL([description],'') AS description
        ,[createdAt]
        ,ISNULL([updatedAt],'') AS updatedAt
        ,companyId
    FROM [montanogilberto_smartloans].[dbo].[products]
    FOR JSON AUTO, ROOT('products');

END
GO

-- dbo.sp_products_by_company
IF OBJECT_ID(N'dbo.sp_products_by_company', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products_by_company];
GO


---Si quieres crear uno nuevo
CREATE  PROC [dbo].[sp_products_by_company] 
   @pjsonfile VARCHAR(MAX)
	AS

BEGIN
SET NOCOUNT ON;
    
  /*
   DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
            "companyId": "3",
            "categoryId": "1"
        }
    ]
}'
    */
	

    DECLARE @companyId INT;
    DECLARE @categoryId INT;

    -- Extraemos companyId del JSON
    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId') 
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

        -- Extraemos companyId del JSON
    SET @categoryId = CAST(
        (SELECT JSON_VALUE(value, '$.categoryId') 
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    SELECT     
		p.productId AS [id],
		p.name,
		p.description,
		pd.saleprice as price,
		NULL AS [image],
		p.categoryId,
		(
			SELECT     
				o.productOptionId AS [productOptionId],  -- Use actual ID from DB
				o.name,
				o.type,
				(
					SELECT     
						c.productOptionChoiceId AS [productOptionChoiceId], -- Use actual ID from DB
						c.name,
						c.price
					FROM productOptionChoices c
					WHERE c.productOptionId = o.productOptionId
					FOR JSON PATH
				) AS choices
			FROM productOptions o
			WHERE o.productId = p.productId
			FOR JSON PATH
		) AS options
	FROM products p
	INNER JOIN productdetails pd ON p.productId = pd.productId
	WHERE EXISTS (
		SELECT 1 FROM productOptions o WHERE o.productId = p.productId
	)
    AND companyId = @companyId
    --AND categoryId = @categoryId
	FOR JSON PATH, ROOT('products');

END
GO

-- dbo.sp_products_categories
IF OBJECT_ID(N'dbo.sp_products_categories', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products_categories];
GO

--drop proc sp_product_by_company_products
--sp_product_by_company_categories
--sp_product_by_company_products

-- Create or replace
CREATE PROC [dbo].[sp_products_categories]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- EXAMPLES --

    

    -- 1) INSERT (one or many)
    DECLARE @pjsonfile NVARCHAR(MAX) = '{
      "productCategories": [
        { "action": 1, "name": "Detergentes", "image": "detergentes.png", "companyId": 3 },
        { "action": 1, "name": "Suavizantes", "image": "suavizantes.png", "companyId": 3 }
      ]
    }';

    */

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '{
          "result":[{ "value":"", "msg":"", "error":"" }]
        }',
        @Error NVARCHAR(500) = '',
        @action INT,
        @filterCompanyId INT = NULL,
        @filterCategoryId INT = NULL;

    -- Read action and optional filters from the first element
    SELECT TOP (1)
        @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
        @filterCompanyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        @filterCategoryId = TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.productCategories');

    BEGIN TRY

        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- INSERT (supports multiple rows)
            DECLARE @Inserted TABLE (productCategoryId INT);

            INSERT INTO [dbo].[productCategories] ([name], [image], [companyId])
            OUTPUT inserted.productCategoryId INTO @Inserted(productCategoryId)
            SELECT
                JSON_VALUE(j.value, '$.name'),
                JSON_VALUE(j.value, '$.image'),
                TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT)
            FROM OPENJSON(@pjsonfile, '$.productCategories') AS j
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 1;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', CONCAT('Inserted Successfully (', (SELECT COUNT(*) FROM @Inserted), ' row(s))'));
        END
        ELSE IF @action = 2
        BEGIN
            -- UPDATE (supports multiple rows)
            UPDATE pc
            SET
                pc.[name]  = COALESCE(JSON_VALUE(j.value, '$.name'), pc.[name]),
                pc.[image] = COALESCE(JSON_VALUE(j.value, '$.image'), pc.[image]),
                pc.[companyId] = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT), pc.[companyId])
            FROM [dbo].[productCategories] pc
            INNER JOIN OPENJSON(@pjsonfile, '$.productCategories') j
                ON pc.productCategoryId = TRY_CAST(JSON_VALUE(j.value, '$.productCategoryId') AS INT)
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 2;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- DELETE (supports multiple ids)
            DELETE pc
            FROM [dbo].[productCategories] pc
            INNER JOIN OPENJSON(@pjsonfile, '$.productCategories') j
                ON pc.productCategoryId = TRY_CAST(JSON_VALUE(j.value, '$.productCategoryId') AS INT)
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 3;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            -- Unknown action
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid or missing action (use 0=list, 1=insert, 2=update, 3=delete)');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Unified status response for non-list actions
    -- Unified status response for non-list actions
SELECT 
    (
        SELECT
            JSON_VALUE(value, '$.value') AS [value],
            JSON_VALUE(value, '$.msg')   AS [msg],
            JSON_VALUE(value, '$.error') AS [error]
        FROM OPENJSON(@Outputmessage, '$.result')
        FOR JSON PATH, ROOT('result')
    ) AS json_output;

END
GO

-- dbo.sp_products_categories_all
IF OBJECT_ID(N'dbo.sp_products_categories_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products_categories_all];
GO

 
-- Create or replace
CREATE PROC [dbo].[sp_products_categories_all]
    @pjsonfile NVARCHAR(MAX)
AS

BEGIN
    SET NOCOUNT ON;

   /*
    DECLARE @pjsonfile NVARCHAR(MAX) = '{
      "productCategories": [
        { "companyId": 1, "categoryId": null }
      ]
    }';
    */

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '{
          "result":[{ "value":"", "msg":"", "error":"" }]
        }',
        @Error NVARCHAR(500) = '',
        @action INT,
        @filterCompanyId INT = NULL,
        @filterCategoryId INT = NULL;

    -- Read action and optional filters from the first element
    SELECT TOP (1)
        @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
        @filterCompanyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        @filterCategoryId = TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.productCategories');

    
    -- LIST
    SELECT
        [productCategoryId] AS [categoryId],
        [name],
        [image],
        [companyId]
    FROM [dbo].[productCategories]
    WHERE (@filterCompanyId IS NULL OR companyId = @filterCompanyId)
        AND (@filterCategoryId IS NULL OR productCategoryId = @filterCategoryId)
    FOR JSON PATH, ROOT('productCategories');

END
GO

-- dbo.sp_products_categories_by_company_one
IF OBJECT_ID(N'dbo.sp_products_categories_by_company_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products_categories_by_company_one];
GO

CREATE PROC [dbo].[sp_products_categories_by_company_one]
    @pjsonfile NVARCHAR(MAX) = NULL  -- JSON like: { "products": [ { "companyId": "1" } ] }
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
                "product_categories": [
                    {
                        "companyId": "1"
                    }
                ]
            }'
    */

    DECLARE @companyId INT = NULL;

    -- Safely extract companyId from JSON (if present)
    IF @pjsonfile IS NOT NULL AND ISJSON(@pjsonfile) = 1
    BEGIN
        SELECT TOP (1)
               @companyId = TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.product_categories') AS j;
    END

    -- Return categories filtered by companyId when provided
    SELECT
        [productCategoryId] AS categoryId,
        [name],
        [image],
        companyId
    FROM [dbo].[productCategories]
    WHERE (@companyId IS NULL OR companyId = @companyId)
    FOR JSON PATH, ROOT('product_categories');
END
GO

-- dbo.sp_products_food
IF OBJECT_ID(N'dbo.sp_products_food', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products_food];
GO

CREATE PROC [dbo].[sp_products_food]
  @pjsonfile NVARCHAR(MAX) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @companyId INT = NULL;
  DECLARE @categoryId INT = NULL;

    /*
    @pjsonfile NVARCHAR(MAX) =  '{
    "products": [
        {
        "companyId": "1",
        "categoryId": "3"
        }
    ]
    }'
    */


  -- Extract companyId and categoryId from JSON
  IF @pjsonfile IS NOT NULL
  BEGIN
    SELECT TOP (1)
      @companyId = TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT),
      @categoryId = TRY_CAST(JSON_VALUE(j.value, '$.categoryId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.products') AS j;
  END

  SELECT
      p.productId AS [id],
      p.name,
      p.description,
      pd.saleprice AS price,
      NULL AS [image],
      p.categoryId,
      (
        SELECT
            o.productOptionId AS [id],
            o.name,
            o.type,
            (
              SELECT
                  c.productOptionChoiceId AS [id],
                  c.name,
                  c.price
              FROM dbo.productOptionChoices AS c
              WHERE c.productOptionId = o.productOptionId
              FOR JSON PATH
            ) AS choices
        FROM dbo.productOptions AS o
        WHERE o.productId = p.productId
        FOR JSON PATH
      ) AS options
  FROM dbo.products AS p
  INNER JOIN dbo.productdetails AS pd
          ON pd.productId = p.productId
  WHERE EXISTS (SELECT 1 FROM dbo.productOptions o WHERE o.productId = p.productId)
    --AND (@companyId IS NULL OR p.companyId = @companyId)
    AND (@categoryId IS NULL OR p.categoryId = @categoryId)
  FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_products_one
IF OBJECT_ID(N'dbo.sp_products_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products_one];
GO

CREATE PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
        "productId": "1"
        }
     ]   
    }'
    */

    DECLARE @productId INT;

    -- Extracting ProductId safely
    SET @productId = TRY_CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

    -- Complete JSON structure generation matching the layout used by your application
    SELECT 
        p.[productId]
        ,p.[name]
        ,ISNULL(p.[barCode],'') AS barCode
        ,ISNULL(p.[code],'') AS code
        ,ISNULL(p.[dateOfExpire],'') AS dateOfExpire
        ,p.[productFormId]
        ,p.[manufactureId]
        ,ISNULL(p.[description],'') AS description
        ,p.[categoryId]
        ,p.[companyId]
        ,p.[createdAt]
        ,ISNULL(p.[updatedAt],'') AS updatedAt
        
        -- 1. Nested Details Object (Returns as an array/object matching your save logic)
        ,(
            SELECT 
                pd.stockQuantity
                ,pd.unitPrice
                ,pd.salePrice
            FROM dbo.productDetails pd
            WHERE pd.productId = p.productId
            FOR JSON PATH
        ) AS productDetails

        -- 2. Nested Descriptions Array
        ,(
            SELECT 
                pdesc.Dosage
                ,pdesc.measurementId
                ,pdesc.is_principal
                ,pdesc.activeIngredientId
            FROM dbo.productsDescription pdesc
            WHERE pdesc.productId = p.productId
            FOR JSON PATH
        ) AS productDescriptions

        -- 3. Nested Options and nested Choices Array
        ,(
            SELECT 
                po.optionKey
                ,po.name
                ,po.type
                ,(
                    SELECT 
                        poc.choiceKey
                        ,poc.name
                        ,poc.price
                        ,poc.description
                    FROM dbo.productOptionChoices poc
                    WHERE poc.productOptionId = po.productOptionId
                    FOR JSON PATH
                ) AS optionChoices
            FROM dbo.productOptions po
            WHERE po.productId = p.productId
            FOR JSON PATH
        ) AS productOptions

    FROM 
        [dbo].[products] p
    WHERE
        p.productId = @productId
    FOR JSON PATH, ROOT('products');

END
GO

-- dbo.sp_products_save
IF OBJECT_ID(N'dbo.sp_products_save', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_products_save];
GO

CREATE PROCEDURE [dbo].[sp_products_save]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '{"result":[{ "value":"", "msg":"", "error":"" }]}',
        @Error NVARCHAR(500) = '',
        @action INT,
        @companyId INT,
        @productId INT;

    BEGIN TRY
        -- 1. Extract Root Context
        SELECT TOP (1)
            @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
            @companyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
            @productId = TRY_CAST(JSON_VALUE(value, '$.productId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.products');

        -- Validations
        IF @action IS NULL RAISERROR('action is required (1=insert, 2=update, 3=delete).', 16, 1);
        IF @companyId IS NULL RAISERROR('companyId is required.', 16, 1);
        IF @companyId <> 1 RAISERROR('Invalid companyId.', 16, 1);

        BEGIN TRANSACTION;

        /* ============================================================
           STEP 1: BASE PRODUCTS
           ============================================================ */
        IF @action = 1
        BEGIN
            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, categoryId, companyId)
            SELECT 
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), JSON_VALUE(value, '$.code'),
                JSON_VALUE(value, '$.dateOfExpire'), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT), @companyId
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR('productId is required for update.', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, '$.name'), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, '$.barCode'), p.barCode),
                p.code = COALESCE(JSON_VALUE(j.value, '$.code'), p.code),
                p.dateOfExpire = COALESCE(JSON_VALUE(j.value, '$.dateOfExpire'), p.dateOfExpire),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.productFormId') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.manufactureId') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, '$.description'), p.description),
                p.updatedAt = GETDATE(),
                p.categoryId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.categoryId') AS INT), p.categoryId)
            FROM dbo.products p
            CROSS APPLY OPENJSON(@pjsonfile, '$.products') j
            WHERE p.productId = @productId AND p.companyId = @companyId;
        END
        ELSE IF @action = 3
        BEGIN
            -- Clean up everything associated with this product (Cascade Delete)
            DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
            DELETE FROM dbo.productOptions WHERE productId = @productId;
            DELETE FROM dbo.productDetails WHERE productId = @productId;
            IF OBJECT_ID('dbo.productsDescription', 'U') IS NOT NULL DELETE FROM dbo.productsDescription WHERE productId = @productId;
            DELETE FROM dbo.products WHERE productId = @productId AND companyId = @companyId;

            COMMIT TRANSACTION;
            
            -- Early return on successful delete
            SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@productId AS NVARCHAR(50))), '$.result[0].msg', 'Deleted Successfully');
            SELECT JSON_VALUE(value, '$.value') AS [value], JSON_VALUE(value, '$.msg') AS [msg], JSON_VALUE(value, '$.error') AS [error] FROM OPENJSON(@Outputmessage, '$.result');
            RETURN;
        END

        /* ============================================================
           STEP 2: PRODUCT DETAILS (Simple IF EXISTS Check)
           ============================================================ */
        DECLARE @stock INT, @uPrice DECIMAL(10,2), @sPrice DECIMAL(10,2);
        
        SELECT 
            @stock = TRY_CAST(JSON_VALUE(value, '$.stockQuantity') AS INT),
            @uPrice = TRY_CAST(JSON_VALUE(value, '$.unitPrice') AS DECIMAL(10,2)),
            @sPrice = TRY_CAST(JSON_VALUE(value, '$.salePrice') AS DECIMAL(10,2))
        FROM OPENJSON(@pjsonfile, '$.productDetails');

        IF EXISTS (SELECT 1 FROM dbo.productDetails WHERE productId = @productId)
        BEGIN
            UPDATE dbo.productDetails
            SET stockQuantity = COALESCE(@stock, stockQuantity),
                unitPrice = COALESCE(@uPrice, unitPrice),
                salePrice = COALESCE(@sPrice, salePrice),
                updatedAt = GETDATE()
            WHERE productId = @productId;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
            VALUES (@productId, COALESCE(@stock, 0), COALESCE(@uPrice, 0), COALESCE(@sPrice, 0), GETDATE(), GETDATE());
        END

        /* ============================================================
           STEP 3: PRODUCT DESCRIPTIONS
           ============================================================ */
        IF OBJECT_ID('dbo.productsDescription', 'U') IS NOT NULL
        BEGIN
            DELETE FROM dbo.productsDescription WHERE productId = @productId;

            INSERT INTO dbo.productsDescription (productId, Dosage, measurementId, is_principal, activeIngredientId)
            SELECT 
                @productId, JSON_VALUE(value, '$.Dosage'), 
                TRY_CAST(JSON_VALUE(value, '$.measurementId') AS INT), 
                JSON_VALUE(value, '$.is_principal'), 
                TRY_CAST(JSON_VALUE(value, '$.activeIngredientId') AS INT)
            FROM OPENJSON(@pjsonfile, '$.productDescriptions');
        END

        /* ============================================================
           STEP 4: OPTIONS AND CHOICES (Simple Loop/Insert Pattern)
           ============================================================ */
        -- Clear old configurations to avoid messy updates
        DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
        DELETE FROM dbo.productOptions WHERE productId = @productId;

        -- We use a cursor or simple loop over the array index to keep identities synchronized
        DECLARE @index INT = 0, @maxOptions INT;
        SET @maxOptions = (SELECT COUNT(*) FROM OPENJSON(@pjsonfile, '$.productOptions'));

        WHILE @index < @maxOptions
        BEGIN
            DECLARE @optPath NVARCHAR(100) = '$.productOptions[' + CAST(@index AS NVARCHAR(10)) + ']';
            DECLARE @newOptId INT;

            -- Insert the Option Node
            INSERT INTO dbo.productOptions (productId, optionKey, name, type, createdAt, updatedAt)
            SELECT @productId, JSON_VALUE(@pjsonfile, @optPath + '.optionKey'), JSON_VALUE(@pjsonfile, @optPath + '.name'), JSON_VALUE(@pjsonfile, @optPath + '.type'), GETDATE(), GETDATE();
            
            SET @newOptId = SCOPE_IDENTITY();

            -- Insert Nested Choices matching this exact option index
            INSERT INTO dbo.productOptionChoices (productOptionId, choiceKey, name, price, description, createdAt, updatedAt)
            SELECT 
                @newOptId,
                JSON_VALUE(value, '$.choiceKey'),
                JSON_VALUE(value, '$.name'),
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.price') AS DECIMAL(10,2)), 0.00),
                COALESCE(JSON_VALUE(value, '$.description'), ''),
                GETDATE(),
                GETDATE()
            FROM OPENJSON(@pjsonfile, @optPath + '.optionChoices');

            SET @index = @index + 1;
        END

        COMMIT TRANSACTION;

        -- Success Output Compilation
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@productId AS NVARCHAR(50))), '$.result[0].msg', CASE WHEN @action = 1 THEN 'Inserted Successfully' ELSE 'Updated Successfully' END);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, '$.result[0].error', '1'), '$.result[0].msg', @Error);
    END CATCH;

    -- Return Status Response
    SELECT JSON_VALUE(value, '$.value') AS [value], JSON_VALUE(value, '$.msg') AS [msg], JSON_VALUE(value, '$.error') AS [error] FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_profitabilitySnapshots
IF OBJECT_ID(N'dbo.sp_profitabilitySnapshots', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_profitabilitySnapshots];
GO
CREATE PROCEDURE [dbo].[sp_profitabilitySnapshots]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action     NVARCHAR(10) = JSON_VALUE(@pjsonfile,'$.snapshots[0].action')
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile,'$.snapshots[0].companyId')
        DECLARE @periodType NVARCHAR(10) = ISNULL(JSON_VALUE(@pjsonfile,'$.snapshots[0].periodType'),'daily')
        DECLARE @snapDate   DATE         = ISNULL(JSON_VALUE(@pjsonfile,'$.snapshots[0].snapshotDate'), CAST(GETUTCDATE() AS DATE))
        DECLARE @limitRows  INT          = ISNULL(JSON_VALUE(@pjsonfile,'$.snapshots[0].limit'), 30)

        IF @action = 'upsert'
        BEGIN
            -- Aggregate from productionOrders for the period
            DECLARE @startDate DATE, @endDate DATE
            SET @endDate = @snapDate
            SET @startDate = CASE @periodType
                WHEN 'weekly'  THEN DATEADD(DAY,-6,@snapDate)
                WHEN 'monthly' THEN DATEADD(DAY,-29,@snapDate)
                ELSE @snapDate END

            SELECT
                @companyId AS companyId,
                COUNT(*)                                    AS totalOrders,
                ISNULL(SUM(ticketPrice),0)                  AS totalRevenue,
                ISNULL(SUM(realCostTotal),0)                AS totalRealCost,
                ISNULL(SUM(margin),0)                       AS totalMargin,
                ISNULL(AVG(marginPct),0)                    AS avgMarginPct,
                SUM(CASE WHEN margin < 0 THEN 1 ELSE 0 END) AS lossOrders
            INTO #snap
            FROM [dbo].[productionOrders]
            WHERE companyId=@companyId AND status='done'
              AND CAST(completedAt AS DATE) BETWEEN @startDate AND @endDate

            DECLARE @totOrd INT, @totRev DECIMAL(18,2), @totCost DECIMAL(18,2),
                    @totMrg DECIMAL(18,2), @avgMrg DECIMAL(6,2), @lossOrd INT
            SELECT @totOrd=totalOrders,@totRev=totalRevenue,@totCost=totalRealCost,
                   @totMrg=totalMargin,@avgMrg=avgMarginPct,@lossOrd=lossOrders FROM #snap
            DROP TABLE #snap

            -- Best / worst cycle type by margin
            DECLARE @best NVARCHAR(50), @worst NVARCHAR(50)
            SELECT TOP 1 @best=cycleType FROM [dbo].[productionOrders]
            WHERE companyId=@companyId AND status='done' AND CAST(completedAt AS DATE) BETWEEN @startDate AND @endDate
            GROUP BY cycleType ORDER BY AVG(marginPct) DESC

            SELECT TOP 1 @worst=cycleType FROM [dbo].[productionOrders]
            WHERE companyId=@companyId AND status='done' AND CAST(completedAt AS DATE) BETWEEN @startDate AND @endDate
            GROUP BY cycleType ORDER BY AVG(marginPct) ASC

            MERGE [dbo].[profitabilitySnapshots] AS t
            USING (SELECT @companyId AS companyId, @snapDate AS snapshotDate, @periodType AS periodType) AS s
                ON t.companyId=s.companyId AND t.snapshotDate=s.snapshotDate AND t.periodType=s.periodType
            WHEN MATCHED THEN UPDATE SET
                totalOrders=@totOrd, totalRevenue=@totRev, totalRealCost=@totCost,
                totalMargin=@totMrg, avgMarginPct=@avgMrg, lossOrders=@lossOrd,
                bestServiceType=@best, worstServiceType=@worst
            WHEN NOT MATCHED THEN INSERT
                (companyId,snapshotDate,periodType,totalOrders,totalRevenue,totalRealCost,
                 totalMargin,avgMarginPct,lossOrders,bestServiceType,worstServiceType)
            VALUES (@companyId,@snapDate,@periodType,@totOrd,@totRev,@totCost,
                    @totMrg,@avgMrg,@lossOrd,@best,@worst);

            SELECT '{"message":"snapshot saved"}' AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP (@limitRows)
                        snapshotId, snapshotDate, periodType, totalOrders,
                        totalRevenue, totalRealCost, totalMargin, avgMarginPct,
                        bestServiceType, worstServiceType, lossOrders
                 FROM [dbo].[profitabilitySnapshots]
                 WHERE companyId=@companyId AND periodType=@periodType
                 ORDER BY snapshotDate DESC
                 FOR JSON PATH, ROOT('snapshots')),
                '{"snapshots":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_projects
IF OBJECT_ID(N'dbo.sp_projects', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_projects];
GO
CREATE PROC [dbo].[sp_projects] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "projects": [
        {
            "projectId": 1,
            "projectName": "Project Alpha",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/
    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.projects'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the projects
            INSERT INTO [dbo].[projects] 
                ([projectName], [createdAt])
            SELECT
                JSON_VALUE(value, '$.projectName'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.projects');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the projects
            UPDATE p
            SET 
                p.[projectName] = JSON_VALUE(j.value, '$.projectName')
            FROM 
                [dbo].[projects] p
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.projects') j
                ON p.[projectId] = JSON_VALUE(j.value, '$.projectId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the projects
            DELETE FROM [dbo].[projects]
            WHERE [projectId] IN (SELECT JSON_VALUE(value, '$.projectId') FROM OPENJSON(@pjsonfile, '$.projects'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_projects_all
IF OBJECT_ID(N'dbo.sp_projects_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_projects_all];
GO

CREATE PROC [dbo].[sp_projects_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [projectId],
        [projectName],
        [createdAt]
    FROM [montanogilberto_smartloans].[dbo].[projects]
    FOR JSON AUTO, ROOT('projects');
END
GO

-- dbo.sp_projects_one
IF OBJECT_ID(N'dbo.sp_projects_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_projects_one];
GO
CREATE PROC [dbo].[sp_projects_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "projects": [
        {
        "projectId": "1"
        }
     ]   
    }'
    */

    DECLARE @projectId INT;

    SET @projectId = CAST((SELECT JSON_VALUE(value, '$.projectId') FROM OPENJSON(@pjsonfile, '$.projects')) AS INT);

    SELECT 
        [projectId]
        ,[projectName]
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[projects]
    WHERE
        projectId = @projectId
    FOR JSON AUTO, ROOT('projects');

END
GO

-- dbo.sp_publishJobs
IF OBJECT_ID(N'dbo.sp_publishJobs', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_publishJobs];
GO

CREATE PROC [dbo].[sp_publishJobs] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

/*
  DECLARE @pjsonfile VARCHAR(MAX) = '{
  "publishJobs": [
    {
      "draftId": 1,
      "status": "queued",
      "attempts": 0,
      "nextRetryAt": null,
      "lastError": null,
      "action": "1"
    }
  ]
}';
*/

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value,'$.action')) FROM OPENJSON(@pjsonfile,'$.publishJobs'));

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.publishJobs (draftId, status, attempts, nextRetryAt, lastError)
      SELECT
        TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.draftId')),
        ISNULL(NULLIF(JSON_VALUE(value,'$.status'),''),'queued'),
        ISNULL(TRY_CONVERT(INT, JSON_VALUE(value,'$.attempts')), 0),
        TRY_CONVERT(DATETIME2, JSON_VALUE(value,'$.nextRetryAt')),
        JSON_VALUE(value,'$.lastError')
      FROM OPENJSON(@pjsonfile,'$.publishJobs');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE pj
      SET
        pj.draftId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.draftId')),
        pj.status  = ISNULL(NULLIF(JSON_VALUE(j.value,'$.status'),''), pj.status),
        pj.attempts = COALESCE(TRY_CONVERT(INT, JSON_VALUE(j.value,'$.attempts')), pj.attempts),
        pj.nextRetryAt = TRY_CONVERT(DATETIME2, JSON_VALUE(j.value,'$.nextRetryAt')),
        pj.lastError = JSON_VALUE(j.value,'$.lastError'),
        pj.updatedAt = SYSUTCDATETIME()
      FROM dbo.publishJobs pj
      INNER JOIN OPENJSON(@pjsonfile,'$.publishJobs') j
        ON pj.jobId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.jobId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.publishJobs
      WHERE jobId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.jobId'))
        FROM OPENJSON(@pjsonfile,'$.publishJobs')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);
  END CATCH

  SELECT
    JSON_VALUE(value,'$.value') AS [value],
    JSON_VALUE(value,'$.msg') AS [msg],
    JSON_VALUE(value,'$.error') AS [error]
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_publishJobs_next
IF OBJECT_ID(N'dbo.sp_publishJobs_next', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_publishJobs_next];
GO

CREATE   PROC dbo.sp_publishJobs_next
  @batchSize INT = 10
AS
BEGIN
  SET NOCOUNT ON;

  ;WITH cte AS (
    SELECT TOP (@batchSize)
      pj.jobId, pj.draftId, pj.attempts
    FROM dbo.publishJobs pj WITH (READPAST, UPDLOCK, ROWLOCK)
    WHERE pj.status IN ('queued','failed')
      AND (pj.nextRetryAt IS NULL OR pj.nextRetryAt <= SYSUTCDATETIME())
    ORDER BY pj.updatedAt ASC, pj.jobId ASC
  )
  UPDATE pj
    SET pj.status = 'processing',
        pj.attempts = ISNULL(pj.attempts,0) + 1,
        pj.nextRetryAt = NULL,
        pj.lastError = NULL,
        pj.updatedAt = SYSUTCDATETIME()
  OUTPUT
    inserted.jobId,
    inserted.draftId,
    d.channel,
    d.market,
    d.payloadJson,
    inserted.attempts
  FROM dbo.publishJobs pj
  JOIN cte ON cte.jobId = pj.jobId
  JOIN dbo.listingDrafts d ON d.draftId = pj.draftId;
END
GO

-- dbo.sp_pushNotifications
IF OBJECT_ID(N'dbo.sp_pushNotifications', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pushNotifications];
GO
CREATE PROCEDURE dbo.sp_pushNotifications
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Outputmessage VARCHAR(MAX);
    DECLARE @companyId INT;

    -- Create a temporary table to hold the parsed JSON data
    DECLARE @payload TABLE (
        action INT,
        pushNotificationId INT,
        companyId INT,
        title NVARCHAR(200),
        message NVARCHAR(1000),
        notificationType NVARCHAR(50),
        priority NVARCHAR(20),
        targetType NVARCHAR(50),
        targetUserId INT,
        targetRoleId INT,
        targetCompanyId INT,
        navigationRoute NVARCHAR(250),
        isRead BIT,
        isSent BIT,
        sentAt DATETIME,
        scheduledAt DATETIME,
        payloadJson NVARCHAR(MAX)
    );

    -- Insert data from JSON into the temporary table
    INSERT INTO @payload (
        action,
        pushNotificationId,
        companyId,
        title,
        message,
        notificationType,
        priority,
        targetType,
        targetUserId,
        targetRoleId,
        targetCompanyId,
        navigationRoute,
        isRead,
        isSent,
        sentAt,
        scheduledAt,
        payloadJson
    )
    SELECT
        TRY_CONVERT(INT, JSON_VALUE(value, '$.action')),
        JSON_VALUE(value, '$.pushNotificationId'),
        JSON_VALUE(value, '$.companyId'),
        JSON_VALUE(value, '$.title'),
        JSON_VALUE(value, '$.message'),
        JSON_VALUE(value, '$.notificationType'),
        JSON_VALUE(value, '$.priority'),
        JSON_VALUE(value, '$.targetType'),
        JSON_VALUE(value, '$.targetUserId'),
        JSON_VALUE(value, '$.targetRoleId'),
        JSON_VALUE(value, '$.targetCompanyId'),
        JSON_VALUE(value, '$.navigationRoute'),
        JSON_VALUE(value, '$.isRead'),
        JSON_VALUE(value, '$.isSent'),
        JSON_VALUE(value, '$.sentAt'),
        JSON_VALUE(value, '$.scheduledAt'),
        JSON_VALUE(value, '$.payloadJson')
    FROM OPENJSON(@pjsonfile, '$.pushNotifications');

    SELECT @companyId = companyId FROM @payload;

    -- Validate companyId for all operations
    IF NOT EXISTS (SELECT 1 FROM dbo.companies WHERE companyId = @companyId)
    BEGIN
        SET @Outputmessage = JSON_MODIFY('{}', '$.status', 'error');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.message', 'Invalid companyId provided.');
        SELECT @Outputmessage AS Outputmessage;
        GOTO Finish;
    END;

    -- Action 1: INSERT
    IF EXISTS (SELECT 1 FROM @payload WHERE action = 1)
    BEGIN
        INSERT INTO dbo.PushNotifications (
            companyId,
            title,
            message,
            notificationType,
            priority,
            targetType,
            targetUserId,
            targetRoleId,
            targetCompanyId,
            navigationRoute,
            isRead,
            isSent,
            sentAt,
            scheduledAt,
            payloadJson,
            created_At
        )
        SELECT
            p.companyId,
            p.title,
            p.message,
            p.notificationType,
            p.priority,
            p.targetType,
            p.targetUserId,
            p.targetRoleId,
            p.targetCompanyId,
            p.navigationRoute,
            ISNULL(p.isRead, 0), -- Default to 0 if not provided
            ISNULL(p.isSent, 0), -- Default to 0 if not provided
            p.sentAt,
            p.scheduledAt,
            p.payloadJson,
            GETDATE()
        FROM @payload p
        WHERE p.action = 1;

        SET @Outputmessage = JSON_MODIFY('{}', '$.status', 'success');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.message', 'PushNotification(s) inserted successfully.');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.pushNotificationId', CAST(SCOPE_IDENTITY() AS VARCHAR(20)));
    END;

    -- Action 2: UPDATE
    IF EXISTS (SELECT 1 FROM @payload WHERE action = 2)
    BEGIN
        UPDATE pn
        SET
            pn.title = p.title,
            pn.message = p.message,
            pn.notificationType = p.notificationType,
            pn.priority = p.priority,
            pn.targetType = p.targetType,
            pn.targetUserId = p.targetUserId,
            pn.targetRoleId = p.targetRoleId,
            pn.targetCompanyId = p.targetCompanyId,
            pn.navigationRoute = p.navigationRoute,
            pn.isRead = p.isRead,
            pn.isSent = p.isSent,
            pn.sentAt = p.sentAt,
            pn.scheduledAt = p.scheduledAt,
            pn.payloadJson = p.payloadJson,
            pn.updated_at = GETDATE()
        FROM dbo.PushNotifications pn
        INNER JOIN @payload p ON pn.pushNotificationId = p.pushNotificationId
        WHERE p.action = 2 AND pn.companyId = p.companyId;

        SET @Outputmessage = JSON_MODIFY('{}', '$.status', 'success');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.message', 'PushNotification(s) updated successfully.');
    END;

    -- Action 3: DELETE
    IF EXISTS (SELECT 1 FROM @payload WHERE action = 3)
    BEGIN
        DELETE pn
        FROM dbo.PushNotifications pn
        INNER JOIN @payload p ON pn.pushNotificationId = p.pushNotificationId
        WHERE p.action = 3 AND pn.companyId = p.companyId;

        SET @Outputmessage = JSON_MODIFY('{}', '$.status', 'success');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.message', 'PushNotification(s) deleted successfully.');
    END;

    SELECT @Outputmessage AS Outputmessage;

    Finish:
END;
GO

-- dbo.sp_pushNotifications_activeUsers
IF OBJECT_ID(N'dbo.sp_pushNotifications_activeUsers', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pushNotifications_activeUsers];
GO
CREATE PROCEDURE dbo.sp_pushNotifications_activeUsers
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    -- @pjsonfile is a flat object (e.g. {"companyId": 5} or {"companyId": null}),
    -- not an array, so JSON_VALUE reads straight off @pjsonfile -- OPENJSON
    -- without an array path returns one row per key with a scalar `value`,
    -- which JSON_VALUE(value, '$.key') can't re-parse.
    DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.companyId');

    -- @companyId NULL -> every active user (targetType 'All').
    -- @companyId set  -> active users in that company (targetType 'Company').
    SELECT userId
    FROM dbo.users
    WHERE active = '1'
      AND (@companyId IS NULL OR companyId = @companyId)
    FOR JSON AUTO, ROOT('users');
END;
GO

-- dbo.sp_pushNotifications_all
IF OBJECT_ID(N'dbo.sp_pushNotifications_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pushNotifications_all];
GO
CREATE PROCEDURE dbo.sp_pushNotifications_all
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT;

    SELECT @companyId = JSON_VALUE(value, '$.companyId')
    FROM OPENJSON(@pjsonfile, '$.pushNotifications');

    SELECT
        pushNotificationId,
        companyId,
        title,
        message,
        notificationType,
        priority,
        targetType,
        targetUserId,
        targetRoleId,
        targetCompanyId,
        navigationRoute,
        isRead,
        isSent,
        ISNULL(CONVERT(VARCHAR(30), sentAt, 126), '') AS sentAt,
        ISNULL(CONVERT(VARCHAR(30), scheduledAt, 126), '') AS scheduledAt,
        payloadJson,
        CONVERT(VARCHAR(30), created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.PushNotifications
    WHERE companyId = @companyId
    FOR JSON AUTO, ROOT('pushNotifications');
END;
GO

-- dbo.sp_pushNotifications_forUser
IF OBJECT_ID(N'dbo.sp_pushNotifications_forUser', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pushNotifications_forUser];
GO
CREATE PROCEDURE [dbo].[sp_pushNotifications_forUser]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @userId INT = JSON_VALUE(@pjsonfile, '$.userId')

    -- Materializa (lazy) las entregas de broadcasts 'Company': el envío masivo
    -- no crea filas por usuario (102 filas por oferta ahogarían la DB de 20MB),
    -- así que se crean aquí, solo cuando el usuario abre su bandeja.
    -- companyId por clients (fuente de verdad), NO users: cuentas legacy
    -- siguen con users.companyId=1 (Lavanderia) mientras el cliente vive en
    -- 1008 (SmartLoans) — el bug conocido 1 vs 1008.
    DECLARE @companyId INT = (
        SELECT TOP 1 ISNULL(c.companyId, u.companyId)
        FROM users u
        LEFT JOIN clients c ON c.clientId = u.clientId
        WHERE u.userId = @userId);
    INSERT INTO NotificationDeliveries (pushNotificationId, userId, isSent, isRead, sentAt, created_At)
    SELECT p.pushNotificationId, @userId, 1, 0, p.created_At, p.created_At
    FROM PushNotifications p
    WHERE p.targetType = 'Company'
      AND p.targetCompanyId = @companyId
      -- Solo broadcasts posteriores al registro del usuario: una cuenta nueva
      -- no debe recibir anuncios históricos (p.ej. ofertas de capital que ya
      -- se prestó antes de que existiera).
      AND p.created_At >= ISNULL((SELECT created_at FROM users WHERE userId = @userId), '1900-01-01')
      AND NOT EXISTS (SELECT 1 FROM NotificationDeliveries d
                      WHERE d.pushNotificationId = p.pushNotificationId
                        AND d.userId = @userId);

    SELECT (SELECT
        (SELECT COUNT(*) FROM NotificationDeliveries
         WHERE userId = @userId AND ISNULL(isRead, 0) = 0) AS unreadCount,
        JSON_QUERY(ISNULL((
            SELECT TOP 50
                d.notificationDeliveryId, d.pushNotificationId,
                ISNULL(d.isRead, 0) AS isRead,
                CONVERT(NVARCHAR(19), d.created_At, 120) AS receivedAt,
                p.title, p.message, p.notificationType, p.priority,
                p.navigationRoute
            FROM NotificationDeliveries d
            INNER JOIN PushNotifications p ON p.pushNotificationId = d.pushNotificationId
            WHERE d.userId = @userId
            ORDER BY d.notificationDeliveryId DESC
            FOR JSON PATH), '[]')) AS notifications
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
END
GO

-- dbo.sp_pushNotifications_markRead
IF OBJECT_ID(N'dbo.sp_pushNotifications_markRead', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pushNotifications_markRead];
GO
CREATE PROCEDURE [dbo].[sp_pushNotifications_markRead]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @userId INT = JSON_VALUE(@pjsonfile, '$.userId')
    -- NULL = marcar todas las del usuario
    DECLARE @pushNotificationId INT = JSON_VALUE(@pjsonfile, '$.pushNotificationId')

    UPDATE NotificationDeliveries
    SET isRead = 1, readAt = GETUTCDATE()
    WHERE userId = @userId AND ISNULL(isRead, 0) = 0
      AND (@pushNotificationId IS NULL OR pushNotificationId = @pushNotificationId)

    SELECT ('{"marked":' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + '}') AS [jsonResult]
END
GO

-- dbo.sp_pushNotifications_one
IF OBJECT_ID(N'dbo.sp_pushNotifications_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pushNotifications_one];
GO
CREATE PROCEDURE dbo.sp_pushNotifications_one
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pushNotificationId INT;
    DECLARE @companyId INT;

    SELECT
        @pushNotificationId = JSON_VALUE(value, '$.pushNotificationId'),
        @companyId = JSON_VALUE(value, '$.companyId')
    FROM OPENJSON(@pjsonfile);

    SELECT
        pushNotificationId,
        companyId,
        title,
        message,
        notificationType,
        priority,
        targetType,
        targetUserId,
        targetRoleId,
        targetCompanyId,
        navigationRoute,
        isRead,
        isSent,
        ISNULL(CONVERT(VARCHAR(30), sentAt, 126), '') AS sentAt,
        ISNULL(CONVERT(VARCHAR(30), scheduledAt, 126), '') AS scheduledAt,
        payloadJson,
        CONVERT(VARCHAR(30), created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.PushNotifications
    WHERE pushNotificationId = @pushNotificationId AND companyId = @companyId
    FOR JSON AUTO, ROOT('pushNotifications');
END;
GO

-- dbo.sp_pushNotifications_recordDelivery
IF OBJECT_ID(N'dbo.sp_pushNotifications_recordDelivery', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pushNotifications_recordDelivery];
GO

CREATE PROCEDURE dbo.sp_pushNotifications_recordDelivery
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @pushNotificationId INT = JSON_VALUE(@pjsonfile, N'$.pushNotificationId');
    DECLARE @userId INT = JSON_VALUE(@pjsonfile, N'$.userId');
    DECLARE @isSent BIT = JSON_VALUE(@pjsonfile, N'$.isSent');

    INSERT INTO dbo.NotificationDeliveries (pushNotificationId, userId, isSent, isRead, sentAt)
    VALUES (
        @pushNotificationId,
        @userId,
        @isSent,
        0,
        CASE WHEN @isSent = 1 THEN GETDATE() ELSE NULL END
    );
END;
GO

-- dbo.sp_registrationReminders
IF OBJECT_ID(N'dbo.sp_registrationReminders', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_registrationReminders];
GO

CREATE PROCEDURE [dbo].[sp_registrationReminders]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action       NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.registrationReminders[0].action')
        DECLARE @userId       INT           = JSON_VALUE(@pjsonfile, '$.registrationReminders[0].userId')
        DECLARE @missingSteps NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.registrationReminders[0].missingSteps')

        -- Every user with an incomplete registration who hasn't already
        -- been reminded (LEFT JOIN ... IS NULL). Caller decides the
        -- missing-steps text and how/whether to notify.
        IF @action = 'getIncomplete'
        BEGIN
            SELECT ISNULL(
                (SELECT u.userId,
                        u.email,
                        u.cellphone,
                        CASE WHEN u.appProfile IS NULL THEN 0 ELSE 1 END AS hasProfile,
                        CASE WHEN u.identityVerified = 1 THEN 1 ELSE 0 END AS isVerified,
                        CASE WHEN uc.userId IS NULL THEN 0 ELSE 1 END AS hasAccess,
                        uc.companyId AS companyId
                 FROM [dbo].[users] u
                 OUTER APPLY (SELECT TOP 1 userId, companyId FROM [dbo].[userCompanies] WHERE userId = u.userId) uc
                 LEFT JOIN [dbo].[registrationReminders] r ON r.userId = u.userId
                 WHERE r.reminderId IS NULL
                   AND (u.appProfile IS NULL OR u.identityVerified = 0 OR uc.userId IS NULL)
                 FOR JSON PATH, ROOT('users')),
                '{"users":[]}'
            ) AS [jsonResult]
        END

        -- Idempotent: UNIQUE(userId) means a user can only ever be marked
        -- once — remind once, then stop (staff can still nudge manually).
        ELSE IF @action = 'markReminded'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[registrationReminders] WHERE userId = @userId)
            BEGIN
                INSERT INTO [dbo].[registrationReminders] (userId, missingSteps)
                VALUES (@userId, @missingSteps)
            END

            SELECT '{"message":"marked"}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_renamediagram
IF OBJECT_ID(N'dbo.sp_renamediagram', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_renamediagram];
GO

	CREATE PROCEDURE dbo.sp_renamediagram
	(
		@diagramname 		sysname,
		@owner_id		int	= null,
		@new_diagramname	sysname
	
	)
	WITH EXECUTE AS 'dbo'
	AS
	BEGIN
		set nocount on
		declare @theId 			int
		declare @IsDbo 			int
		
		declare @UIDFound 		int
		declare @DiagId			int
		declare @DiagIdTarg		int
		declare @u_name			sysname
		if((@diagramname is null) or (@new_diagramname is null))
		begin
			RAISERROR ('Invalid value', 16, 1);
			return -1
		end
	
		EXECUTE AS CALLER;
		select @theId = DATABASE_PRINCIPAL_ID();
		select @IsDbo = IS_MEMBER(N'db_owner'); 
		if(@owner_id is null)
			select @owner_id = @theId;
		REVERT;
	
		select @u_name = USER_NAME(@owner_id)
	
		select @DiagId = diagram_id, @UIDFound = principal_id from dbo.sysdiagrams where principal_id = @owner_id and name = @diagramname 
		if(@DiagId IS NULL or (@IsDbo = 0 and @UIDFound <> @theId))
		begin
			RAISERROR ('Diagram does not exist or you do not have permission.', 16, 1)
			return -3
		end
	
		-- if((@u_name is not null) and (@new_diagramname = @diagramname))	-- nothing will change
		--	return 0;
	
		if(@u_name is null)
			select @DiagIdTarg = diagram_id from dbo.sysdiagrams where principal_id = @theId and name = @new_diagramname
		else
			select @DiagIdTarg = diagram_id from dbo.sysdiagrams where principal_id = @owner_id and name = @new_diagramname
	
		if((@DiagIdTarg is not null) and  @DiagId <> @DiagIdTarg)
		begin
			RAISERROR ('The name is already used.', 16, 1);
			return -2
		end		
	
		if(@u_name is null)
			update dbo.sysdiagrams set [name] = @new_diagramname, principal_id = @theId where diagram_id = @DiagId
		else
			update dbo.sysdiagrams set [name] = @new_diagramname where diagram_id = @DiagId
		return 0
	END
GO

-- dbo.sp_rewards
IF OBJECT_ID(N'dbo.sp_rewards', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_rewards];
GO

CREATE PROCEDURE [dbo].[sp_rewards]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        DECLARE @action      NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.rewards[0].action')
        DECLARE @companyId   INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].companyId')
        DECLARE @clientId    INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].clientId')
        DECLARE @ruleId      INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].ruleId')
        DECLARE @createdBy   INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].createdBy')

        -- ── upsert_rule ──────────────────────────────────────
        IF @action = 'upsert_rule'
        BEGIN
            DECLARE @ruleName       NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.rewards[0].ruleName')
            DECLARE @ruleType       NVARCHAR(40)  = ISNULL(JSON_VALUE(@pjsonfile, '$.rewards[0].ruleType'), 'purchase')
            DECLARE @pointsPerUnit  DECIMAL(10,4) = ISNULL(JSON_VALUE(@pjsonfile, '$.rewards[0].pointsPerUnit'), 1)
            DECLARE @minAmount      DECIMAL(10,2) = JSON_VALUE(@pjsonfile, '$.rewards[0].minAmount')
            DECLARE @maxPointsTx    INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].maxPointsPerTx')
            DECLARE @isActive       BIT           = ISNULL(JSON_VALUE(@pjsonfile, '$.rewards[0].isActive'), 1)

            IF @ruleId IS NOT NULL AND EXISTS (SELECT 1 FROM rewardRules WHERE ruleId = @ruleId AND companyId = @companyId)
            BEGIN
                UPDATE rewardRules SET
                    ruleName       = @ruleName,
                    ruleType       = @ruleType,
                    pointsPerUnit  = @pointsPerUnit,
                    minAmount      = @minAmount,
                    maxPointsPerTx = @maxPointsTx,
                    isActive       = @isActive,
                    updated_at     = GETUTCDATE()
                WHERE ruleId = @ruleId AND companyId = @companyId

                SELECT (SELECT ruleId, companyId, ruleName, ruleType, pointsPerUnit,
                    minAmount, maxPointsPerTx, isActive, created_At, updated_at
                    FROM rewardRules WHERE ruleId = @ruleId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
            END
            ELSE
            BEGIN
                INSERT INTO rewardRules (companyId, ruleName, ruleType, pointsPerUnit, minAmount, maxPointsPerTx, isActive)
                VALUES (@companyId, @ruleName, @ruleType, @pointsPerUnit, @minAmount, @maxPointsTx, @isActive)

                DECLARE @newRuleId INT = SCOPE_IDENTITY()
                SELECT (SELECT ruleId, companyId, ruleName, ruleType, pointsPerUnit,
                    minAmount, maxPointsPerTx, isActive, created_At
                    FROM rewardRules WHERE ruleId = @newRuleId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
            END
        END

        -- ── delete_rule ──────────────────────────────────────
        ELSE IF @action = 'delete_rule'
        BEGIN
            UPDATE rewardRules SET isActive = 0, updated_at = GETUTCDATE()
            WHERE ruleId = @ruleId AND companyId = @companyId
            SELECT '{"deleted":true}' AS [jsonResult]
        END

        -- ── list_rules ───────────────────────────────────────
        ELSE IF @action = 'list_rules'
        BEGIN
            SELECT ISNULL(
                (SELECT ruleId, companyId, ruleName, ruleType, pointsPerUnit,
                    minAmount, maxPointsPerTx, isActive, created_At, updated_at
                    FROM rewardRules
                    WHERE companyId = @companyId AND isActive = 1
                    ORDER BY ruleId
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END

        -- ── earn ─────────────────────────────────────────────
        ELSE IF @action = 'earn'
        BEGIN
            DECLARE @earnPoints     INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].points')
            DECLARE @referenceId    NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.rewards[0].referenceId')
            DECLARE @description    NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.rewards[0].description')

            -- Ensure wallet row exists
            IF NOT EXISTS (SELECT 1 FROM rewardPoints WHERE companyId = @companyId AND clientId = @clientId)
                INSERT INTO rewardPoints (companyId, clientId, balance, lifetimeEarned, lifetimeRedeemed)
                VALUES (@companyId, @clientId, 0, 0, 0)

            UPDATE rewardPoints SET
                balance         = balance + @earnPoints,
                lifetimeEarned  = lifetimeEarned + @earnPoints,
                lastActivity    = GETUTCDATE(),
                updated_at      = GETUTCDATE()
            WHERE companyId = @companyId AND clientId = @clientId

            DECLARE @balanceAfterEarn INT
            SELECT @balanceAfterEarn = balance FROM rewardPoints WHERE companyId = @companyId AND clientId = @clientId

            INSERT INTO rewardTransactions (companyId, clientId, ruleId, txType, points, balanceAfter, referenceId, description, createdBy)
            VALUES (@companyId, @clientId, @ruleId, 'earn', @earnPoints, @balanceAfterEarn, @referenceId, @description, @createdBy)

            SELECT (SELECT @balanceAfterEarn AS balance, @earnPoints AS pointsEarned,
                SCOPE_IDENTITY() AS txId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        -- ── redeem ────────────────────────────────────────────
        ELSE IF @action = 'redeem'
        BEGIN
            DECLARE @redeemPoints   INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].points')
            DECLARE @refIdRedeem    NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.rewards[0].referenceId')
            DECLARE @descRedeem     NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.rewards[0].description')

            DECLARE @currentBalance INT
            SELECT @currentBalance = ISNULL(balance, 0)
            FROM rewardPoints WHERE companyId = @companyId AND clientId = @clientId

            IF @currentBalance < @redeemPoints
            BEGIN
                SELECT '{"error":"insufficient_points","balance":' + CAST(@currentBalance AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            UPDATE rewardPoints SET
                balance           = balance - @redeemPoints,
                lifetimeRedeemed  = lifetimeRedeemed + @redeemPoints,
                lastActivity      = GETUTCDATE(),
                updated_at        = GETUTCDATE()
            WHERE companyId = @companyId AND clientId = @clientId

            DECLARE @balanceAfterRedeem INT
            SELECT @balanceAfterRedeem = balance FROM rewardPoints WHERE companyId = @companyId AND clientId = @clientId

            INSERT INTO rewardTransactions (companyId, clientId, ruleId, txType, points, balanceAfter, referenceId, description, createdBy)
            VALUES (@companyId, @clientId, NULL, 'redeem', -@redeemPoints, @balanceAfterRedeem, @refIdRedeem, @descRedeem, @createdBy)

            SELECT (SELECT @balanceAfterRedeem AS balance, @redeemPoints AS pointsRedeemed,
                SCOPE_IDENTITY() AS txId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        -- ── get_balance ───────────────────────────────────────
        ELSE IF @action = 'get_balance'
        BEGIN
            SELECT ISNULL(
                (SELECT balance, lifetimeEarned, lifetimeRedeemed, lastActivity, clientId, companyId
                    FROM rewardPoints
                    WHERE companyId = @companyId AND clientId = @clientId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{"balance":0,"lifetimeEarned":0,"lifetimeRedeemed":0}'
            ) AS [jsonResult]
        END

        -- ── list_transactions ─────────────────────────────────
        ELSE IF @action = 'list_transactions'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 50 txId, companyId, clientId, ruleId, txType, points, balanceAfter,
                    referenceId, description, createdBy, created_At
                    FROM rewardTransactions
                    WHERE companyId = @companyId
                      AND (@clientId IS NULL OR clientId = @clientId)
                    ORDER BY txId DESC
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END

        -- ── list_balances (all clients in company) ────────────
        ELSE IF @action = 'list_balances'
        BEGIN
            SELECT ISNULL(
                (SELECT rp.clientId, rp.balance, rp.lifetimeEarned, rp.lifetimeRedeemed, rp.lastActivity
                    FROM rewardPoints rp
                    WHERE rp.companyId = @companyId
                    ORDER BY rp.balance DESC
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_savedPaymentMethods
IF OBJECT_ID(N'dbo.sp_savedPaymentMethods', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_savedPaymentMethods];
GO

CREATE PROCEDURE [dbo].[sp_savedPaymentMethods]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    NVARCHAR(10)   = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].action')
        DECLARE @clientId  INT            = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].clientId')
        DECLARE @companyId INT            = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].companyId')
        DECLARE @pmId      NVARCHAR(100)  = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].stripePaymentMethodId')
        DECLARE @last4     NVARCHAR(4)    = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].last4')
        DECLARE @brand     NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].brand')
        DECLARE @expMonth  INT            = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].expiryMonth')
        DECLARE @expYear   INT            = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].expiryYear')

        IF @action = 'upsert'
        BEGIN
            MERGE [dbo].[savedPaymentMethods] AS target
            USING (SELECT @clientId AS clientId, @companyId AS companyId) AS src
                ON target.clientId = src.clientId AND target.companyId = src.companyId
            WHEN MATCHED THEN
                UPDATE SET stripePaymentMethodId=@pmId, last4=@last4, brand=@brand,
                           expiryMonth=@expMonth, expiryYear=@expYear, updatedAt=GETUTCDATE()
            WHEN NOT MATCHED THEN
                INSERT (clientId, companyId, stripePaymentMethodId, last4, brand, expiryMonth, expiryYear)
                VALUES (@clientId, @companyId, @pmId, @last4, @brand, @expMonth, @expYear);

            SELECT (SELECT TOP 1 stripePaymentMethodId, last4, brand, expiryMonth, expiryYear
                    FROM [dbo].[savedPaymentMethods]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 stripePaymentMethodId, last4, brand, expiryMonth, expiryYear
                 FROM [dbo].[savedPaymentMethods]
                 WHERE clientId=@clientId AND companyId=@companyId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                'null'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_select_all_tables
IF OBJECT_ID(N'dbo.sp_select_all_tables', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_select_all_tables];
GO

CREATE PROC [dbo].[sp_select_all_tables](@table_name VARCHAR(50))
AS
SET NOCOUNT ON
BEGIN

    --DECLARE @table_name VARCHAR(50) = 'users'
    DECLARE @sql NVARCHAR(MAX)

    -- Construct the dynamic SQL statement
    SET @sql = N'
       SELECT * FROM [dbo].' + QUOTENAME(@table_name) + '
       FOR JSON PATH, ROOT(''' + @table_name + ''')'

    -- Execute the dynamic SQL statement
    EXEC sp_executesql @sql
END
GO

-- dbo.sp_select_one_row
IF OBJECT_ID(N'dbo.sp_select_one_row', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_select_one_row];
GO
create PROC [dbo].[sp_select_one_row](@pjsonfile VARCHAR(MAX))

AS

SET NOCOUNT ON

 

/*

DECLARE @pjsonfile VARCHAR(MAX) = '{

  "utils": [

    {

      "table_name": "users",

      "valueId": "1",

    }

  ]

}'

*/

 

BEGIN

 

       DECLARE @Outputmessage VARCHAR(MAX) = '

              {

                "result": [

                      {

                        "value": "",

                        "msg": ""

                      }

                ]

              }'

 

       DECLARE

       @table_name VARCHAR(50),

       @valueId VARCHAR(50)

 

       --DECLARE @table_name VARCHAR(50) = 'users'

       DECLARE

              @sql NVARCHAR(MAX),

              @field VARCHAR(100)

 

       SELECT

              @table_name = JSON_VALUE(value, '$.table_name'),

              @valueId = JSON_VALUE(value, '$.valueId')

       FROM OPENJSON(@pjsonfile, '$.utils')

 

       SELECT

              @field = c.[name]

       FROM

              sys.tables t

              INNER JOIN sys.columns c ON c.object_id = t.object_id

       WHERE

              t.name = @table_name

              AND is_identity = 1

 

       IF @field IS NOT NULL

       BEGIN

              -- Construct the dynamic SQL statement

              SET @sql = N'

                      SELECT * FROM [dbo].' + QUOTENAME(@table_name) + '

                      WHERE ' + QUOTENAME(@field) + ' = @valueId

                      FOR JSON PATH, ROOT(''' + @table_name + ''')'

 

              -- Execute the dynamic SQL statement with parameters

              EXEC sp_executesql @sql, N'@valueId NVARCHAR(50)', @valueId = @valueId

       END

       ELSE

       BEGIN

              PRINT 'No identity column found'

              SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].result', '-1')

              SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No identity column found')

 

              SELECT

                      JSON_VALUE(value, '$.value') AS [value],

                      JSON_VALUE(value, '$.msg') AS [msg]

              FROM OPENJSON(@Outputmessage, '$.result')

       END

 

END
GO

-- dbo.sp_sellListings
IF OBJECT_ID(N'dbo.sp_sellListings', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_sellListings];
GO

CREATE PROC [dbo].[sp_sellListings]
(
    @pjsonfile NVARCHAR(MAX)
)
AS
BEGIN

    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @Outputmessage NVARCHAR(MAX) =
        N'{ "result": [ { "value": "", "msg": "", "error": "" } ] }',

        @Error NVARCHAR(4000) = N'',
        @action INT;

    ---------------------------------------------------------------------
    -- Detect action
    ---------------------------------------------------------------------
    SELECT TOP 1
        @action = TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
    FROM OPENJSON(@pjsonfile, '$.sellListings');

    IF @action IS NULL SET @action = 1;

    BEGIN TRY

        BEGIN TRANSACTION;

        ---------------------------------------------------------------------
        -- ACTION 1: UPSERT
        ---------------------------------------------------------------------
        IF @action = 1
        BEGIN

            -----------------------------------------------------------------
            -- VALIDATION
            -----------------------------------------------------------------
            IF EXISTS (
                SELECT 1
                FROM OPENJSON(@pjsonfile, '$.sellListings') j
                WHERE
                    NULLIF(JSON_VALUE(j.value, '$.channelItemId'), '') IS NULL
                    OR TRY_CONVERT(DECIMAL(18,6),
                        JSON_VALUE(j.value, '$.sellPriceOriginal')) IS NULL
                    OR NULLIF(JSON_VALUE(j.value, '$.currencyOriginal'), '') IS NULL
                    OR TRY_CONVERT(DECIMAL(18,8),
                        JSON_VALUE(j.value, '$.fxRateToUsd')) IS NULL
                    OR TRY_CONVERT(DATE,
                        JSON_VALUE(j.value, '$.fxAsOfDate')) IS NULL
            )
            BEGIN
                RAISERROR('Invalid payload.',16,1);
            END


            -----------------------------------------------------------------
            -- Capture merge output
            -----------------------------------------------------------------
            DECLARE @merge_attr TABLE
            (
                sellListingId BIGINT,
                attributesJson NVARCHAR(MAX),
                attributesHash VARBINARY(32)
            );


            -----------------------------------------------------------------
            -- SOURCE PARSE
            -----------------------------------------------------------------
            ;WITH src AS
            (

                SELECT

                    channel =
                        LOWER(
                            ISNULL(
                                NULLIF(JSON_VALUE(j.value,'$.channel'),''),
                                'mercadolibre'
                            )
                        ),

                    market =
                        CASE UPPER(
                            ISNULL(
                                NULLIF(JSON_VALUE(j.value,'$.market'),''),
                                'MX'
                            )
                        )
                            WHEN 'MLM' THEN 'MX'
                            WHEN 'MX' THEN 'MX'
                            WHEN 'US' THEN 'US'
                            ELSE 'MX'
                        END,

                    channelItemId =
                        JSON_VALUE(j.value,'$.channelItemId'),

                    title =
                        JSON_VALUE(j.value,'$.title'),

                    sellPriceOriginal =
                        TRY_CONVERT(
                            DECIMAL(18,6),
                            JSON_VALUE(j.value,'$.sellPriceOriginal')
                        ),

                    currencyOriginal =
                        JSON_VALUE(j.value,'$.currencyOriginal'),

                    sellPriceUsd_raw =
                        TRY_CONVERT(
                            DECIMAL(18,8),
                            JSON_VALUE(j.value,'$.sellPriceUsd')
                        ),

                    fxRateToUsd =
                        TRY_CONVERT(
                            DECIMAL(18,8),
                            JSON_VALUE(j.value,'$.fxRateToUsd')
                        ),

                    fxAsOfDate =
                        TRY_CONVERT(
                            DATE,
                            JSON_VALUE(j.value,'$.fxAsOfDate')
                        ),

                    listingTimestamp_raw =
                        TRY_CONVERT(
                            DATETIME2(6),
                            JSON_VALUE(j.value,'$.listingTimestamp')
                        ),

                    capturedAtUtc_raw =
                        TRY_CONVERT(
                            DATETIME2(6),
                            JSON_VALUE(j.value,'$.capturedAtUtc')
                        ),

                    fulfillmentType =
                        JSON_VALUE(j.value,'$.fulfillmentType'),

                    shippingTimeDays =
                        TRY_CONVERT(
                            INT,
                            JSON_VALUE(j.value,'$.shippingTimeDays')
                        ),

                    rating =
                        TRY_CONVERT(
                            DECIMAL(5,2),
                            JSON_VALUE(j.value,'$.rating')
                        ),

                    reviewsCount =
                        TRY_CONVERT(
                            INT,
                            JSON_VALUE(j.value,'$.reviewsCount')
                        ),

                    unifiedProductId =
                        TRY_CONVERT(
                            BIGINT,
                            JSON_VALUE(j.value,'$.unifiedProductId')
                        ),

                    attributesJson =
                        COALESCE
                        (
                            JSON_QUERY(j.value,'$.attributes'),

                            (
                                SELECT
                                    JSON_VALUE(j.value,'$.permalink')      AS permalink,
                                    JSON_VALUE(j.value,'$.image')          AS image,
                                    JSON_VALUE(j.value,'$.condition')      AS condition,
                                    JSON_VALUE(j.value,'$.brand')          AS brand,
                                    JSON_VALUE(j.value,'$.itemId')         AS itemId,
                                    JSON_VALUE(j.value,'$.upId')           AS upId,
                                    JSON_VALUE(j.value,'$.capturedAtUtc')  AS capturedAtUtc
                                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                            )
                        )

                FROM OPENJSON(@pjsonfile,'$.sellListings') j

            ),

            src2 AS
            (

                SELECT

                    channel,
                    market,
                    channelItemId,
                    title,

                    sellPriceOriginal,
                    currencyOriginal,

                    sellPriceUsd =
                        ISNULL(
                            sellPriceUsd_raw,
                            sellPriceOriginal * fxRateToUsd
                        ),

                    fxRateToUsd,
                    fxAsOfDate,

                    fulfillmentType,
                    shippingTimeDays,
                    rating,
                    reviewsCount,

                    unifiedProductId,

                    attributesJson,

                    listingTimestamp =
                        COALESCE
                        (
                            listingTimestamp_raw,

                            DATEADD
                            (
                                DAY,
                                DATEDIFF(DAY,0,fxAsOfDate),
                                0
                            )
                        )

                FROM src

            )


            -----------------------------------------------------------------
            -- MERGE sellListings
            -----------------------------------------------------------------
            MERGE dbo.sellListings tgt

            USING src2 s

            ON
                tgt.channel = s.channel
                AND tgt.market = s.market
                AND tgt.channelItemId = s.channelItemId
                AND tgt.listingTimestamp = s.listingTimestamp


            WHEN MATCHED THEN

                UPDATE SET

                    tgt.title = COALESCE(s.title,tgt.title),

                    tgt.sellPriceOriginal = s.sellPriceOriginal,
                    tgt.currencyOriginal = s.currencyOriginal,
                    tgt.sellPriceUsd = s.sellPriceUsd,

                    tgt.fxRateToUsd = s.fxRateToUsd,
                    tgt.fxAsOfDate = s.fxAsOfDate,

                    tgt.fulfillmentType = s.fulfillmentType,
                    tgt.shippingTimeDays = s.shippingTimeDays,

                    tgt.rating = s.rating,
                    tgt.reviewsCount = s.reviewsCount,

                    tgt.unifiedProductId =
                        COALESCE
                        (
                            tgt.unifiedProductId,
                            s.unifiedProductId
                        ),

                    tgt.updatedAt = SYSUTCDATETIME()


            WHEN NOT MATCHED THEN

                INSERT
                (
                    channel,
                    market,
                    channelItemId,
                    title,

                    sellPriceOriginal,
                    currencyOriginal,
                    sellPriceUsd,

                    fxRateToUsd,
                    fxAsOfDate,

                    fulfillmentType,
                    shippingTimeDays,
                    rating,
                    reviewsCount,

                    listingTimestamp,
                    unifiedProductId,

                    createdAt,
                    updatedAt
                )

                VALUES
                (
                    s.channel,
                    s.market,
                    s.channelItemId,
                    s.title,

                    s.sellPriceOriginal,
                    s.currencyOriginal,
                    s.sellPriceUsd,

                    s.fxRateToUsd,
                    s.fxAsOfDate,

                    s.fulfillmentType,
                    s.shippingTimeDays,
                    s.rating,
                    s.reviewsCount,

                    s.listingTimestamp,
                    s.unifiedProductId,

                    SYSUTCDATETIME(),
                    SYSUTCDATETIME()
                )


            OUTPUT

                inserted.sellListingId,

                s.attributesJson,

                CASE
                    WHEN s.attributesJson IS NOT NULL
                    THEN HASHBYTES
                    (
                        'SHA2_256',
                        CONVERT(VARBINARY(MAX),s.attributesJson)
                    )
                END

            INTO @merge_attr;


            -----------------------------------------------------------------
            -- UPSERT ATTRIBUTES TABLE
            -----------------------------------------------------------------
            MERGE dbo.sellListingAttributes tgt

            USING
            (
                SELECT
                    sellListingId,
                    attributesJson,
                    attributesHash
                FROM @merge_attr
                WHERE attributesJson IS NOT NULL
            ) src

            ON tgt.sellListingId = src.sellListingId

            WHEN MATCHED
                AND
                (
                    tgt.attributesHash IS NULL
                    OR tgt.attributesHash <> src.attributesHash
                )

            THEN UPDATE SET

                tgt.attributesJson = src.attributesJson,
                tgt.attributesHash = src.attributesHash,
                tgt.updatedAt = SYSUTCDATETIME()


            WHEN NOT MATCHED THEN

                INSERT
                (
                    sellListingId,
                    attributesJson,
                    attributesHash,
                    updatedAt
                )

                VALUES
                (
                    src.sellListingId,
                    src.attributesJson,
                    src.attributesHash,
                    SYSUTCDATETIME()
                );


            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].value','1');

            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].msg','Upsert OK');

            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].error','0');

        END


        ---------------------------------------------------------------------
        -- ACTION 2 UPDATE
        ---------------------------------------------------------------------
        ELSE IF @action = 2
        BEGIN

            UPDATE s

            SET

                s.title =
                    COALESCE
                    (
                        JSON_VALUE(j.value,'$.title'),
                        s.title
                    ),

                s.sellPriceOriginal =
                    COALESCE
                    (
                        TRY_CONVERT
                        (
                            DECIMAL(18,6),
                            JSON_VALUE(j.value,'$.sellPriceOriginal')
                        ),
                        s.sellPriceOriginal
                    ),

                s.sellPriceUsd =
                    COALESCE
                    (
                        TRY_CONVERT
                        (
                            DECIMAL(18,8),
                            JSON_VALUE(j.value,'$.sellPriceUsd')
                        ),
                        s.sellPriceUsd
                    ),

                s.updatedAt = SYSUTCDATETIME()

            FROM dbo.sellListings s

            JOIN OPENJSON(@pjsonfile,'$.sellListings') j

            ON s.sellListingId =
                TRY_CONVERT
                (
                    BIGINT,
                    JSON_VALUE(j.value,'$.sellListingId')
                );


            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].value','1');

            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].msg','Update OK');

            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].error','0');

        END


        ---------------------------------------------------------------------
        -- ACTION 3 DELETE
        ---------------------------------------------------------------------
        ELSE IF @action = 3
        BEGIN

            DELETE a
            FROM dbo.sellListingAttributes a

            JOIN OPENJSON(@pjsonfile,'$.sellListings') j

            ON a.sellListingId =
                TRY_CONVERT
                (
                    BIGINT,
                    JSON_VALUE(j.value,'$.sellListingId')
                );


            DELETE s
            FROM dbo.sellListings s

            JOIN OPENJSON(@pjsonfile,'$.sellListings') j

            ON s.sellListingId =
                TRY_CONVERT
                (
                    BIGINT,
                    JSON_VALUE(j.value,'$.sellListingId')
                );


            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].value','1');

            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].msg','Delete OK');

            SET @Outputmessage =
                JSON_MODIFY(@Outputmessage,'$.result[0].error','0');

        END


        COMMIT TRANSACTION;

    END TRY

    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();

        SET @Outputmessage =
            JSON_MODIFY(@Outputmessage,'$.result[0].value','0');

        SET @Outputmessage =
            JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);

        SET @Outputmessage =
            JSON_MODIFY(@Outputmessage,'$.result[0].error','1');

    END CATCH;


    ---------------------------------------------------------------------
    -- RETURN RESULT
    ---------------------------------------------------------------------
    SELECT

        JSON_VALUE(value,'$.value') AS value,
        JSON_VALUE(value,'$.msg') AS msg,
        JSON_VALUE(value,'$.error') AS error

    FROM OPENJSON(@Outputmessage,'$.result');

END
GO

-- dbo.sp_sellListings_all
IF OBJECT_ID(N'dbo.sp_sellListings_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_sellListings_all];
GO

CREATE PROC [dbo].[sp_sellListings_all]
AS
BEGIN
  SET NOCOUNT ON;

  SELECT
      s.[sellListingId],
      ISNULL(s.[channel],'')            AS channel,
      ISNULL(s.[market],'')             AS market,
      ISNULL(s.[channelItemId],'')      AS channelItemId,
      ISNULL(s.[title],'')              AS title,

      s.[sellPriceOriginal],
      ISNULL(s.[currencyOriginal],'')   AS currencyOriginal,
      s.[sellPriceUsd],
      s.[fxRateToUsd],
      s.[fxAsOfDate],

      ISNULL(s.[fulfillmentType],'')    AS fulfillmentType,
      s.[shippingTimeDays],
      s.[rating],
      s.[reviewsCount],

      s.[listingTimestamp],
      s.[unifiedProductId],

      s.[createdAt],
      ISNULL(CONVERT(VARCHAR(33), s.[updatedAt], 127), '') AS updatedAt,

      -- ✅ NEW: attributes as JSON object (not string)
      attributes =
        COALESCE(JSON_QUERY(a.[attributesJson]), JSON_QUERY(N'{}'))

  FROM [dbo].[sellListings] s
  LEFT JOIN [dbo].[sellListingAttributes] a
    ON a.[sellListingId] = s.[sellListingId]

  ORDER BY s.[listingTimestamp] DESC, s.[sellListingId] DESC
  FOR JSON PATH, ROOT('sellListings');
END
GO

-- dbo.sp_sellListings_backup
IF OBJECT_ID(N'dbo.sp_sellListings_backup', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_sellListings_backup];
GO

CREATE PROC [dbo].[sp_sellListings_backup] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /*
  DECLARE @pjsonfile NVARCHAR(MAX) = N'
    {
    "sellListings": [
        {
        "action": 1,
        "channel": "mercadolibre",
        "market": "MLM",
        "channelItemId": "MLM1054106937",
        "title": "Apple iPhone 17 Pro Max (256 GB) - Color plata - Sólo eSIM - Distribuidor Autorizado",
        "sellPriceOriginal": 30999.0,
        "currencyOriginal": "MXN",
        "sellPriceUsd": 1800.0,
        "fxRateToUsd": 0.05809,
        "fxAsOfDate": "2026-02-19",
        "fulfillmentType": null,
        "shippingTimeDays": null,
        "rating": null,
        "reviewsCount": null,
        "unifiedProductId": null,

        "attributes": {
            "brand": "Apple",
            "weight": "231 g",
            "width": "7.8 cm",
            "height": "16.34 cm",
            "color": "Gris",
            "description": "Memoria RAM: 12 GB. | ESIM integrada: activa tu iPhone sin SIM física..."
        }
        }
    ]
    }';
  */

  DECLARE
    @Outputmessage NVARCHAR(MAX) = N'{ "result": [ { "value": "", "msg": "", "error": "" } ] }',
    @Error NVARCHAR(4000) = N'',
    @action INT;

  SET @action = (
    SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
    FROM OPENJSON(@pjsonfile, '$.sellListings')
  );

  IF @action IS NULL SET @action = 1;

  BEGIN TRY
    BEGIN TRANSACTION;

    /* =========================================================
       ACTION 1: UPSERT (MERGE) - Idempotent daily
       listingTimestamp is CANONICALIZED to fxAsOfDate 00:00:00
       ========================================================= */
    IF @action = 1
    BEGIN
      /* =========================================
         VALIDATION: required fields
         ========================================= */
      IF EXISTS (
        SELECT 1
        FROM OPENJSON(@pjsonfile, '$.sellListings') j
        WHERE
          NULLIF(JSON_VALUE(j.value, '$.channelItemId'), '') IS NULL
          OR TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.sellPriceOriginal')) IS NULL
          OR NULLIF(JSON_VALUE(j.value, '$.currencyOriginal'), '') IS NULL
          OR TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(j.value, '$.fxRateToUsd')) IS NULL
          OR TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.fxAsOfDate')) IS NULL
          OR (
            TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.sellPriceUsd')) IS NULL
            AND (
              TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.sellPriceOriginal')) IS NULL
              OR TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(j.value, '$.fxRateToUsd')) IS NULL
            )
          )
      )
      BEGIN
        RAISERROR('Invalid payload: required fields missing (channelItemId, sellPriceOriginal, currencyOriginal, fxRateToUsd, fxAsOfDate, sellPriceUsd or calculable).', 16, 1);
      END

      /* =========================================
         UPSERT
         - Canonical listingTimestamp per day
         - Do NOT wipe unifiedProductId on updates
         ========================================= */

      -- Capture sellListingId + attributes from MERGE
      DECLARE @merge_attr TABLE (
        sellListingId   BIGINT       NOT NULL,
        attributesJson  NVARCHAR(MAX) NULL,
        attributesHash  VARBINARY(32) NULL
      );

      ;WITH src AS (
        SELECT
          channel =
            ISNULL(NULLIF(JSON_VALUE(j.value, '$.channel'), ''), 'mercadolibre'),

          market =
            ISNULL(NULLIF(JSON_VALUE(j.value, '$.market'), ''), 'MX'),

          channelItemId =
            NULLIF(JSON_VALUE(j.value, '$.channelItemId'), ''),

          title =
            NULLIF(JSON_VALUE(j.value, '$.title'), ''),

          sellPriceOriginal =
            TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.sellPriceOriginal')),

          currencyOriginal =
            NULLIF(JSON_VALUE(j.value, '$.currencyOriginal'), ''),

          sellPriceUsd_raw =
            TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.sellPriceUsd')),

          fxRateToUsd =
            TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(j.value, '$.fxRateToUsd')),

          fxAsOfDate =
            TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.fxAsOfDate')),

          fulfillmentType =
            NULLIF(JSON_VALUE(j.value, '$.fulfillmentType'), ''),

          shippingTimeDays =
            TRY_CONVERT(INT, JSON_VALUE(j.value, '$.shippingTimeDays')),

          rating =
            TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(j.value, '$.rating')),

          reviewsCount =
            TRY_CONVERT(INT, JSON_VALUE(j.value, '$.reviewsCount')),

          unifiedProductId =
            TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.unifiedProductId')),

          -- ✅ NEW: raw attributes JSON (object)
          attributesJson =
            JSON_QUERY(j.value, '$.attributes')
        FROM OPENJSON(@pjsonfile, '$.sellListings') j
      ),
      src2 AS (
        SELECT
          channel,
          market,
          channelItemId,
          title,
          sellPriceOriginal,
          currencyOriginal,

          sellPriceUsd =
            ISNULL(sellPriceUsd_raw,
              sellPriceOriginal * fxRateToUsd
            ),

          fxRateToUsd,
          fxAsOfDate,
          fulfillmentType,
          shippingTimeDays,
          rating,
          reviewsCount,

          -- ✅ CANONICAL DAILY TIMESTAMP (idempotent daily)
          listingTimestamp =
            DATEADD(DAY, DATEDIFF(DAY, 0, fxAsOfDate), 0),

          unifiedProductId,

          -- carry forward
          attributesJson
        FROM src
      )
      MERGE dbo.sellListings AS tgt
      USING src2 AS s
        ON  tgt.channel = s.channel
        AND tgt.market = s.market
        AND tgt.channelItemId = s.channelItemId
        AND tgt.listingTimestamp = s.listingTimestamp
      WHEN MATCHED THEN
        UPDATE SET
          tgt.title = COALESCE(s.title, tgt.title),
          tgt.sellPriceOriginal = s.sellPriceOriginal,
          tgt.currencyOriginal  = s.currencyOriginal,
          tgt.sellPriceUsd      = s.sellPriceUsd,
          tgt.fxRateToUsd       = s.fxRateToUsd,
          tgt.fxAsOfDate        = s.fxAsOfDate,
          tgt.fulfillmentType   = s.fulfillmentType,
          tgt.shippingTimeDays  = s.shippingTimeDays,
          tgt.rating            = s.rating,
          tgt.reviewsCount      = s.reviewsCount,

          -- ✅ do NOT wipe existing unifiedProductId with NULL
          tgt.unifiedProductId  = COALESCE(tgt.unifiedProductId, s.unifiedProductId),

          tgt.updatedAt         = SYSUTCDATETIME()
      WHEN NOT MATCHED THEN
        INSERT (
          channel, market, channelItemId, title,
          sellPriceOriginal, currencyOriginal, sellPriceUsd,
          fxRateToUsd, fxAsOfDate,
          fulfillmentType, shippingTimeDays, rating, reviewsCount,
          listingTimestamp, unifiedProductId,
          createdAt, updatedAt
        )
        VALUES (
          s.channel, s.market, s.channelItemId, s.title,
          s.sellPriceOriginal, s.currencyOriginal, s.sellPriceUsd,
          s.fxRateToUsd, s.fxAsOfDate,
          s.fulfillmentType, s.shippingTimeDays, s.rating, s.reviewsCount,
          s.listingTimestamp, s.unifiedProductId,
          SYSUTCDATETIME(), SYSUTCDATETIME()
        )
      OUTPUT
        inserted.sellListingId,
        s.attributesJson,
        CASE
          WHEN s.attributesJson IS NOT NULL AND ISJSON(s.attributesJson) = 1
            THEN HASHBYTES('SHA2_256', s.attributesJson)
          ELSE NULL
        END
      INTO @merge_attr (sellListingId, attributesJson, attributesHash);

      /* =========================================
         ✅ NEW: Upsert attributes JSON (one row per sellListingId)
         Only if attributesJson is a valid JSON object
         ========================================= */
      MERGE dbo.sellListingAttributes AS tgt
      USING (
        SELECT
          ma.sellListingId,
          ma.attributesJson,
          ma.attributesHash
        FROM @merge_attr ma
        WHERE ma.attributesJson IS NOT NULL AND ISJSON(ma.attributesJson) = 1
      ) AS srcA
      ON tgt.sellListingId = srcA.sellListingId
      WHEN MATCHED AND (
           tgt.attributesHash IS NULL
           OR tgt.attributesHash <> srcA.attributesHash
           OR tgt.attributesJson IS NULL
         )
        THEN UPDATE SET
          tgt.attributesJson = srcA.attributesJson,
          tgt.attributesHash = srcA.attributesHash,
          tgt.updatedAt      = SYSUTCDATETIME()
      WHEN NOT MATCHED
        THEN INSERT (sellListingId, attributesJson, attributesHash, updatedAt)
             VALUES (srcA.sellListingId, srcA.attributesJson, srcA.attributesHash, SYSUTCDATETIME());

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Upsert OK');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '0');
    END

    /* =========================================================
       ACTION 2: UPDATE by sellListingId (partial update)
       Note: also canonicalizes listingTimestamp if fxAsOfDate provided
       ========================================================= */
    ELSE IF @action = 2
    BEGIN
      UPDATE s
      SET
        s.channel = COALESCE(NULLIF(JSON_VALUE(j.value, '$.channel'), ''), s.channel),
        s.market  = COALESCE(NULLIF(JSON_VALUE(j.value, '$.market'), ''), s.market),
        s.channelItemId = COALESCE(NULLIF(JSON_VALUE(j.value, '$.channelItemId'), ''), s.channelItemId),
        s.title = COALESCE(NULLIF(JSON_VALUE(j.value, '$.title'), ''), s.title),

        s.sellPriceOriginal = COALESCE(TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.sellPriceOriginal')), s.sellPriceOriginal),
        s.currencyOriginal  = COALESCE(NULLIF(JSON_VALUE(j.value, '$.currencyOriginal'), ''), s.currencyOriginal),
        s.sellPriceUsd      = COALESCE(TRY_CONVERT(DECIMAL(18,6), JSON_VALUE(j.value, '$.sellPriceUsd')), s.sellPriceUsd),

        s.fxRateToUsd       = COALESCE(TRY_CONVERT(DECIMAL(18,8), JSON_VALUE(j.value, '$.fxRateToUsd')), s.fxRateToUsd),
        s.fxAsOfDate        = COALESCE(TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.fxAsOfDate')), s.fxAsOfDate),

        s.fulfillmentType   = COALESCE(NULLIF(JSON_VALUE(j.value, '$.fulfillmentType'), ''), s.fulfillmentType),
        s.shippingTimeDays  = COALESCE(TRY_CONVERT(INT, JSON_VALUE(j.value, '$.shippingTimeDays')), s.shippingTimeDays),
        s.rating            = COALESCE(TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(j.value, '$.rating')), s.rating),
        s.reviewsCount      = COALESCE(TRY_CONVERT(INT, JSON_VALUE(j.value, '$.reviewsCount')), s.reviewsCount),

        -- If fxAsOfDate is provided, canonicalize listingTimestamp to that day @ 00:00:00
        s.listingTimestamp  =
          CASE
            WHEN TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.fxAsOfDate')) IS NOT NULL
              THEN DATEADD(DAY, DATEDIFF(DAY, 0, TRY_CONVERT(DATE, JSON_VALUE(j.value, '$.fxAsOfDate'))), 0)
            ELSE COALESCE(TRY_CONVERT(DATETIME2(7), JSON_VALUE(j.value, '$.listingTimestamp')), s.listingTimestamp)
          END,

        -- Do not wipe mapping
        s.unifiedProductId  = COALESCE(s.unifiedProductId, TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.unifiedProductId'))),

        s.updatedAt         = SYSUTCDATETIME()
      FROM dbo.sellListings s
      INNER JOIN OPENJSON(@pjsonfile, '$.sellListings') j
        ON s.sellListingId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.sellListingId'));

      /* =========================================
         ✅ NEW: Upsert attributes for Action 2
         Uses sellListingId directly from payload
         ========================================= */
      ;WITH a AS (
        SELECT
          sellListingId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.sellListingId')),
          attributesJson = JSON_QUERY(j.value, '$.attributes')
        FROM OPENJSON(@pjsonfile, '$.sellListings') j
      ),
      a2 AS (
        SELECT
          sellListingId,
          attributesJson,
          attributesHash =
            CASE
              WHEN attributesJson IS NOT NULL AND ISJSON(attributesJson) = 1
                THEN HASHBYTES('SHA2_256', attributesJson)
              ELSE NULL
            END
        FROM a
        WHERE sellListingId IS NOT NULL
          AND attributesJson IS NOT NULL
          AND ISJSON(attributesJson) = 1
      )
      MERGE dbo.sellListingAttributes AS tgt
      USING a2 AS srcA
      ON tgt.sellListingId = srcA.sellListingId
      WHEN MATCHED AND (
           tgt.attributesHash IS NULL
           OR tgt.attributesHash <> srcA.attributesHash
           OR tgt.attributesJson IS NULL
         )
        THEN UPDATE SET
          tgt.attributesJson = srcA.attributesJson,
          tgt.attributesHash = srcA.attributesHash,
          tgt.updatedAt      = SYSUTCDATETIME()
      WHEN NOT MATCHED
        THEN INSERT (sellListingId, attributesJson, attributesHash, updatedAt)
             VALUES (srcA.sellListingId, srcA.attributesJson, srcA.attributesHash, SYSUTCDATETIME());

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '0');
    END

    /* =========================================================
       ACTION 3: DELETE by sellListingId
       ========================================================= */
    ELSE IF @action = 3
    BEGIN
      -- ✅ NEW: delete attributes first (FK protection)
      DELETE FROM dbo.sellListingAttributes
      WHERE sellListingId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.sellListingId'))
        FROM OPENJSON(@pjsonfile, '$.sellListings')
      );

      DELETE FROM dbo.sellListings
      WHERE sellListingId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.sellListingId'))
        FROM OPENJSON(@pjsonfile, '$.sellListings')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', '1');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
      SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '0');
    END
    ELSE
    BEGIN
      RAISERROR('Invalid action. Use 1 (UPSERT), 2 (UPDATE), 3 (DELETE).', 16, 1);
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', '0');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH;

  SELECT
    JSON_VALUE(value, '$.value') AS [value],
    JSON_VALUE(value, '$.msg')   AS [msg],
    JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_sellListings_query
IF OBJECT_ID(N'dbo.sp_sellListings_query', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_sellListings_query];
GO

CREATE PROC [dbo].[sp_sellListings_query]
(
  @pjsonfile NVARCHAR(MAX)
)
AS
BEGIN
  SET NOCOUNT ON;

  ------------------------------------------------------------
  -- Extract params from JSON (sellListings[0])
  ------------------------------------------------------------
  DECLARE
    @channel          NVARCHAR(50)  = NULLIF(JSON_VALUE(@pjsonfile, '$.sellListings[0].channel'), ''),
    @market           NVARCHAR(10)  = NULLIF(JSON_VALUE(@pjsonfile, '$.sellListings[0].market'), ''),
    @channelItemId    NVARCHAR(100) = NULLIF(JSON_VALUE(@pjsonfile, '$.sellListings[0].channelItemId'), ''),
    @unifiedProductId BIGINT        = TRY_CONVERT(BIGINT, JSON_VALUE(@pjsonfile, '$.sellListings[0].unifiedProductId')),
    @dateFrom         DATE          = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.sellListings[0].dateFrom')),
    @dateTo           DATE          = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.sellListings[0].dateTo')),
    @page             INT           = ISNULL(TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.sellListings[0].page')), 1),
    @pageSize         INT           = ISNULL(TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.sellListings[0].pageSize')), 100);

  ------------------------------------------------------------
  -- Normalize pagination
  ------------------------------------------------------------
  IF @page IS NULL OR @page < 1 SET @page = 1;
  IF @pageSize IS NULL OR @pageSize < 1 SET @pageSize = 100;
  IF @pageSize > 500 SET @pageSize = 500;

  DECLARE @offset INT = (@page - 1) * @pageSize;

  ------------------------------------------------------------
  -- Query + paging
  ------------------------------------------------------------
  ;WITH base AS
  (
      SELECT
          s.[sellListingId],
          s.[channel],
          s.[market],
          s.[channelItemId],
          s.[title],
          s.[sellPriceOriginal],
          s.[currencyOriginal],
          s.[sellPriceUsd],
          s.[fxRateToUsd],
          s.[fxAsOfDate],
          s.[fulfillmentType],
          s.[shippingTimeDays],
          s.[rating],
          s.[reviewsCount],
          s.[listingTimestamp],
          s.[unifiedProductId],
          s.[createdAt],
          s.[updatedAt]
      FROM dbo.sellListings s
      WHERE
          (@channel IS NULL OR s.channel = @channel)
          AND (@market IS NULL OR s.market = @market)
          AND (@channelItemId IS NULL OR s.channelItemId = @channelItemId)
          AND (@unifiedProductId IS NULL OR s.unifiedProductId = @unifiedProductId)
          AND (@dateFrom IS NULL OR s.listingTimestamp >= DATEADD(DAY, DATEDIFF(DAY, 0, @dateFrom), 0))
          AND (
              @dateTo IS NULL
              OR s.listingTimestamp < DATEADD(DAY, 1, DATEADD(DAY, DATEDIFF(DAY, 0, @dateTo), 0))
          )
  ),
  numbered AS
  (
      SELECT
          *,
          ROW_NUMBER() OVER (ORDER BY listingTimestamp DESC, sellListingId DESC) AS rn,
          COUNT(1) OVER() AS totalRows
      FROM base
  )
  SELECT
      totalRows,
      page     = @page,
      pageSize = @pageSize,

      sellListingId,
      channel          = ISNULL(channel,''),
      market           = ISNULL(market,''),
      channelItemId    = ISNULL(channelItemId,''),
      title            = ISNULL(title,''),

      sellPriceOriginal,
      currencyOriginal = ISNULL(currencyOriginal,''),
      sellPriceUsd,
      fxRateToUsd,
      fxAsOfDate,

      fulfillmentType  = ISNULL(fulfillmentType,''),
      shippingTimeDays,
      rating,
      reviewsCount,

      listingTimestamp,
      unifiedProductId,

      createdAt,
      updatedAt = ISNULL(CONVERT(NVARCHAR(33), updatedAt, 126), '')
  FROM numbered
  WHERE rn > @offset AND rn <= (@offset + @pageSize)
  FOR JSON PATH, ROOT('sellListingsQuery');

END
GO

-- dbo.sp_shipments
IF OBJECT_ID(N'dbo.sp_shipments', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_shipments];
GO

CREATE PROC [dbo].[sp_shipments] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
  SET NOCOUNT ON;

/*
  DECLARE @pjsonfile VARCHAR(MAX) = '{
  "shipments": [
    {
      "marketplaceOrderId": 1,
      "carrier": "UPS",
      "serviceLevel": "Ground",
      "labelRef": "LBL-UPS-000001",
      "trackingNumber": "1Z999AA10123456784",
      "status": "LABEL_CREATED",
      "shippedAt": null,
      "deliveredAt": null,
      "lastError": null,
      "action": "1"
    }
  ]
}';
*/

  DECLARE @Outputmessage NVARCHAR(MAX) = '
  { "result": [ { "value": "", "msg": "", "error": "" } ] }',
  @Error NVARCHAR(500) = '',
  @action INT;

  SET @action = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value,'$.action')) FROM OPENJSON(@pjsonfile,'$.shipments'));

  BEGIN TRY
    BEGIN TRANSACTION;

    IF @action = 1
    BEGIN
      INSERT INTO dbo.shipments (
        marketplaceOrderId, carrier, serviceLevel, labelRef,
        trackingNumber, status, shippedAt, deliveredAt, lastError
      )
      SELECT
        TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.marketplaceOrderId')),
        JSON_VALUE(value,'$.carrier'),
        JSON_VALUE(value,'$.serviceLevel'),
        JSON_VALUE(value,'$.labelRef'),
        JSON_VALUE(value,'$.trackingNumber'),
        ISNULL(NULLIF(JSON_VALUE(value,'$.status'),''),'LABEL_CREATED'),
        TRY_CONVERT(DATETIME2, JSON_VALUE(value,'$.shippedAt')),
        TRY_CONVERT(DATETIME2, JSON_VALUE(value,'$.deliveredAt')),
        JSON_VALUE(value,'$.lastError')
      FROM OPENJSON(@pjsonfile,'$.shipments');

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Inserted Successfully');
    END
    ELSE IF @action = 2
    BEGIN
      UPDATE s
      SET
        s.marketplaceOrderId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.marketplaceOrderId')),
        s.carrier = JSON_VALUE(j.value,'$.carrier'),
        s.serviceLevel = JSON_VALUE(j.value,'$.serviceLevel'),
        s.labelRef = JSON_VALUE(j.value,'$.labelRef'),
        s.trackingNumber = JSON_VALUE(j.value,'$.trackingNumber'),
        s.status = ISNULL(NULLIF(JSON_VALUE(j.value,'$.status'),''), s.status),
        s.shippedAt = TRY_CONVERT(DATETIME2, JSON_VALUE(j.value,'$.shippedAt')),
        s.deliveredAt = TRY_CONVERT(DATETIME2, JSON_VALUE(j.value,'$.deliveredAt')),
        s.lastError = JSON_VALUE(j.value,'$.lastError'),
        s.updatedAt = SYSUTCDATETIME()
      FROM dbo.shipments s
      INNER JOIN OPENJSON(@pjsonfile,'$.shipments') j
        ON s.shipmentId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value,'$.shipmentId'));

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Updated Successfully');
    END
    ELSE IF @action = 3
    BEGIN
      DELETE FROM dbo.shipments
      WHERE shipmentId IN (
        SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value,'$.shipmentId'))
        FROM OPENJSON(@pjsonfile,'$.shipments')
      );

      SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg','Deleted Successfully');
    END

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].error','1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage,'$.result[0].msg',@Error);
  END CATCH

  SELECT
    JSON_VALUE(value,'$.value') AS [value],
    JSON_VALUE(value,'$.msg') AS [msg],
    JSON_VALUE(value,'$.error') AS [error]
  FROM OPENJSON(@Outputmessage,'$.result');
END
GO

-- dbo.sp_shipments_next
IF OBJECT_ID(N'dbo.sp_shipments_next', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_shipments_next];
GO
CREATE   PROC dbo.sp_shipments_next
  @batchSize INT = 10
AS
BEGIN
  SET NOCOUNT ON;

  ;WITH cte AS (
    SELECT TOP (@batchSize)
      s.shipmentId
    FROM dbo.shipments s WITH (READPAST, UPDLOCK, ROWLOCK)
    WHERE s.status IN ('LABEL_CREATED','SHIPPED')
    ORDER BY s.updatedAt ASC, s.shipmentId ASC
  )
  UPDATE s
    SET s.status = 'processing',
        s.updatedAt = SYSUTCDATETIME()
  OUTPUT
    inserted.shipmentId,
    inserted.marketplaceOrderId,
    inserted.carrier,
    inserted.serviceLevel,
    inserted.labelRef,
    inserted.trackingNumber,
    inserted.status,
    inserted.shippedAt,
    inserted.deliveredAt
  FROM dbo.shipments s
  JOIN cte ON cte.shipmentId = s.shipmentId;
END
GO

-- dbo.sp_statuses
IF OBJECT_ID(N'dbo.sp_statuses', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_statuses];
GO
CREATE PROC [dbo].[sp_statuses] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "statuses": [
        {
            "statusId": 1,
            "status": "active",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/
    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.statuses'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the statuses
            INSERT INTO [dbo].[statuses] 
                ([status], [createdAt])
            SELECT
                JSON_VALUE(value, '$.status'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.statuses');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the statuses
            UPDATE s
            SET 
                s.[status] = JSON_VALUE(j.value, '$.status')
            FROM 
                [dbo].[statuses] s
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.statuses') j
                ON s.[statusId] = JSON_VALUE(j.value, '$.statusId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the statuses
            DELETE FROM [dbo].[statuses]
            WHERE [statusId] IN (SELECT JSON_VALUE(value, '$.statusId') FROM OPENJSON(@pjsonfile, '$.statuses'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_statuses_all
IF OBJECT_ID(N'dbo.sp_statuses_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_statuses_all];
GO

CREATE PROC [dbo].[sp_statuses_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [statusId],
        [status],
        [createdAt]
    FROM [montanogilberto_smartloans].[dbo].[statuses]
    FOR JSON AUTO, ROOT('statuses');
END
GO

-- dbo.sp_statuses_one
IF OBJECT_ID(N'dbo.sp_statuses_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_statuses_one];
GO
CREATE PROC [dbo].[sp_statuses_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "statuses": [
        {
        "statusId": "1"
        }
     ]   
    }'
    */

    DECLARE @statusId INT;

    SET @statusId = CAST((SELECT JSON_VALUE(value, '$.statusId') FROM OPENJSON(@pjsonfile, '$.statuses')) AS INT);

    SELECT 
        [statusId]
        ,[status]
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[statuses]
    WHERE
        statusId = @statusId
    FOR JSON AUTO, ROOT('statuses');

END
GO

-- dbo.sp_stripe_connectedAccounts
IF OBJECT_ID(N'dbo.sp_stripe_connectedAccounts', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_stripe_connectedAccounts];
GO

CREATE PROCEDURE [dbo].[sp_stripe_connectedAccounts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action                  NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].action')
        DECLARE @clientId                INT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].clientId')
        DECLARE @companyId               INT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].companyId')
        DECLARE @connectedAccountId      NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].connectedAccountId')
        DECLARE @chargesEnabled          BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].chargesEnabled')
        DECLARE @payoutsEnabled          BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].payoutsEnabled')
        DECLARE @detailsSubmitted        BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].detailsSubmitted')
        DECLARE @identitySubmitted       BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].identitySubmitted')
        DECLARE @hasExternalAccount      BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].hasExternalAccount')
        DECLARE @externalAccountLast4    NVARCHAR(4)   = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].externalAccountLast4')
        DECLARE @externalAccountType     NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].externalAccountType')
        DECLARE @externalAccountBankName NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].externalAccountBankName')
        DECLARE @tosAccepted             BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].tosAccepted')
        DECLARE @tosAcceptedAt           DATETIME2     = TRY_CONVERT(DATETIME2, JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].tosAcceptedAt'), 127)

        IF @action = 'upsert'
        BEGIN
            MERGE [dbo].[stripeConnectedAccounts] AS target
            USING (SELECT @clientId AS clientId, @companyId AS companyId) AS source
                ON target.clientId = source.clientId AND target.companyId = source.companyId
            WHEN MATCHED THEN
                UPDATE SET connectedAccountId      = ISNULL(@connectedAccountId,      target.connectedAccountId),
                           chargesEnabled          = ISNULL(@chargesEnabled,          target.chargesEnabled),
                           payoutsEnabled          = ISNULL(@payoutsEnabled,          target.payoutsEnabled),
                           detailsSubmitted        = ISNULL(@detailsSubmitted,        target.detailsSubmitted),
                           identitySubmitted       = ISNULL(@identitySubmitted,       target.identitySubmitted),
                           hasExternalAccount      = ISNULL(@hasExternalAccount,      target.hasExternalAccount),
                           externalAccountLast4    = ISNULL(@externalAccountLast4,    target.externalAccountLast4),
                           externalAccountType     = ISNULL(@externalAccountType,     target.externalAccountType),
                           externalAccountBankName = ISNULL(@externalAccountBankName, target.externalAccountBankName),
                           -- Sticky: una vez aceptado, nunca se revierte a 0 en
                           -- upserts posteriores que no traen tosAccepted (p.ej.
                           -- attach_external_bank_account).
                           tosAccepted             = CASE WHEN @tosAccepted = 1 THEN 1 ELSE target.tosAccepted END,
                           tosAcceptedAt           = ISNULL(@tosAcceptedAt,           target.tosAcceptedAt),
                           updated_at              = GETUTCDATE()
            WHEN NOT MATCHED THEN
                INSERT (clientId, companyId, connectedAccountId, chargesEnabled, payoutsEnabled, detailsSubmitted,
                        identitySubmitted, hasExternalAccount, externalAccountLast4, externalAccountType, externalAccountBankName,
                        tosAccepted, tosAcceptedAt)
                VALUES (@clientId, @companyId, @connectedAccountId,
                        ISNULL(@chargesEnabled, 0), ISNULL(@payoutsEnabled, 0), ISNULL(@detailsSubmitted, 0),
                        ISNULL(@identitySubmitted, 0), ISNULL(@hasExternalAccount, 0), @externalAccountLast4, @externalAccountType, @externalAccountBankName,
                        ISNULL(@tosAccepted, 0), @tosAcceptedAt);

            SELECT (SELECT TOP 1 * FROM [dbo].[stripeConnectedAccounts]
                    WHERE clientId = @clientId AND companyId = @companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 connectedAccountId, clientId, companyId,
                        chargesEnabled, payoutsEnabled, detailsSubmitted, identitySubmitted,
                        hasExternalAccount, externalAccountLast4, externalAccountType, externalAccountBankName,
                        tosAccepted, CONVERT(NVARCHAR, tosAcceptedAt, 127) AS tosAcceptedAt,
                        CONVERT(NVARCHAR, created_At, 127) AS created_At
                 FROM [dbo].[stripeConnectedAccounts]
                 WHERE clientId = @clientId AND companyId = @companyId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_stripe_transactions
IF OBJECT_ID(N'dbo.sp_stripe_transactions', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_stripe_transactions];
GO

CREATE PROCEDURE [dbo].[sp_stripe_transactions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action                 NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].action')
        DECLARE @companyId              INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].companyId')
        DECLARE @loanId                 INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].loanId')
        DECLARE @proposalId             INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].proposalId')
        DECLARE @fromClientId           INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].fromClientId')
        DECLARE @toClientId             INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].toClientId')
        DECLARE @amount                 INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].amount')
        DECLARE @currency               NVARCHAR(3)   = ISNULL(JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].currency'), 'mxn')
        DECLARE @paymentType            NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].paymentType')
        DECLARE @status                 NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].status'), 'pending')
        DECLARE @stripePaymentIntentId  NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].stripePaymentIntentId')
        DECLARE @stripeTransferId       NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].stripeTransferId')
        DECLARE @stripePayoutId         NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].stripePayoutId')
        DECLARE @failureReason          NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].failureReason')
        DECLARE @clientId               INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].clientId')

        IF @action = 'insert'
        BEGIN
            INSERT INTO [dbo].[stripeTransactions]
                (companyId, loanId, proposalId, fromClientId, toClientId, amount, currency,
                 paymentType, status, stripePaymentIntentId, stripeTransferId, stripePayoutId, failureReason)
            VALUES
                (@companyId, @loanId, @proposalId, @fromClientId, @toClientId, @amount, @currency,
                 @paymentType, @status, @stripePaymentIntentId, @stripeTransferId, @stripePayoutId, @failureReason)

            SELECT (SELECT transactionId, status, stripePaymentIntentId, stripePayoutId, amount, currency
                    FROM [dbo].[stripeTransactions]
                    WHERE transactionId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'update_status'
        BEGIN
            -- Capture the PREVIOUS status so callers can act exactly once on
            -- the pending→succeeded transition (e.g. credit a wallet top-up)
            -- even when both the app's confirm call and the Stripe webhook
            -- report the same intent.
            DECLARE @prev TABLE (prevStatus NVARCHAR(20));

            UPDATE [dbo].[stripeTransactions]
            SET status        = @status,
                failureReason = ISNULL(@failureReason, failureReason),
                updated_at    = GETUTCDATE()
            OUTPUT deleted.status INTO @prev
            WHERE stripePaymentIntentId = @stripePaymentIntentId
              AND (@companyId IS NULL OR companyId = @companyId)

            SELECT (SELECT TOP 1 transactionId, status,
                           (SELECT TOP 1 prevStatus FROM @prev) AS prevStatus,
                           stripePaymentIntentId, amount, currency,
                           paymentType, fromClientId, toClientId, companyId
                    FROM [dbo].[stripeTransactions]
                    WHERE stripePaymentIntentId = @stripePaymentIntentId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT transactionId, companyId, loanId, proposalId,
                        fromClientId, toClientId, amount, currency,
                        paymentType, status,
                        stripePaymentIntentId, stripeTransferId, stripePayoutId, failureReason,
                        CONVERT(NVARCHAR, created_At, 127) AS created_At,
                        CONVERT(NVARCHAR, updated_at, 127) AS updated_at
                 FROM [dbo].[stripeTransactions]
                 WHERE companyId = @companyId
                   AND (@clientId    IS NULL OR (fromClientId = @clientId OR toClientId = @clientId))
                   AND (@loanId      IS NULL OR loanId      = @loanId)
                   AND (@paymentType IS NULL OR paymentType = @paymentType)
                 ORDER BY created_At DESC
                 FOR JSON PATH, ROOT('transactions')),
                '{"transactions":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_suppliers
IF OBJECT_ID(N'dbo.sp_suppliers', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_suppliers];
GO
create PROCEDURE [dbo].[sp_suppliers]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage VARCHAR(MAX);
    DECLARE @Action INT;

    -- Temporary table to hold the parsed JSON data
    DECLARE @payload TABLE (
        action INT,
        supplierId INT,
        companyId INT,
        supplierName NVARCHAR(200),
        contactName NVARCHAR(100),
        phone NVARCHAR(20),
        email NVARCHAR(100),
        address NVARCHAR(MAX),
        active NVARCHAR(1)
    );

    -- Ajustado el path a '$.suppliers' o '$' según envíes el objeto desde FastAPI
    INSERT INTO @payload (action, supplierId, companyId, supplierName, contactName, phone, email, address, active)
    SELECT
        JSON_VALUE(value, '$.action'),
        JSON_VALUE(value, '$.supplierId'),
        JSON_VALUE(value, '$.companyId'),
        JSON_VALUE(value, '$.supplierName'),
        JSON_VALUE(value, '$.contactName'),
        JSON_VALUE(value, '$.phone'),
        JSON_VALUE(value, '$.email'),
        JSON_VALUE(value, '$.address'),
        JSON_VALUE(value, '$.active')
    FROM OPENJSON(@pjsonfile, '$.suppliers');

    -- Fallback si el JSON no viene envuelto en un nodo 'suppliers'
    IF NOT EXISTS (SELECT 1 FROM @payload)
    BEGIN
        INSERT INTO @payload (action, supplierId, companyId, supplierName, contactName, phone, email, address, active)
        SELECT
            JSON_VALUE(@pjsonfile, '$.action'),
            JSON_VALUE(@pjsonfile, '$.supplierId'),
            JSON_VALUE(@pjsonfile, '$.companyId'),
            JSON_VALUE(@pjsonfile, '$.supplierName'),
            JSON_VALUE(@pjsonfile, '$.contactName'),
            JSON_VALUE(@pjsonfile, '$.phone'),
            JSON_VALUE(@pjsonfile, '$.email'),
            JSON_VALUE(@pjsonfile, '$.address'),
            JSON_VALUE(@pjsonfile, '$.active');
    END

    SELECT @Action = action FROM @payload;

    -- GUARDRAIL: Estructura de control transaccional requerida por la arquitectura
    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Action = 1 -- INSERT
        BEGIN
            -- Validate for duplicate supplier name within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.supplierName = p.supplierName)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this name already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate email within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.email = p.email WHERE p.email IS NOT NULL AND p.email != '')
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this email already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate phone within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.phone = p.phone WHERE p.phone IS NOT NULL AND p.phone != '')
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this phone number already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            INSERT INTO [dbo].[Suppliers] (
                companyId, supplierName, contactName, phone, email, address, active, created_At
            )
            SELECT
                companyId, supplierName, contactName, phone, email, address, active, GETDATE()
            FROM @payload;

            SET @Outputmessage = '{"status": "success", "message": "Supplier inserted successfully."}';
        END
        ELSE IF @Action = 2 -- UPDATE
        BEGIN
            -- Validate if the supplier exists
            IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.supplierId = p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier not found."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate supplier name excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.supplierName = p.supplierName WHERE s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this name already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate email excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.email = p.email WHERE p.email IS NOT NULL AND p.email != '' AND s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this email already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate phone excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.phone = p.phone WHERE p.phone IS NOT NULL AND p.phone != '' AND s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this phone number already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            UPDATE s
            SET
                s.companyId = p.companyId,
                s.supplierName = p.supplierName,
                s.contactName = p.contactName,
                s.phone = p.phone,
                s.email = p.email,
                s.address = p.address,
                s.active = p.active,
                s.updated_at = GETDATE()
            FROM [dbo].[Suppliers] s
            JOIN @payload p ON s.supplierId = p.supplierId;

            SET @Outputmessage = '{"status": "success", "message": "Supplier updated successfully."}';
        END
        ELSE IF @Action = 3 -- DELETE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.supplierId = p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier not found."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            DELETE s
            FROM [dbo].[Suppliers] s
            JOIN @payload p ON s.supplierId = p.supplierId;

            SET @Outputmessage = '{"status": "success", "message": "Supplier deleted successfully."}';
        END
        ELSE
        BEGIN
            SET @Outputmessage = '{"status": "error", "message": "Invalid action specified."}';
            ROLLBACK TRANSACTION;
            GOTO Finish;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE();
        SET @Outputmessage = (
            SELECT 
                'error' AS [status], 
                'Internal SP Error: ' + @ErrMessage AS [message] 
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
    END CATCH

Finish:
    -- Retorna exactamente una fila con una columna '[jsonResult]', ideal para tu backend en FastAPI (json_result[0][0])
    SELECT @Outputmessage AS [jsonResult];
END;
GO

-- dbo.sp_suppliers_all
IF OBJECT_ID(N'dbo.sp_suppliers_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_suppliers_all];
GO
CREATE PROCEDURE [dbo].[sp_suppliers_all]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @companyId INT;

    SELECT TOP 1
        @companyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.suppliers')
    WHERE JSON_VALUE(value, '$.companyId') IS NOT NULL;

    SELECT
        s.supplierId,
        s.companyId,
        s.supplierName,
        ISNULL(s.contactName, '') AS contactName,
        ISNULL(s.phone, '') AS phone,
        ISNULL(s.email, '') AS email,
        ISNULL(s.address, '') AS address,
        s.active,
        CONVERT(VARCHAR(30), s.created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), s.updated_at, 126), '') AS updated_at
    FROM [dbo].[Suppliers] s
    WHERE s.companyId = @companyId OR @companyId IS NULL
    FOR JSON PATH, ROOT('suppliers');
END;
GO

-- dbo.sp_suppliers_one
IF OBJECT_ID(N'dbo.sp_suppliers_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_suppliers_one];
GO
CREATE PROCEDURE [dbo].[sp_suppliers_one]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @supplierId INT;
    DECLARE @companyId INT;

    SELECT
        @supplierId = JSON_VALUE(@pjsonfile, '$.supplierId'),
        @companyId = JSON_VALUE(@pjsonfile, '$.companyId');

    SELECT
        s.supplierId,
        s.companyId,
        s.supplierName,
        ISNULL(s.contactName, '') AS contactName,
        ISNULL(s.phone, '') AS phone,
        ISNULL(s.email, '') AS email,
        ISNULL(s.address, '') AS address,
        s.active,
        CONVERT(VARCHAR(30), s.created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), s.updated_at, 126), '') AS updated_at
    FROM [dbo].[Suppliers] s
    WHERE s.supplierId = @supplierId AND s.companyId = @companyId
    FOR JSON AUTO, ROOT('suppliers');

END
GO

-- dbo.sp_tankWater_all
IF OBJECT_ID(N'dbo.sp_tankWater_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_tankWater_all];
GO
--drop table tank_waters
/*
create table dbo.tankWaters (
    tankWaterId INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
    [name] VARCHAR(200) NULL,
    metrics INT NULL,
    capacity VARCHAR(200) NULL,
    device VARCHAR(200) NULL,
    created_At DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE()
)

CREATE TABLE dbo.tankWatersDetails (
    tankWatersDetailId INT NOT NULL IDENTITY(1,1) PRIMARY KEY,
    tankWaterId int not null,
    quantity VARCHAR(200) not  NULL,
    created_At DATETIME DEFAULT GETDATE(),

)

INSERT INTO dbo.tankWaters ([name],capacity,device) VALUES ('tinaco red','2500','esp32')
INSERT INTO dbo.tankWaters ([name],capacity,device) VALUES ('tinaco purificado','1100','esp32')
INSERT INTO dbo.tankWaters ([name],capacity,device) VALUES ('tinaco reserva 1','1100','esp32')
INSERT INTO dbo.tankWaters ([name],capacity,device) VALUES ('tinaco reserva 2','1100','esp32')
INSERT INTO dbo.tankWaters ([name],capacity,device) VALUES ('tinaco rechazo','500','esp32')

INSERT INTO dbo.tankWatersDetails (tankWaterId,quantity) VALUES (1,1500)
INSERT INTO dbo.tankWatersDetails (tankWaterId,quantity) VALUES (2,1100)
INSERT INTO dbo.tankWatersDetails (tankWaterId,quantity) VALUES (3,1000)
INSERT INTO dbo.tankWatersDetails (tankWaterId,quantity) VALUES (4,1000)
INSERT INTO dbo.tankWatersDetails (tankWaterId,quantity) VALUES (5,300)

SELECT 
    * 
FROM 
    dbo.tankWaters t
    INNER JOIN tankWatersDetails td on t.tankWaterId = td.tankWaterId

*/

-- Returns:
-- {
--   "waterTanks": [ { ... }, ... ]
-- }

CREATE PROC [dbo].[sp_tankWater_all]
AS
WITH Tanks AS (
  SELECT
      t.tankWaterId,
      t.[name],
      TRY_CONVERT(INT, t.capacity) AS capacityLiters,
      t.device
  FROM dbo.tankWaters t
)
SELECT
  JSON_QUERY((
    SELECT
      tk.tankWaterId,
      tk.[name],
      tk.capacityLiters,
      tk.device,

      -- current (latest reading per tank)
      JSON_QUERY((
        SELECT TOP (1)
          TRY_CONVERT(INT, td.quantity) AS quantityLiters,
          CAST(
            CASE
              WHEN TRY_CONVERT(FLOAT, tk.capacityLiters) = 0 THEN NULL
              ELSE ROUND(100.0 * TRY_CONVERT(FLOAT, td.quantity) / NULLIF(TRY_CONVERT(FLOAT, tk.capacityLiters), 0), 2)
            END
            AS DECIMAL(5,2)
          ) AS [percent],
          td.created_At AS sampledAt
        FROM dbo.tankWatersDetails td
        WHERE td.tankWaterId = tk.tankWaterId
        ORDER BY td.created_At DESC, td.tankWatersDetailId DESC
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
      )) AS [current],

      -- history (all readings per tank)
      JSON_QUERY((
        SELECT
          td.tankWatersDetailId,
          TRY_CONVERT(INT, td.quantity) AS quantityLiters,
          td.created_At AS createdAt,
          td.quantity as quantityLiter
        FROM dbo.tankWatersDetails td
        WHERE td.tankWaterId = tk.tankWaterId
        ORDER BY td.created_At DESC, td.tankWatersDetailId DESC
        FOR JSON PATH
      )) AS [history],

      -- empty object for future metadata (mirrors ticketMeta)
      JSON_QUERY('{}') AS tankMeta

    FROM Tanks tk
    FOR JSON PATH
  )) AS [waterTanks]
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
GO

-- dbo.sp_tankWaters
IF OBJECT_ID(N'dbo.sp_tankWaters', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_tankWaters];
GO

CREATE PROC dbo.sp_tankWaters
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile NVARCHAR(MAX) = '{
    "action": 1,
    "waterTanks": [
        {
        "tankWaterId": 1,
        "name": "Tinaco rojo",
        "metrics": [
            { "quantity": 1800 }
        ]
        },
        {
        "tankWaterId": 2,
        "name": "Purificado",
        "metrics": [
            { "quantity": 950 }
        ]
        },
        {
        "tankWaterId": null,
        "name": "Tinaco nuevo",
        "metrics": [
            { "quantity": 600 },
            { "quantity": 700 }
        ]
        }
    ]
    }'
    */

  DECLARE
      @Outputmessage NVARCHAR(MAX) = N'{
        "result": [
          { "value": "", "msg": "", "error": "" }
        ]
      }',
      @Error NVARCHAR(500) = N'',
      @globalAction INT;

  -- Global action (default = 1)
  SET @globalAction = TRY_CONVERT(INT, COALESCE(JSON_VALUE(@pjsonfile, '$.action'), '1'));

  BEGIN TRY
    BEGIN TRANSACTION;

    -- Parse items
    DECLARE @Items TABLE(
      itemIndex INT PRIMARY KEY,
      tankWaterId INT NULL,
      name NVARCHAR(200) NULL,
      metrics NVARCHAR(MAX) NULL,
      itemAction INT NULL
    );

    INSERT INTO @Items(itemIndex, tankWaterId, name, metrics, itemAction)
    SELECT
      wt.[key] AS itemIndex,
      TRY_CONVERT(INT, JSON_VALUE(wt.value, '$.tankWaterId')) AS tankWaterId,
      JSON_VALUE(wt.value, '$.name') AS [name],
      JSON_QUERY(wt.value, '$.metrics') AS metrics,
      TRY_CONVERT(INT, JSON_VALUE(wt.value, '$.action')) AS itemAction
    FROM OPENJSON(@pjsonfile, '$.waterTanks') wt;

    -- Counters
    DECLARE
      @idx INT, @id INT, @name NVARCHAR(200), @metrics NVARCHAR(MAX),
      @action INT,
      @detailsInserted INT = 0,
      @tanksUpserted INT = 0,
      @tanksUpdated INT = 0,
      @tanksDeleted INT = 0,
      @lastQty NVARCHAR(200),
      @lastQtyInt INT;

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
      SELECT itemIndex, tankWaterId, name, metrics, COALESCE(itemAction, @globalAction) AS effAction
      FROM @Items
      ORDER BY itemIndex;

    OPEN c;
    FETCH NEXT FROM c INTO @idx, @id, @name, @metrics, @action;

    WHILE @@FETCH_STATUS = 0
    BEGIN
      IF @action IN (1, 2)
      BEGIN
        -- Upsert/Update tank
        IF @id IS NULL
        BEGIN
          INSERT INTO dbo.tankWaters([name], created_At, updated_at)
          VALUES (NULLIF(LTRIM(RTRIM(@name)), ''), GETDATE(), GETDATE());
          SET @id = SCOPE_IDENTITY();
          SET @tanksUpserted += 1;
        END
        ELSE
        BEGIN
          IF NULLIF(LTRIM(RTRIM(@name)), '') IS NOT NULL
          BEGIN
            UPDATE dbo.tankWaters
               SET [name] = @name,
                   updated_at = GETDATE()
             WHERE tankWaterId = @id;
          END
          SET @tanksUpdated += 1;
        END

        -- Insert metrics as details + update header.metrics with last quantity
        IF @metrics IS NOT NULL AND @metrics <> 'null'
        BEGIN
          INSERT INTO dbo.tankWatersDetails(tankWaterId, quantity)
          SELECT @id, JSON_VALUE(m.value, '$.quantity')
          FROM OPENJSON(@metrics) m;

          SET @detailsInserted += @@ROWCOUNT;

          SELECT TOP (1)
            @lastQty = JSON_VALUE(m2.value, '$.quantity')
          FROM OPENJSON(@metrics) m2
          ORDER BY TRY_CONVERT(INT, m2.[key]) DESC;

          SET @lastQtyInt = TRY_CONVERT(INT, @lastQty);

          UPDATE dbo.tankWaters
             SET metrics = @lastQtyInt,
                 updated_at = GETDATE()
           WHERE tankWaterId = @id;
        END
      END
      ELSE IF @action = 3
      BEGIN
        IF @id IS NOT NULL
        BEGIN
          DELETE d FROM dbo.tankWatersDetails d WHERE d.tankWaterId = @id;
          DELETE t FROM dbo.tankWaters t WHERE t.tankWaterId = @id;
          SET @tanksDeleted += @@ROWCOUNT; -- counts deleted tanks
        END
      END
      ELSE
      BEGIN
        RAISERROR('Unsupported action in item %d. Use 1 (insert/upsert), 2 (update), or 3 (delete).', 16, 1, @idx);
      END

      FETCH NEXT FROM c INTO @idx, @id, @name, @metrics, @action;
    END

    CLOSE c;
    DEALLOCATE c;

    -- Message
    DECLARE @msg NVARCHAR(300) =
      CONCAT(
        'OK (upserted=', @tanksUpserted,
        ', updated=', @tanksUpdated,
        ', deleted=', @tanksDeleted,
        ', detailsInserted=', @detailsInserted, ')'
      );

    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @msg);

    -- ✅ FIXED: no single-arg CONCAT — cast the sum to NVARCHAR
    SET @Outputmessage = JSON_MODIFY(
      @Outputmessage,
      '$.result[0].value',
      CAST(@tanksUpserted + @tanksUpdated AS NVARCHAR(20))
    );

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @Error = ERROR_MESSAGE();
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
  END CATCH;

  SELECT
      JSON_VALUE(value, '$.value') AS [value],
      JSON_VALUE(value, '$.msg')   AS [msg],
      JSON_VALUE(value, '$.error') AS [error]
  FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_ticket
IF OBJECT_ID(N'dbo.sp_ticket', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_ticket];
GO

CREATE PROC [dbo].[sp_ticket]
(
    @pjsonfile NVARCHAR(MAX)
)
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE
        @action VARCHAR(50),
        @incomeId INT,
        @companyId INT,
        @fileName VARCHAR(500),
        @containerName VARCHAR(200),
        @receiptUrl VARCHAR(MAX),
        @phone VARCHAR(50),
        @response VARCHAR(MAX),
        @errorMessage VARCHAR(MAX);

    SELECT
        @action = JSON_VALUE(@pjsonfile,'$.ticket[0].action'),
        @incomeId = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.ticket[0].incomeId')),
        @companyId = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.ticket[0].companyId')),
        @fileName = JSON_VALUE(@pjsonfile,'$.ticket[0].fileName'),
        @containerName = JSON_VALUE(@pjsonfile,'$.ticket[0].containerName'),
        @receiptUrl = JSON_VALUE(@pjsonfile,'$.ticket[0].receiptUrl'),
        @phone = JSON_VALUE(@pjsonfile,'$.ticket[0].phone'),
        @response = JSON_VALUE(@pjsonfile,'$.ticket[0].response'),
        @errorMessage = JSON_VALUE(@pjsonfile,'$.ticket[0].errorMessage');

    ---------------------------------------------------------
    -- VALIDATE
    ---------------------------------------------------------
    IF @action = 'validate'
    BEGIN

        SELECT
            ticketId,
            incomeId,
            companyId,
            shortCode,
            receiptUrl,
            fileName,
            containerName,
            uploadAzure,
            uploadAzureDate,
            whatsappSent,
            whatsappSentDate,
            whatsappPhone,
            whatsappResponse,
            smsSent,
            smsSentDate,
            smsPhone,
            smsResponse,
            generationStatus,
            generatedDate,
            errorMessage,
            created_At,
            updated_At
        FROM dbo.tickets
        WHERE incomeId = @incomeId
        FOR JSON PATH, ROOT('tickets');

        RETURN;

    END

    ---------------------------------------------------------
    -- SAVE
    ---------------------------------------------------------
    IF @action = 'save'
    BEGIN

        IF EXISTS
        (
            SELECT 1
            FROM dbo.tickets
            WHERE incomeId = @incomeId
        )
        BEGIN

            UPDATE dbo.tickets
            SET
                companyId = @companyId,
                fileName = @fileName,
                containerName = @containerName,
                receiptUrl = @receiptUrl,
                uploadAzure = 1,
                uploadAzureDate = GETDATE(),
                updated_At = GETDATE()
            WHERE incomeId = @incomeId;

        END
        ELSE
        BEGIN

            INSERT INTO dbo.tickets
            (
                incomeId,
                companyId,
                fileName,
                containerName,
                receiptUrl,
                uploadAzure,
                uploadAzureDate,
                created_At,
                generationStatus
            )
            VALUES
            (
                @incomeId,
                @companyId,
                @fileName,
                @containerName,
                @receiptUrl,
                1,
                GETDATE(),
                GETDATE(),
                'PENDING'
            );

        END

        -----------------------------------------------------
        -- Generate shortCode if missing
        -----------------------------------------------------
        UPDATE dbo.tickets
        SET
            shortCode = CONCAT('T', incomeId)
        WHERE incomeId = @incomeId
          AND shortCode IS NULL;

        SELECT
            1 AS success,
            CONCAT('T', @incomeId) AS shortCode,
            'Ticket saved successfully' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- WHATSAPP
    ---------------------------------------------------------
    IF @action = 'whatsapp'
    BEGIN

        UPDATE dbo.tickets
        SET
            whatsappSent = 1,
            whatsappSentDate = GETDATE(),
            whatsappPhone = @phone,
            whatsappResponse = @response,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success,
            'Whatsapp updated' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- SMS
    ---------------------------------------------------------
    IF @action = 'sms'
    BEGIN

        UPDATE dbo.tickets
        SET
            smsSent = 1,
            smsSentDate = GETDATE(),
            smsPhone = @phone,
            smsResponse = @response,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success,
            'SMS updated' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- GENERATION START
    ---------------------------------------------------------
    IF @action = 'generate_start'
    BEGIN

        UPDATE dbo.tickets
        SET
            generationStatus = 'PROCESSING',
            errorMessage = NULL,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success,
            'Generation started' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- GENERATION SUCCESS
    ---------------------------------------------------------
    IF @action = 'generate_success'
    BEGIN

        UPDATE dbo.tickets
        SET
            generationStatus = 'SUCCESS',
            generatedDate = GETDATE(),
            errorMessage = NULL,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success,
            'Generation completed' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- GENERATION ERROR
    ---------------------------------------------------------
    IF @action = 'generate_error'
    BEGIN

        UPDATE dbo.tickets
        SET
            generationStatus = 'ERROR',
            errorMessage = @errorMessage,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success,
            'Generation error saved' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

END
GO

-- dbo.sp_ticket_redirect
IF OBJECT_ID(N'dbo.sp_ticket_redirect', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_ticket_redirect];
GO
CREATE PROC dbo.sp_ticket_redirect
(
    @pjsonfile NVARCHAR(MAX)
)
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE
        @Outputmessage NVARCHAR(MAX) = '',
        @action VARCHAR(50),
        @shortCode VARCHAR(20);

    SELECT
        @action = JSON_VALUE(@pjsonfile,'$.ticket[0].action'),
        @shortCode = JSON_VALUE(@pjsonfile,'$.ticket[0].shortCode');

    IF @action = 'redirect'
    BEGIN

        SET @Outputmessage =
        (
            SELECT TOP 1
                ticketId,
                incomeId,
                shortCode,
                receiptUrl
            FROM dbo.tickets
            WHERE shortCode = @shortCode
            FOR JSON PATH, ROOT('tickets')
        );

        SELECT @Outputmessage;

        RETURN;
    END

END
GO

-- dbo.sp_ticket_tracking
IF OBJECT_ID(N'dbo.sp_ticket_tracking', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_ticket_tracking];
GO

CREATE PROC [dbo].[sp_ticket_tracking]
(
    @pjsonfile NVARCHAR(MAX)
)
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE
        @action VARCHAR(50),
        @incomeId INT,
        @companyId INT,
        @fileName VARCHAR(500),
        @containerName VARCHAR(100),
        @receiptUrl VARCHAR(MAX),
        @phone VARCHAR(50);

    SELECT
        @action = JSON_VALUE(@pjsonfile,'$.ticket[0].action'),
        @incomeId = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.ticket[0].incomeId')),
        @companyId = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.ticket[0].companyId')),
        @fileName = JSON_VALUE(@pjsonfile,'$.ticket[0].fileName'),
        @containerName = JSON_VALUE(@pjsonfile,'$.ticket[0].containerName'),
        @receiptUrl = JSON_VALUE(@pjsonfile,'$.ticket[0].receiptUrl'),
        @phone = JSON_VALUE(@pjsonfile,'$.ticket[0].phone');

    ---------------------------------------------------------
    -- VALIDATE
    ---------------------------------------------------------
    IF @action = 'validate'
    BEGIN

        SELECT
            ticketId,
            incomeId,
            shortCode,
            fileName,
            receiptUrl,
            uploadAzure,
            whatsappSent,
            smsSent,
            printed,
            printedDate,
            generationStatus,
            generatedDate,
            errorMessage
        FROM dbo.tickets
        WHERE incomeId = @incomeId
        FOR JSON PATH, ROOT('tickets');

        RETURN;

    END

    ---------------------------------------------------------
    -- SAVE RECEIPT
    ---------------------------------------------------------
    IF @action = 'save'
    BEGIN

        IF EXISTS
        (
            SELECT 1
            FROM dbo.tickets
            WHERE incomeId = @incomeId
        )
        BEGIN

            UPDATE dbo.tickets
            SET
                companyId = @companyId,
                fileName = @fileName,
                containerName = @containerName,
                receiptUrl = @receiptUrl,
                uploadAzure = 1,
                uploadAzureDate = GETDATE(),
                updated_At = GETDATE()
            WHERE incomeId = @incomeId;

            -- Generate shortCode if missing
            UPDATE dbo.tickets
            SET shortCode = CONCAT('T', incomeId)
            WHERE incomeId = @incomeId
              AND shortCode IS NULL;

        END
        ELSE
        BEGIN

            INSERT INTO dbo.tickets
            (
                incomeId,
                companyId,
                fileName,
                containerName,
                receiptUrl,
                shortCode,
                uploadAzure,
                uploadAzureDate,
                created_At
            )
            VALUES
            (
                @incomeId,
                @companyId,
                @fileName,
                @containerName,
                @receiptUrl,
                CONCAT('T', @incomeId),
                1,
                GETDATE(),
                GETDATE()
            );

        END

        SELECT
            1 AS success,
            'Receipt saved' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- WHATSAPP SUCCESS
    ---------------------------------------------------------
    IF @action = 'whatsapp'
    BEGIN

        UPDATE dbo.tickets
        SET
            whatsappSent = 1,
            whatsappSentDate = GETDATE(),
            whatsappPhone = @phone,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- SMS SUCCESS
    ---------------------------------------------------------
    IF @action = 'sms'
    BEGIN

        UPDATE dbo.tickets
        SET
            smsSent = 1,
            smsSentDate = GETDATE(),
            smsPhone = @phone,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

END
GO

-- dbo.sp_tickets_one
IF OBJECT_ID(N'dbo.sp_tickets_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_tickets_one];
GO

CREATE   PROC [dbo].[sp_tickets_one]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @incomeId INT =
    TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.tickets[0].income'));

  IF @incomeId IS NULL
  BEGIN
    RAISERROR('Invalid input: $.tickets[0].income is required.', 16, 1);
    RETURN;
  END;

  ------------------------------------------------------------------
  -- Header
  ------------------------------------------------------------------
  DECLARE
    @paymentMethod  NVARCHAR(50),
    @paymentDate    DATETIME,
    @userId         INT,
    @clientId       INT,
    @companyId      INT,
    @incomeTotal    DECIMAL(10,2),
    @cashPaid       DECIMAL(10,2),
    @cashReturn     DECIMAL(10,2);

  SELECT
    @paymentMethod = i.paymentMethod,
    @paymentDate   = DATEADD(HOUR, -7, i.paymentDate),  -- ✅ FIX: UTC -> Hermosillo (UTC-7)
    @userId        = i.userId,
    @clientId      = i.clientId,
    @companyId     = i.companyId,
    @incomeTotal   = i.total,
    @cashPaid      = i.cashPaid,
    @cashReturn    = i.cashReturn
  FROM dbo.income i
  WHERE i.incomeId = @incomeId;

  IF @paymentMethod IS NULL
  BEGIN
    RAISERROR('incomeId not found.', 16, 1);
    RETURN;
  END;

  ------------------------------------------------------------------
  -- Build product lines (NEW: carry piecesJson)
  ------------------------------------------------------------------
  ;WITH P AS (
    SELECT
      id.incomeDetailId,
      id.productId,
      p.name AS productName,
      id.piecesJson,

      -- Base product price = 0 (service price defined by options)
      CAST(0 AS DECIMAL(10,2)) AS unitPrice,

      CAST(ISNULL(id.quantity, 1) AS INT) AS quantity,

      -- Options total (sum(choice price * option qty))
      CAST(ISNULL((
        SELECT SUM(CAST(c.price AS DECIMAL(10,2)) * ISNULL(ido.quantity, 1))
        FROM dbo.incomeDetailOptions ido
        JOIN dbo.productOptionChoices c
          ON c.productOptionChoiceId = ido.productOptionChoiceId
        WHERE ido.incomeDetailId = id.incomeDetailId
      ), 0) AS DECIMAL(10,2)) AS optionsTotal
    FROM dbo.incomeDetails id
    JOIN dbo.products p
      ON p.productId = id.productId
    WHERE id.incomeId = @incomeId
  )
  SELECT
    incomeDetailId,
    productId,
    productName,
    piecesJson,
    unitPrice,
    quantity,
    optionsTotal,
    CAST((unitPrice * quantity) + optionsTotal AS DECIMAL(10,2)) AS lineSubtotal
  INTO #TicketProducts
  FROM P;

  ------------------------------------------------------------------
  -- Totals
  ------------------------------------------------------------------
  DECLARE
    @subtotal DECIMAL(10,2),
    @iva      DECIMAL(10,2),
    @total    DECIMAL(10,2);

  SET @subtotal = ISNULL((SELECT SUM(lineSubtotal) FROM #TicketProducts), 0);

  -- Prefer stored income total if present
  SET @total = COALESCE(@incomeTotal, @subtotal);

  -- IVA derived from stored total - subtotal (if included)
  SET @iva = CASE
    WHEN @total >= @subtotal THEN ROUND(@total - @subtotal, 2)
    ELSE 0
  END;

  ------------------------------------------------------------------
  -- Ticket meta from tickets table (optional)
  ------------------------------------------------------------------
  DECLARE
    @ticketId INT,
    @ticketNumber VARCHAR(50),
    @printed BIT,
    @printedDate DATETIME,
    @amountReceived DECIMAL(10,2),
    @change DECIMAL(10,2);

  SELECT TOP (1)
    @ticketId       = t.ticketId,
    @ticketNumber   = t.ticketNumber,
    @printed        = t.printed,
    @printedDate    = t.printedDate,
    @amountReceived = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(t.ticketData, '$.amountReceived')),
    @change         = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(t.ticketData, '$.change'))
  FROM dbo.tickets t
  WHERE TRY_CONVERT(INT, JSON_VALUE(t.ticketData, '$.incomeId')) = @incomeId
  ORDER BY t.created_At DESC;

  -- If tickets table doesn't have amountReceived/change, fallback to income cash fields
  IF @amountReceived IS NULL
    SET @amountReceived = @cashPaid;

  IF @change IS NULL
    SET @change = @cashReturn;

  IF @amountReceived IS NOT NULL AND @change IS NULL
    SET @change = @amountReceived - @total;

  ------------------------------------------------------------------
  -- Final JSON
  ------------------------------------------------------------------
  SELECT
    @incomeId      AS incomeId,
    @companyId     AS companyId,
    @paymentDate   AS paymentDate,
    @paymentMethod AS paymentMethod,

    JSON_QUERY((
      SELECT
        c.clientId,
        CONCAT(c.first_name, ' ', c.last_name) AS [name],
        c.cellphone,
        c.email
      FROM dbo.clients c
      WHERE c.clientId = @clientId
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS client,

    JSON_QUERY((
      SELECT
        u.userId,
        u.name,
        u.email
      FROM dbo.users u
      WHERE u.userId = @userId
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS [user],

    JSON_QUERY((
      SELECT
        tp.incomeDetailId,
        tp.productId,
        tp.productName AS name,
        tp.unitPrice,
        tp.lineSubtotal AS subtotal,
        tp.quantity,

        -- NEW: pieces object for Servicio Completo (or any product that sends it)
        CASE
          WHEN tp.piecesJson IS NULL THEN NULL
          ELSE JSON_QUERY(tp.piecesJson)
        END AS pieces,

        JSON_QUERY(ISNULL((
          SELECT
            o.productOptionId,
            o.name AS optionName,
            c.productOptionChoiceId,
            c.name AS choiceName,
            CAST(c.price AS DECIMAL(10,2)) AS price,
            ISNULL(ido.quantity, 1) AS quantity
          FROM dbo.incomeDetailOptions ido
          JOIN dbo.productOptions o
            ON o.productOptionId = ido.productOptionId
          JOIN dbo.productOptionChoices c
            ON c.productOptionChoiceId = ido.productOptionChoiceId
          WHERE ido.incomeDetailId = tp.incomeDetailId
          FOR JSON PATH
        ), '[]')) AS options
      FROM #TicketProducts tp
      FOR JSON PATH
    )) AS products,

    JSON_QUERY((
      SELECT
        @subtotal       AS subtotal,
        @iva            AS iva,
        @total          AS total,
        @amountReceived AS amountReceived,
        @change         AS [change]
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS totals,

    JSON_QUERY((
      SELECT
        @ticketId     AS ticketId,
        @ticketNumber AS ticketNumber,
        @printed      AS printed,
        @printedDate  AS printedDate
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS ticketMeta

  FOR JSON PATH, ROOT('tickets');

  DROP TABLE IF EXISTS #TicketProducts;
END
GO

-- dbo.sp_transfers
IF OBJECT_ID(N'dbo.sp_transfers', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_transfers];
GO

CREATE PROCEDURE [dbo].[sp_transfers]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action          INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].action')
        DECLARE @transferId      INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].transferId')
        DECLARE @companyId       INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].companyId')
        DECLARE @toClientId      INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].toClientId')
        DECLARE @toBankAccountId INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].toBankAccountId')
        DECLARE @amountMXN       DECIMAL(12,2)  = JSON_VALUE(@pjsonfile, '$.transfers[0].amountMXN')
        DECLARE @purpose         NVARCHAR(30)   = JSON_VALUE(@pjsonfile, '$.transfers[0].purpose')
        DECLARE @loanId          INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].loanId')
        DECLARE @provider        NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.transfers[0].provider')
        DECLARE @providerRef     NVARCHAR(100)  = JSON_VALUE(@pjsonfile, '$.transfers[0].providerRef')
        DECLARE @cepUrl          NVARCHAR(2048) = JSON_VALUE(@pjsonfile, '$.transfers[0].cepUrl')
        DECLARE @status          NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.transfers[0].status')
        DECLARE @failureReason   NVARCHAR(500)  = JSON_VALUE(@pjsonfile, '$.transfers[0].failureReason')
        DECLARE @idempotencyKey  NVARCHAR(64)   = JSON_VALUE(@pjsonfile, '$.transfers[0].idempotencyKey')

        IF @action = 1 -- CREATE (idempotent: same key returns the original)
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[transfers]
                       WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey)
            BEGIN
                SELECT (SELECT TOP 1 transferId, toClientId, amountMXN, purpose, provider,
                               providerRef, cepUrl, status, 'true' AS replayed,
                               CONVERT(NVARCHAR, created_At, 127) AS created_At
                        FROM [dbo].[transfers]
                        WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
                RETURN
            END

            INSERT INTO [dbo].[transfers]
                (companyId, toClientId, toBankAccountId, amountMXN, purpose, loanId,
                 provider, idempotencyKey, status)
            VALUES
                (@companyId, @toClientId, @toBankAccountId, @amountMXN, @purpose, @loanId,
                 ISNULL(@provider, 'stp'), @idempotencyKey, 'pending')

            SELECT (SELECT TOP 1 transferId, companyId, toClientId, toBankAccountId,
                           amountMXN, purpose, provider, status, idempotencyKey,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[transfers]
                    WHERE transferId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (provider result / webhook advance)
        BEGIN
            UPDATE [dbo].[transfers]
            SET status        = ISNULL(@status, status),
                providerRef   = ISNULL(@providerRef, providerRef),
                cepUrl        = ISNULL(@cepUrl, cepUrl),
                failureReason = ISNULL(@failureReason, failureReason),
                settledAt     = CASE WHEN @status = 'settled' THEN GETUTCDATE() ELSE settledAt END,
                updated_at    = GETUTCDATE()
            WHERE transferId = @transferId AND companyId = @companyId

            SELECT (SELECT TOP 1 transferId, toClientId, amountMXN, purpose, provider,
                           providerRef, cepUrl, status, failureReason,
                           CONVERT(NVARCHAR, settledAt, 127) AS settledAt
                    FROM [dbo].[transfers]
                    WHERE transferId = @transferId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE
            -- No action 3: money-movement records are never deleted.
            SELECT '{"error":"Transfers son registros de auditoría — sin delete. Acciones válidas: 1 crear, 2 actualizar."}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_transfers_all
IF OBJECT_ID(N'dbo.sp_transfers_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_transfers_all];
GO
CREATE PROCEDURE [dbo].[sp_transfers_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId  INT           = JSON_VALUE(@pjsonfile, '$.transfers[0].companyId')
    DECLARE @toClientId INT           = JSON_VALUE(@pjsonfile, '$.transfers[0].toClientId')
    DECLARE @status     NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.transfers[0].status')
    DECLARE @purpose    NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.transfers[0].purpose')

    SELECT ISNULL(
        (SELECT TOP 200 transferId, companyId, toClientId, toBankAccountId, amountMXN,
                purpose, loanId, provider, providerRef, cepUrl, status, failureReason,
                CONVERT(NVARCHAR, settledAt, 127)  AS settledAt,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[transfers]
         WHERE companyId = @companyId
           AND (@toClientId IS NULL OR toClientId = @toClientId)
           AND (@status     IS NULL OR status     = @status)
           AND (@purpose    IS NULL OR purpose    = @purpose)
         ORDER BY created_At DESC
         FOR JSON PATH, ROOT('transfers')),
        '{"transfers":[]}'
    ) AS [jsonResult]
END
GO

-- dbo.sp_transfers_one
IF OBJECT_ID(N'dbo.sp_transfers_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_transfers_one];
GO
CREATE PROCEDURE [dbo].[sp_transfers_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId      INT          = JSON_VALUE(@pjsonfile, '$.transfers[0].companyId')
    DECLARE @transferId     INT          = JSON_VALUE(@pjsonfile, '$.transfers[0].transferId')
    DECLARE @idempotencyKey NVARCHAR(64) = JSON_VALUE(@pjsonfile, '$.transfers[0].idempotencyKey')

    SELECT ISNULL(
        (SELECT TOP 1 transferId, companyId, toClientId, toBankAccountId, amountMXN,
                purpose, loanId, provider, providerRef, cepUrl, status, failureReason,
                idempotencyKey,
                CONVERT(NVARCHAR, settledAt, 127)  AS settledAt,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[transfers]
         WHERE (@transferId IS NOT NULL AND transferId = @transferId)
            OR (@idempotencyKey IS NOT NULL AND companyId = @companyId AND idempotencyKey = @idempotencyKey)
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO

-- dbo.sp_unifiedProducts
IF OBJECT_ID(N'dbo.sp_unifiedProducts', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_unifiedProducts];
GO

CREATE PROC [dbo].[sp_unifiedProducts] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- TEST PAYLOAD
    DECLARE @pjsonfile VARCHAR(MAX) = '{
      "unifiedProducts": [
        {
          "brand": "Apple",
          "model": "A2890",
          "title": "iPhone 15",
          "ean_upc": "1234567890123",
          "attributesJson": { "color": "black" },
          "action": "1"
        }
      ]
    }';
    */

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '
        {
          "result": [
            { "value": "", "msg": "", "error": "" }
          ]
        }',
        @Error NVARCHAR(500) = '',
        @action INT;

    -- Detect action
    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.unifiedProducts')
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        /* =========================
           ACTION = 1  (INSERT)
        ========================= */
        IF @action = 1
        BEGIN
            DECLARE @Inserted TABLE (unifiedProductId BIGINT);

            INSERT INTO dbo.unifiedProducts
                (brand, model, title, ean_upc, attributesJson)
            OUTPUT INSERTED.unifiedProductId
                INTO @Inserted(unifiedProductId)
            SELECT
                JSON_VALUE(value, '$.brand'),
                JSON_VALUE(value, '$.model'),
                JSON_VALUE(value, '$.title'),
                JSON_VALUE(value, '$.ean_upc'),
                JSON_QUERY(value, '$.attributesJson')
            FROM OPENJSON(@pjsonfile, '$.unifiedProducts');

            DECLARE @newId BIGINT = (SELECT TOP 1 unifiedProductId FROM @Inserted);

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(50), @newId));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END

        /* =========================
           ACTION = 2  (UPDATE)
        ========================= */
        ELSE IF @action = 2
        BEGIN
            UPDATE p
            SET
                p.brand = JSON_VALUE(j.value, '$.brand'),
                p.model = JSON_VALUE(j.value, '$.model'),
                p.title = JSON_VALUE(j.value, '$.title'),
                p.ean_upc = JSON_VALUE(j.value, '$.ean_upc'),
                p.attributesJson = JSON_QUERY(j.value, '$.attributesJson'),
                p.updatedAt = SYSUTCDATETIME()
            FROM dbo.unifiedProducts p
            INNER JOIN OPENJSON(@pjsonfile, '$.unifiedProducts') j
                ON p.unifiedProductId = TRY_CONVERT(BIGINT, JSON_VALUE(j.value, '$.unifiedProductId'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END

        /* =========================
           ACTION = 3  (DELETE)
        ========================= */
        ELSE IF @action = 3
        BEGIN
            DELETE FROM dbo.unifiedProducts
            WHERE unifiedProductId IN (
                SELECT TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.unifiedProductId'))
                FROM OPENJSON(@pjsonfile, '$.unifiedProducts')
            );

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH;

    -- Final response
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg')   AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_upgraddiagrams
IF OBJECT_ID(N'dbo.sp_upgraddiagrams', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_upgraddiagrams];
GO

	CREATE PROCEDURE dbo.sp_upgraddiagrams
	AS
	BEGIN
		IF OBJECT_ID(N'dbo.sysdiagrams') IS NOT NULL
			return 0;
	
		CREATE TABLE dbo.sysdiagrams
		(
			name sysname NOT NULL,
			principal_id int NOT NULL,	-- we may change it to varbinary(85)
			diagram_id int PRIMARY KEY IDENTITY,
			version int,
	
			definition varbinary(max)
			CONSTRAINT UK_principal_name UNIQUE
			(
				principal_id,
				name
			)
		);


		/* Add this if we need to have some form of extended properties for diagrams */
		/*
		IF OBJECT_ID(N'dbo.sysdiagram_properties') IS NULL
		BEGIN
			CREATE TABLE dbo.sysdiagram_properties
			(
				diagram_id int,
				name sysname,
				value varbinary(max) NOT NULL
			)
		END
		*/

		IF OBJECT_ID(N'dbo.dtproperties') IS NOT NULL
		begin
			insert into dbo.sysdiagrams
			(
				[name],
				[principal_id],
				[version],
				[definition]
			)
			select	 
				convert(sysname, dgnm.[uvalue]),
				DATABASE_PRINCIPAL_ID(N'dbo'),			-- will change to the sid of sa
				0,							-- zero for old format, dgdef.[version],
				dgdef.[lvalue]
			from dbo.[dtproperties] dgnm
				inner join dbo.[dtproperties] dggd on dggd.[property] = 'DtgSchemaGUID' and dggd.[objectid] = dgnm.[objectid]	
				inner join dbo.[dtproperties] dgdef on dgdef.[property] = 'DtgSchemaDATA' and dgdef.[objectid] = dgnm.[objectid]
				
			where dgnm.[property] = 'DtgSchemaNAME' and dggd.[uvalue] like N'_EA3E6268-D998-11CE-9454-00AA00A3F36E_' 
			return 2;
		end
		return 1;
	END
GO

-- dbo.sp_users
IF OBJECT_ID(N'dbo.sp_users', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_users];
GO
CREATE   PROC [dbo].[sp_users] (@pjsonfile VARCHAR(MAX))
-- action 1 → INSERT
-- action 2 → UPDATE (also upserts dbo.userCompanies when companyId is provided)
-- action 3 → DELETE
AS
SET NOCOUNT ON

DECLARE @email            VARCHAR(100)
       ,@cellphone        VARCHAR(20)
       ,@user_id          INT
       ,@action           INT
       ,@companyId        INT
       ,@branchId         INT
       ,@roleCode         VARCHAR(50)
       ,@roleId           INT
       ,@clientId         INT
       ,@appProfile       VARCHAR(20)
       ,@enabledModules   NVARCHAR(MAX)
       ,@identityVerified BIT
       ,@imageUrl         NVARCHAR(500)
       ,@Error            VARCHAR(500) = ''

DECLARE @Outputmessage VARCHAR(MAX) = '{
  "result": [{ "value": "", "msg": "", "error": "" }]
}'

SET @action = (SELECT JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.users'))

-- ── INSERT ────────────────────────────────────────────────────────────────
IF @action = 1
BEGIN
    BEGIN TRY
        DECLARE @newName  VARCHAR(100) =
            (SELECT JSON_VALUE(value, '$.name') FROM OPENJSON(@pjsonfile, '$.users'))
        DECLARE @newEmail VARCHAR(100) =
            NULLIF((SELECT JSON_VALUE(value, '$.email') FROM OPENJSON(@pjsonfile, '$.users')), '')

        -- Username must be unique — belt-and-suspenders alongside the
        -- dedicated /check_username lookup the frontend calls before submit.
        IF EXISTS (SELECT 1 FROM dbo.users WHERE [name] = @newName)
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'El nombre de usuario ya existe.')
        END
        -- Email must be unique too — checkContact only catches this when a
        -- dbo.clients row also exists for that email (e.g. POS-only or
        -- email-only "loans" accounts have no client row, so it wouldn't
        -- have been caught upstream).
        ELSE IF @newEmail IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.users WHERE email = @newEmail)
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'El email ya está registrado.')
        END
        ELSE
        BEGIN
            BEGIN TRAN
                -- clientId links this login to an existing dbo.clients row
                -- (set when an already-known client — found via checkContact,
                -- no account yet — is claiming their account) so the two
                -- records aren't left disconnected.
                INSERT INTO [dbo].[users] ([name], email, cellphone, [password], created_at, clientId)
                SELECT
                    JSON_VALUE(value, '$.name')      AS [name],
                    NULLIF(JSON_VALUE(value, '$.email'), '')      AS email,
                    NULLIF(JSON_VALUE(value, '$.cellphone'), '')  AS cellphone,
                    JSON_VALUE(value, '$.password')  AS [password],
                    GETDATE(),
                    TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId'))  AS clientId
                FROM OPENJSON(@pjsonfile, '$.users')
            COMMIT TRAN

            SET @user_id = SCOPE_IDENTITY()
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@user_id AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'Inserted Successfully');
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK
        SET @Error = ERROR_MESSAGE()
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   @Error)
    END CATCH
END

-- ── UPDATE ────────────────────────────────────────────────────────────────
IF @action = 2
BEGIN
    BEGIN TRY
        SELECT
            @user_id          = JSON_VALUE(value, '$.user_id'),
            @email            = NULLIF(JSON_VALUE(value, '$.email'), ''),
            @cellphone        = NULLIF(JSON_VALUE(value, '$.cellphone'), ''),
            @companyId        = NULLIF(JSON_VALUE(value, '$.companyId'), ''),
            @branchId         = NULLIF(JSON_VALUE(value, '$.branchId'), ''),
            @roleCode         = NULLIF(JSON_VALUE(value, '$.roleCode'), ''),
            @clientId         = TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
            -- Registration wizard steps 2 & 3 (Perfil / Verificar) — previously
            -- sent by the frontend but silently dropped, so a returning
            -- contact could never resume partway. See sp_checkContact v5.
            @appProfile       = NULLIF(JSON_VALUE(value, '$.appProfile'), ''),
            @enabledModules   = JSON_QUERY(value, '$.enabledModules'),
            @identityVerified = TRY_CONVERT(BIT, JSON_VALUE(value, '$.identityVerified')),
            -- Profile avatar (e.g. the verified 'front' liveness capture). Written
            -- to dbo.users.imageUrl, which /one_users reads back as the avatar.
            @imageUrl         = NULLIF(JSON_VALUE(value, '$.imageUrl'), '')
        FROM OPENJSON(@pjsonfile, '$.users')

        -- Allow the caller to target the row by clientId when it doesn't hold a
        -- user_id (agent-assisted KYC only knows the client). Resolves to the
        -- login linked to that client so avatar updates work in both flows.
        IF (@user_id IS NULL OR @user_id = 0) AND @clientId IS NOT NULL
            SET @user_id = (SELECT TOP 1 [userId] FROM dbo.users WHERE clientId = @clientId ORDER BY [userId])

        BEGIN TRAN
            -- clientId mirrors the INSERT path: link/re-link this login to a
            -- dbo.clients row after creation, not just at signup time.
            -- identityVerified only ever moves 0→1 here — an update call
            -- that doesn't touch verification (e.g. saving Perfil) sends no
            -- identityVerified, so @identityVerified is NULL and the
            -- existing value is left alone rather than reset to 0.
            UPDATE [dbo].[users] SET
                email            = ISNULL(@email,     email),
                cellphone        = ISNULL(@cellphone, cellphone),
                clientId         = ISNULL(@clientId,  clientId),
                appProfile       = ISNULL(@appProfile,     appProfile),
                enabledModules   = ISNULL(@enabledModules, enabledModules),
                identityVerified = CASE WHEN @identityVerified = 1 THEN 1 ELSE identityVerified END,
                imageUrl         = ISNULL(@imageUrl, imageUrl),
                [name]    = ISNULL(NULLIF(JSON_VALUE((SELECT value FROM OPENJSON(@pjsonfile,'$.users')), '$.name'), ''), [name]),
                [password]= ISNULL(NULLIF(JSON_VALUE((SELECT value FROM OPENJSON(@pjsonfile,'$.users')), '$.password'), ''), [password])
            WHERE [userId] = @user_id

            -- Company/branch/role selection (step "Acceso") → upsert userCompanies.
            -- sp_login reads role/company/branch from here, not from dbo.users.
            IF @companyId IS NOT NULL
            BEGIN
                SELECT @roleId = roleId FROM dbo.roles WHERE code = @roleCode AND active = 1

                IF EXISTS (SELECT 1 FROM dbo.userCompanies WHERE userId = @user_id AND companyId = @companyId)
                BEGIN
                    UPDATE dbo.userCompanies SET
                        branchId   = ISNULL(@branchId, branchId),
                        roleId     = ISNULL(@roleId, roleId),
                        roleName   = ISNULL(@roleCode, roleName),
                        updated_at = GETDATE()
                    WHERE userId = @user_id AND companyId = @companyId
                END
                ELSE
                BEGIN
                    INSERT INTO dbo.userCompanies
                        (userId, companyId, branchId, isDefault, roleName, active, created_at, roleId)
                    VALUES
                        (@user_id, @companyId, @branchId,
                         CASE WHEN EXISTS (SELECT 1 FROM dbo.userCompanies WHERE userId = @user_id) THEN 0 ELSE 1 END,
                         @roleCode, 1, GETDATE(), @roleId)
                END
            END
        COMMIT TRAN

        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@user_id AS VARCHAR(20)));
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'Updated Successfully');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK
        SET @Error = ERROR_MESSAGE()
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   @Error)
    END CATCH
END

SELECT
    JSON_VALUE(value, '$.value') AS [value],
    JSON_VALUE(value, '$.msg')   AS [msg],
    JSON_VALUE(value, '$.error') AS [error]
FROM OPENJSON(@Outputmessage, '$.result')
GO

-- dbo.sp_users_all
IF OBJECT_ID(N'dbo.sp_users_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_users_all];
GO

CREATE PROC [dbo].[sp_users_all]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        userId,
        ISNULL(companyId, 0) AS companyId,
        [name],
        [email],
        [password],
        created_at,
        active
    FROM dbo.users
    FOR JSON AUTO, ROOT('users');

END
GO

-- dbo.sp_users_one
IF OBJECT_ID(N'dbo.sp_users_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_users_one];
GO

CREATE PROC [dbo].[sp_users_one]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  /*
  DECLARE @pjsonfile NVARCHAR(MAX) = N'{
    "users":[{"userId":"1"}]
  }';
  */

  DECLARE @userId INT;

  SET @userId = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.users[0].userId'));

  IF @userId IS NULL
  BEGIN
    RAISERROR('Invalid input: $.users[0].userId is required.', 16, 1);
    RETURN;
  END;

  DECLARE @baseUrl NVARCHAR(300) = N'https://smartloansbackend.azurewebsites.net';

  SELECT
    u.userId,
    ISNULL(u.companyId, 0) AS companyId,
    u.name,
    u.email,
    u.password,
    u.created_at,
    u.active,

    COALESCE(u.qrCode, CONCAT('USER:', u.userId)) AS qrCode,

    CONCAT(@baseUrl, N'/users/', u.userId, N'/qr.png') AS qrImageUrl,

    u.[image],
    u.imageUrl

  FROM dbo.users u
  WHERE u.userId = @userId
  FOR JSON PATH, ROOT('users');
END
GO

-- dbo.sp_users_one_email
IF OBJECT_ID(N'dbo.sp_users_one_email', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_users_one_email];
GO

CREATE PROC [dbo].[sp_users_one_email]
(
    @pjsonfile VARCHAR(MAX)
)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
      "users": [
        {
          "email": "usuario@correo.com"
        }
      ]
    }';
    */

    DECLARE @Email VARCHAR(255);

    SET @Email =
    (
        SELECT TOP 1
            JSON_VALUE(value, '$.email')
        FROM OPENJSON(@pjsonfile, '$.users')
    );

    SELECT
        userId,
        ISNULL(companyId, 0) AS companyId,
        [name],
        email,
        [password],
        created_at,
        active
    FROM dbo.users
    WHERE email = @Email
    FOR JSON AUTO, ROOT('users');

END
GO

-- dbo.sp_utilityRates
IF OBJECT_ID(N'dbo.sp_utilityRates', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_utilityRates];
GO
CREATE PROCEDURE [dbo].[sp_utilityRates]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         NVARCHAR(10)  = JSON_VALUE(@pjsonfile,'$.rates[0].action')
        DECLARE @companyId      INT           = JSON_VALUE(@pjsonfile,'$.rates[0].companyId')
        DECLARE @elec           DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.rates[0].electricityPerKwh')
        DECLARE @water          DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.rates[0].waterPerLiter')
        DECLARE @det            DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.rates[0].detergentPerGram')
        DECLARE @labor          DECIMAL(10,2) = JSON_VALUE(@pjsonfile,'$.rates[0].laborPerHour')
        DECLARE @overhead       DECIMAL(5,2)  = JSON_VALUE(@pjsonfile,'$.rates[0].overheadPct')
        DECLARE @margin         DECIMAL(5,2)  = JSON_VALUE(@pjsonfile,'$.rates[0].targetMarginPct')
        DECLARE @effFrom        DATE          = ISNULL(JSON_VALUE(@pjsonfile,'$.rates[0].effectiveFrom'), CAST(GETUTCDATE() AS DATE))

        IF @action = 'upsert'
        BEGIN
            MERGE [dbo].[utilityRates] AS t
            USING (SELECT @companyId AS companyId, @effFrom AS effectiveFrom) AS s
                ON t.companyId=s.companyId AND t.effectiveFrom=s.effectiveFrom
            WHEN MATCHED THEN UPDATE SET
                electricityPerKwh=ISNULL(@elec,t.electricityPerKwh),
                waterPerLiter=ISNULL(@water,t.waterPerLiter),
                detergentPerGram=ISNULL(@det,t.detergentPerGram),
                laborPerHour=ISNULL(@labor,t.laborPerHour),
                overheadPct=ISNULL(@overhead,t.overheadPct),
                targetMarginPct=ISNULL(@margin,t.targetMarginPct)
            WHEN NOT MATCHED THEN INSERT
                (companyId,electricityPerKwh,waterPerLiter,detergentPerGram,laborPerHour,overheadPct,targetMarginPct,effectiveFrom)
            VALUES (@companyId,ISNULL(@elec,3.20),ISNULL(@water,0.015),ISNULL(@det,0.08),
                    ISNULL(@labor,80),ISNULL(@overhead,15),ISNULL(@margin,40),@effFrom);

            SELECT (SELECT TOP 1 electricityPerKwh,waterPerLiter,detergentPerGram,
                           laborPerHour,overheadPct,targetMarginPct,
                           CONVERT(NVARCHAR,effectiveFrom,23) AS effectiveFrom
                    FROM [dbo].[utilityRates] WHERE companyId=@companyId
                    ORDER BY effectiveFrom DESC
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 rateId, electricityPerKwh, waterPerLiter, detergentPerGram,
                        laborPerHour, overheadPct, targetMarginPct,
                        CONVERT(NVARCHAR, effectiveFrom, 23) AS effectiveFrom
                 FROM [dbo].[utilityRates]
                 WHERE companyId=@companyId AND effectiveFrom <= CAST(GETUTCDATE() AS DATE)
                 ORDER BY effectiveFrom DESC
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{"electricityPerKwh":3.20,"waterPerLiter":0.015,"detergentPerGram":0.08,"laborPerHour":80,"overheadPct":15,"targetMarginPct":40}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_vending
IF OBJECT_ID(N'dbo.sp_vending', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_vending];
GO

create PROC [dbo].[sp_vending] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Obtener acción del JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.vending'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- INSERT
            INSERT INTO [dbo].[vending] ([ingreso])
            SELECT
                JSON_VALUE(value, '$.ingreso')
            FROM OPENJSON(@pjsonfile, '$.vending');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- UPDATE
            UPDATE v
            SET 
                v.[ingreso] = JSON_VALUE(j.value, '$.ingreso')
            FROM 
                [dbo].[vending] v
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.vending') j
                ON v.[id] = JSON_VALUE(j.value, '$.id');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- DELETE
            DELETE FROM [dbo].[vending]
            WHERE [id] IN (SELECT JSON_VALUE(value, '$.id') FROM OPENJSON(@pjsonfile, '$.vending'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Retornar el resultado
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_vending_all
IF OBJECT_ID(N'dbo.sp_vending_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_vending_all];
GO
CREATE PROC [dbo].[sp_vending_all]
AS
SET NOCOUNT ON

BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[vending])
    BEGIN
        -- Si hay datos, devuélvelos normalmente en JSON
        SELECT ingreso
        FROM [dbo].[vending]
        FOR JSON AUTO, ROOT('vending');
    END
    ELSE
    BEGIN
        -- Si no hay datos, regresa un JSON vacío con la raíz 'vending'
        SELECT '[]' AS [vending]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO

-- dbo.sp_walletTransactions
IF OBJECT_ID(N'dbo.sp_walletTransactions', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_walletTransactions];
GO

CREATE PROCEDURE [dbo].[sp_walletTransactions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         INT            = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].action')
        DECLARE @companyId      INT            = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].companyId')
        DECLARE @clientId       INT            = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].clientId')
        DECLARE @entryType      NVARCHAR(30)   = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].entryType')
        DECLARE @direction      CHAR(1)        = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].direction')
        DECLARE @amountMXN      DECIMAL(12,2)  = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].amountMXN')
        DECLARE @referenceType  NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].referenceType')
        DECLARE @referenceId    INT            = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].referenceId')
        DECLARE @idempotencyKey NVARCHAR(64)   = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].idempotencyKey')
        DECLARE @note           NVARCHAR(255)  = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].note')

        IF @action = 1 -- INSERT (the only mutation this ledger allows)
        BEGIN
            -- Idempotent replay: same key returns the original entry, no double post.
            IF EXISTS (SELECT 1 FROM [dbo].[walletTransactions]
                       WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey)
            BEGIN
                SELECT (SELECT TOP 1 entryId, companyId, clientId, entryType, direction,
                               amountMXN, balanceAfter, idempotencyKey, note,
                               'true' AS replayed,
                               CONVERT(NVARCHAR, created_At, 127) AS created_At
                        FROM [dbo].[walletTransactions]
                        WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
                RETURN
            END

            BEGIN TRANSACTION;

            -- CAPITAL_* (CAPITAL_DECLARED/CAPITAL_COMMITTED/CAPITAL_UNDECLARED)
            -- describe a lender's declared-capital STATE, never real money —
            -- see MD/PR1B_CAPITAL_VOCABULARY_MIGRATION.md. They must never
            -- join the real-money running balance: excluded here from the
            -- @prev lookup (so a real DEPOSIT/WITHDRAWAL after one still
            -- chains off the last REAL balance, not a virtual one) and given
            -- balanceAfter = NULL (never a candidate tail row for anyone's
            -- balance query) with no overdraft check (declaring/undeclaring
            -- virtual capital can never be blocked by real available funds).
            DECLARE @isCapitalEntry BIT = CASE WHEN @entryType IN
                ('CAPITAL_DECLARED','CAPITAL_COMMITTED','CAPITAL_UNDECLARED') THEN 1 ELSE 0 END

            -- Serialize per wallet: HOLDLOCK on the owner's tail entry so two
            -- concurrent inserts can't both read the same previous balance.
            DECLARE @prev DECIMAL(12,2) = ISNULL(
                (SELECT TOP 1 balanceAfter
                 FROM [dbo].[walletTransactions] WITH (UPDLOCK, HOLDLOCK)
                 WHERE companyId = @companyId
                   AND ((@clientId IS NULL AND clientId IS NULL) OR clientId = @clientId)
                   AND entryType NOT IN ('CAPITAL_DECLARED','CAPITAL_COMMITTED','CAPITAL_UNDECLARED')
                 ORDER BY entryId DESC), 0);

            DECLARE @newBalance DECIMAL(12,2) =
                @prev + CASE @direction WHEN 'C' THEN @amountMXN ELSE -@amountMXN END;

            -- Debits cannot overdraw the wallet (RESERVE/RELEASE included:
            -- available balance is what this running figure represents).
            -- Virtual CAPITAL_* entries skip this entirely — not real money.
            IF @isCapitalEntry = 0 AND @newBalance < 0
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT '{"error":"Saldo insuficiente","available":' + CAST(@prev AS NVARCHAR(20)) + '}' AS [jsonResult]
                RETURN
            END

            INSERT INTO [dbo].[walletTransactions]
                (companyId, clientId, entryType, direction, amountMXN,
                 referenceType, referenceId, idempotencyKey, balanceAfter, note)
            VALUES
                (@companyId, @clientId, @entryType, @direction, @amountMXN,
                 @referenceType, @referenceId, @idempotencyKey,
                 CASE WHEN @isCapitalEntry = 1 THEN NULL ELSE @newBalance END, @note)

            COMMIT TRANSACTION;

            SELECT (SELECT TOP 1 entryId, companyId, clientId, entryType, direction,
                           amountMXN, balanceAfter, idempotencyKey, note,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[walletTransactions]
                    WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
        ELSE
            -- INSERT-only ledger: no updates, no deletes — ever.
            SELECT '{"error":"walletTransactions es un ledger INSERT-only; las correcciones son asientos REVERSAL (action 1)."}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- dbo.sp_walletTransactions_all
IF OBJECT_ID(N'dbo.sp_walletTransactions_all', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_walletTransactions_all];
GO
CREATE PROCEDURE [dbo].[sp_walletTransactions_all]  -- statement / movements view
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT           = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].companyId')
    DECLARE @clientId  INT           = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].clientId')
    DECLARE @entryType NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].entryType')

    SELECT ISNULL(
        (SELECT TOP 200 entryId, companyId, clientId, entryType, direction, amountMXN,
                referenceType, referenceId, balanceAfter, note,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[walletTransactions]
         WHERE companyId = @companyId
           AND ((@clientId IS NULL AND clientId IS NULL) OR clientId = @clientId)
           AND (@entryType IS NULL OR entryType = @entryType)
         ORDER BY entryId DESC
         FOR JSON PATH, ROOT('walletTransactions')),
        '{"walletTransactions":[]}'
    ) AS [jsonResult]
END
GO

-- dbo.sp_walletTransactions_balance
IF OBJECT_ID(N'dbo.sp_walletTransactions_balance', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_walletTransactions_balance];
GO
CREATE PROCEDURE [dbo].[sp_walletTransactions_balance]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].companyId')
    DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].clientId')

    -- available = running balance (tail entry among REAL-money rows only —
    -- CAPITAL_* entries are excluded: they store balanceAfter = NULL and
    -- never represent money SmartLoans holds, see sp_walletTransactions
    -- INSERT above). Filtering by entryType here (not just relying on the
    -- NULL) matters: if a CAPITAL_* row happens to be the physically-last
    -- row, ISNULL(NULL, 0) would wrongly reset the balance to $0 instead of
    -- carrying forward the last real one.
    -- reserved = RESERVE minus RELEASE (already subtracted from available;
    -- shown separately for the UI).
    DECLARE @available DECIMAL(12,2) = ISNULL(
        (SELECT TOP 1 balanceAfter FROM [dbo].[walletTransactions]
         WHERE companyId = @companyId
           AND ((@clientId IS NULL AND clientId IS NULL) OR clientId = @clientId)
           AND entryType NOT IN ('CAPITAL_DECLARED','CAPITAL_COMMITTED','CAPITAL_UNDECLARED')
         ORDER BY entryId DESC), 0);

    DECLARE @reserved DECIMAL(12,2) = ISNULL(
        (SELECT SUM(CASE entryType WHEN 'RESERVE' THEN amountMXN
                                   WHEN 'RELEASE' THEN -amountMXN ELSE 0 END)
         FROM [dbo].[walletTransactions]
         WHERE companyId = @companyId
           AND ((@clientId IS NULL AND clientId IS NULL) OR clientId = @clientId)
           AND entryType IN ('RESERVE','RELEASE')), 0);
    IF @reserved < 0 SET @reserved = 0;

    SELECT ('{"availableBalance":' + CAST(@available AS NVARCHAR(20)) +
            ',"reservedBalance":'  + CAST(@reserved  AS NVARCHAR(20)) + '}') AS [jsonResult]
END
GO

-- dbo.sp_whatsapp_messages
IF OBJECT_ID(N'dbo.sp_whatsapp_messages', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_whatsapp_messages];
GO
CREATE PROC [dbo].[sp_whatsapp_messages] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.messages'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for incoming/outgoing messages
            INSERT INTO [dbo].[whatsapp_messages] 
                ([phoneNumber], [messageBody], [responseBody], [direction], [status])
            SELECT
                JSON_VALUE(value, '$.phoneNumber'),
                JSON_VALUE(value, '$.messageBody'),
                JSON_VALUE(value, '$.responseBody'),
                JSON_VALUE(value, '$.direction'),
                JSON_VALUE(value, '$.status')
            FROM OPENJSON(@pjsonfile, '$.messages');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Message Logged Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for a message's response or status
            UPDATE wm
            SET 
                wm.[responseBody] = JSON_VALUE(j.value, '$.responseBody'),
                wm.[status] = JSON_VALUE(j.value, '$.status')
            FROM 
                [dbo].[whatsapp_messages] wm
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.messages') j
                ON wm.[messageId] = JSON_VALUE(j.value, '$.messageId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Message Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for messages
            DELETE FROM [dbo].[whatsapp_messages]
            WHERE [messageId] IN (SELECT JSON_VALUE(value, '$.messageId') FROM OPENJSON(@pjsonfile, '$.messages'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Message Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_workflowLog
IF OBJECT_ID(N'dbo.sp_workflowLog', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_workflowLog];
GO
CREATE PROCEDURE [dbo].[sp_workflowLog] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [dbo].[workflowLogs]
            (workflowId, correlationId, companyId, clientId, userId, entityName, entityId,
             workflowName, stepName, actionName, status, message, durationMs,
             requestJson, responseJson, exception, ipAddress, deviceInfo, appVersion, apiEndpoint)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.userId')),
            JSON_VALUE(value, '$.entityName'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.entityId')),
            JSON_VALUE(value, '$.workflowName'),
            JSON_VALUE(value, '$.stepName'),
            JSON_VALUE(value, '$.actionName'),
            JSON_VALUE(value, '$.status'),
            JSON_VALUE(value, '$.message'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.durationMs')),
            JSON_VALUE(value, '$.requestJson'),
            JSON_VALUE(value, '$.responseJson'),
            JSON_VALUE(value, '$.exception'),
            JSON_VALUE(value, '$.ipAddress'),
            JSON_VALUE(value, '$.deviceInfo'),
            JSON_VALUE(value, '$.appVersion'),
            JSON_VALUE(value, '$.apiEndpoint')
        FROM OPENJSON(@pjsonfile, '$.logs')
        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

/* ---------- TRIGGERS ---------- */

-- dbo.trg_users_set_qr
IF OBJECT_ID(N'dbo.trg_users_set_qr', N'TR') IS NOT NULL
    DROP TRIGGER [dbo].[trg_users_set_qr];
GO
CREATE   TRIGGER dbo.trg_users_set_qr
ON dbo.users
AFTER INSERT
AS
BEGIN
  SET NOCOUNT ON;

  UPDATE u
  SET u.qrCode = CONCAT('USER:', u.userId)
  FROM dbo.users u
  JOIN inserted i ON i.userId = u.userId
  WHERE u.qrCode IS NULL;
END;
GO
