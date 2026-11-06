-- =============================================================================
-- companyPaymentAccounts stored procedures. Run after the 2026-11-06 migration.
-- Factory pattern (posgmo-factory/agents/database/prompt.py), with these PRD rules:
--   action 3 is refused: rows are never deleted, they are ARCHIVED.
--   action 4 confirms: PENDING_VERIFICATION -> ACTIVE by a second admin.
-- =============================================================================
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_companyPaymentAccounts] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage NVARCHAR(MAX) = '{
  "result": [
    { "value": "", "msg": "", "error": "" }
  ]
}';

    DECLARE @action INT;
    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.companyPaymentAccounts')
    );

    DECLARE @payload TABLE (
        companyPaymentAccountId  INT NULL,
        companyId                INT NULL,
        commissionTerminalId     INT NULL,
        purpose                  NVARCHAR(30) NULL,
        accountType              NVARCHAR(20) NULL,
        clabe                    NVARCHAR(18) NULL,
        clabeHash                NVARCHAR(64) NULL,
        bankName                 NVARCHAR(100) NULL,
        holderName               NVARCHAR(255) NULL,
        rfc                      NVARCHAR(13) NULL,
        stripeConnectedAccountId NVARCHAR(100) NULL,
        chargesEnabled           BIT NULL,
        createdByUserId          INT NULL,
        verifiedByUserId         INT NULL
    );

    BEGIN TRY
        INSERT INTO @payload
        SELECT
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyPaymentAccountId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.commissionTerminalId')),
            JSON_VALUE(value, '$.purpose'),
            JSON_VALUE(value, '$.accountType'),
            JSON_VALUE(value, '$.clabe'),
            JSON_VALUE(value, '$.clabeHash'),
            JSON_VALUE(value, '$.bankName'),
            JSON_VALUE(value, '$.holderName'),
            JSON_VALUE(value, '$.rfc'),
            JSON_VALUE(value, '$.stripeConnectedAccountId'),
            TRY_CONVERT(BIT, JSON_VALUE(value, '$.chargesEnabled')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.createdByUserId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.verifiedByUserId'))
        FROM OPENJSON(@pjsonfile, '$.companyPaymentAccounts');

        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            IF EXISTS (SELECT 1 FROM @payload
                       WHERE companyId IS NULL OR purpose IS NULL OR holderName IS NULL OR createdByUserId IS NULL
                          OR accountType NOT IN ('spei', 'stripe_connect')
                          OR (accountType = 'spei' AND (LEN(ISNULL(clabe, '')) <> 18 OR commissionTerminalId IS NULL))
                          OR (accountType = 'stripe_connect' AND stripeConnectedAccountId IS NULL))
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'missing_fields');
                COMMIT TRANSACTION;
                GOTO Finish;
            END

            -- A corrected CLABE replaces the pending one: only one waits for confirmation.
            UPDATE t
            SET t.accountStatus = 'ARCHIVED', t.archivedAt = GETDATE(), t.updated_at = GETDATE()
            FROM dbo.companyPaymentAccounts AS t
            INNER JOIN @payload AS p ON t.companyId = p.companyId AND t.purpose = p.purpose
            WHERE p.accountType = 'spei' AND t.accountType = 'spei' AND t.accountStatus = 'PENDING_VERIFICATION';

            INSERT INTO dbo.companyPaymentAccounts
                (companyId, commissionTerminalId, purpose, accountType, accountStatus, clabe, clabeHash, bankCode,
                 bankName, holderName, rfc, stripeConnectedAccountId, chargesEnabled, createdByUserId)
            SELECT p.companyId, p.commissionTerminalId, p.purpose, p.accountType, 'PENDING_VERIFICATION', p.clabe,
                   p.clabeHash, LEFT(p.clabe, 3), p.bankName, p.holderName, p.rfc, p.stripeConnectedAccountId,
                   CASE WHEN p.accountType = 'stripe_connect' THEN 0 END, p.createdByUserId
            FROM @payload AS p;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(SCOPE_IDENTITY() AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Mirrors Stripe's charges_enabled; nothing else is editable.
            UPDATE t
            SET t.chargesEnabled = p.chargesEnabled, t.updated_at = GETDATE()
            FROM dbo.companyPaymentAccounts AS t
            INNER JOIN @payload AS p ON t.stripeConnectedAccountId = p.stripeConnectedAccountId
            WHERE t.accountStatus <> 'ARCHIVED';

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@@ROWCOUNT AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 4
        BEGIN
            DECLARE @problem NVARCHAR(40), @rowId INT, @rowCompany INT, @rowPurpose NVARCHAR(30), @rowType NVARCHAR(20);

            SELECT @rowId = t.companyPaymentAccountId, @rowCompany = t.companyId,
                   @rowPurpose = t.purpose, @rowType = t.accountType,
                   @problem = CASE
                       WHEN t.accountStatus <> 'PENDING_VERIFICATION' THEN 'not_pending'
                       WHEN p.verifiedByUserId IS NULL OR p.verifiedByUserId = t.createdByUserId THEN 'second_admin_required'
                       WHEN t.accountType = 'stripe_connect' AND ISNULL(t.chargesEnabled, 0) = 0 THEN 'charges_not_enabled'
                   END
            FROM dbo.companyPaymentAccounts AS t WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN @payload AS p
                ON t.companyPaymentAccountId = p.companyPaymentAccountId AND t.companyId = p.companyId;

            IF @rowId IS NULL SET @problem = 'not_found';
            IF @problem IS NOT NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @problem);
                COMMIT TRANSACTION;
                GOTO Finish;
            END

            UPDATE dbo.companyPaymentAccounts
            SET accountStatus = 'ARCHIVED', archivedAt = GETDATE(), updated_at = GETDATE()
            WHERE companyId = @rowCompany AND purpose = @rowPurpose AND accountType = @rowType AND accountStatus = 'ACTIVE';

            UPDATE t
            SET t.accountStatus = 'ACTIVE', t.verifiedByUserId = p.verifiedByUserId,
                t.verifiedAt = GETDATE(), t.updated_at = GETDATE()
            FROM dbo.companyPaymentAccounts AS t
            INNER JOIN @payload AS p ON t.companyPaymentAccountId = p.companyPaymentAccountId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@rowId AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Confirmed Successfully');
        END
        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid action');
            COMMIT TRANSACTION;
            GOTO Finish;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH

Finish:
    SELECT
        JSON_VALUE(value, '$.value') AS value,
        JSON_VALUE(value, '$.msg')   AS msg,
        JSON_VALUE(value, '$.error') AS error
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_companyPaymentAccounts_all] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT;
    SET @companyId = TRY_CONVERT(INT,
        (SELECT TOP 1 JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.companyPaymentAccounts'))
    );

    SELECT
        [companyPaymentAccountId],
        [companyId],
        ISNULL([commissionTerminalId], 0) AS commissionTerminalId,
        [purpose],
        [accountType],
        [accountStatus],
        ISNULL([clabe], '') AS clabe,
        ISNULL([bankCode], '') AS bankCode,
        ISNULL([bankName], '') AS bankName,
        [holderName],
        ISNULL([rfc], '') AS rfc,
        ISNULL([stripeConnectedAccountId], '') AS stripeConnectedAccountId,
        ISNULL([chargesEnabled], 0) AS chargesEnabled,
        [createdByUserId],
        ISNULL([verifiedByUserId], 0) AS verifiedByUserId,
        ISNULL(CONVERT(VARCHAR(30), [verifiedAt], 126), '') AS verifiedAt,
        ISNULL(CONVERT(VARCHAR(30), [archivedAt], 126), '') AS archivedAt,
        ISNULL([notes], '') AS notes,
        [created_At],
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM [dbo].[companyPaymentAccounts]
    WHERE [companyId] = @companyId
    ORDER BY [companyPaymentAccountId] DESC
    FOR JSON AUTO, ROOT('companyPaymentAccounts');
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_companyPaymentAccounts_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @companyId INT;
    SELECT TOP 1 @id = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyPaymentAccountId')),
                 @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId'))
    FROM OPENJSON(@pjsonfile, '$.companyPaymentAccounts');

    SELECT
        [companyPaymentAccountId],
        [companyId],
        ISNULL([commissionTerminalId], 0) AS commissionTerminalId,
        [purpose],
        [accountType],
        [accountStatus],
        ISNULL([clabe], '') AS clabe,
        ISNULL([bankName], '') AS bankName,
        [holderName],
        ISNULL([stripeConnectedAccountId], '') AS stripeConnectedAccountId,
        ISNULL([chargesEnabled], 0) AS chargesEnabled,
        [createdByUserId],
        ISNULL([verifiedByUserId], 0) AS verifiedByUserId,
        [created_At]
    FROM [dbo].[companyPaymentAccounts]
    WHERE [companyPaymentAccountId] = @id AND [companyId] = @companyId
    FOR JSON AUTO, ROOT('companyPaymentAccounts');
END
GO

-- Only ACTIVE rows. The module decides what a customer may see of them.
CREATE OR ALTER PROCEDURE [dbo].[sp_companyPaymentAccounts_active] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT, @purpose NVARCHAR(30);
    SELECT TOP 1 @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
                 @purpose = JSON_VALUE(value, '$.purpose')
    FROM OPENJSON(@pjsonfile, '$.companyPaymentAccounts');

    SELECT
        a.[accountType],
        a.[holderName],
        ISNULL(a.[clabe], '') AS clabe,
        ISNULL(a.[bankName], '') AS bankName,
        ISNULL(a.[stripeConnectedAccountId], '') AS stripeConnectedAccountId,
        ISNULL(a.[chargesEnabled], 0) AS chargesEnabled,
        ISNULL((SELECT t.[terminalName] FROM [dbo].[commissionTerminals] AS t
                WHERE t.[commissionTerminalId] = a.[commissionTerminalId]), '') AS terminalName
    FROM [dbo].[companyPaymentAccounts] AS a
    WHERE a.[companyId] = @companyId AND a.[purpose] = @purpose AND a.[accountStatus] = 'ACTIVE'
    FOR JSON AUTO, ROOT('companyPaymentAccounts');
END
GO
