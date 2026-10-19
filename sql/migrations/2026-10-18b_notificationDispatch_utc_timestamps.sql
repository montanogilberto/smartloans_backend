-- 2026-10-18b — notificationDispatches: write created_At / updated_at in UTC.
-- sentAt/confirmedAt/failedAt come from Python's _now_sql() (UTC), but
-- sp_notificationDispatches wrote created_At and updated_at with GETDATE(),
-- which on this server is US Eastern (CURRENT_TIMEZONE() = Eastern Time).
-- The POS dispatch log reads every column as UTC, so "Creado" showed 4h
-- early (dispatch 1196: created_At 16:20:57 vs sentAt 20:20:57).
--
-- 1. Backfill: converts existing created_At/updated_at from Eastern to UTC with
--    AT TIME ZONE (DST-aware: +4h in summer, +5h in winter).
-- 2. sp_notificationDispatches: GETDATE() -> GETUTCDATE() (insert + update).
-- 3. Column default for created_At: getdate() -> getutcdate() (the SP sets the
--    value itself, so the default only matters for direct inserts).
--
-- Runs as ONE transaction. Re-run guard: the backfill runs only while the live SP
-- still uses GETDATE(). The SP is changed in the same transaction, so a second
-- run never shifts the rows twice.
-- Backend: none (modules/notificationDispatch.py already sends UTC).
-- Rollback: 2026-10-18b_notificationDispatch_utc_timestamps_ROLLBACK.sql

SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
GO

IF OBJECT_DEFINITION(OBJECT_ID('dbo.sp_notificationDispatches')) NOT LIKE '%GETUTCDATE()%'
BEGIN
    SELECT 'BEFORE' AS phase, COUNT(*) AS rowsToFix,
           SUM(CASE WHEN updated_at IS NOT NULL THEN 1 ELSE 0 END) AS updatedAtToFix,
           MIN(created_At) AS minCreated, MAX(created_At) AS maxCreated
    FROM dbo.notificationDispatches WITH (TABLOCKX, HOLDLOCK);

    UPDATE dbo.notificationDispatches
    SET created_At = CAST((created_At AT TIME ZONE 'Eastern Standard Time') AT TIME ZONE 'UTC' AS DATETIME),
        updated_at = CAST((updated_at AT TIME ZONE 'Eastern Standard Time') AT TIME ZONE 'UTC' AS DATETIME)
    WHERE created_At IS NOT NULL OR updated_at IS NOT NULL;

    SELECT 'AFTER' AS phase, DATEDIFF(MINUTE, created_At, sentAt) AS createdToSentMin, COUNT(*) AS n
    FROM dbo.notificationDispatches
    WHERE sentAt IS NOT NULL
    GROUP BY DATEDIFF(MINUTE, created_At, sentAt);
END
ELSE
    PRINT 'sp_notificationDispatches already uses GETUTCDATE(): backfill skipped (already applied).';
GO

IF @@TRANCOUNT = 0
BEGIN
    RAISERROR('Transaction was rolled back by an earlier error. Stopping; nothing after this point runs.', 16, 1);
    SET NOEXEC ON;
END
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatches] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @Outputmessage NVARCHAR(MAX) = '{
      "result": [
        { "value": "", "msg": "", "error": "" }
      ]
    }'

    DECLARE @action INT;
    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.notificationDispatches')
    );

    DECLARE @payload TABLE (
        notificationDispatchId  INT NULL,
        companyId               INT NULL,
        sourceType              NVARCHAR(20) NULL,
        sourceId                INT NULL,
        recipientType           NVARCHAR(10) NULL,
        recipientId             INT NULL,
        eventName               NVARCHAR(40) NULL,
        preferredChannel        NVARCHAR(20) NULL,
        selectedChannel         NVARCHAR(20) NULL,
        attemptedChannels       NVARCHAR(MAX) NULL,
        fallbackReason          NVARCHAR(30) NULL,
        status                  NVARCHAR(20) NULL,
        providerMessageId       NVARCHAR(100) NULL,
        providerName            NVARCHAR(30) NULL,
        messagePreview          NVARCHAR(200) NULL,
        sentAt                  DATETIME NULL,
        confirmedAt             DATETIME NULL,
        failedAt                DATETIME NULL,
        providerErrorCode       NVARCHAR(20) NULL,
        providerErrorMessage    NVARCHAR(300) NULL
    );

    INSERT INTO @payload (
        notificationDispatchId, companyId, sourceType, sourceId, recipientType, recipientId,
        eventName, preferredChannel, selectedChannel, attemptedChannels, fallbackReason, status,
        providerMessageId, providerName, messagePreview, sentAt, confirmedAt, failedAt,
        providerErrorCode, providerErrorMessage
    )
    SELECT
        TRY_CONVERT(INT, JSON_VALUE(value, '$.notificationDispatchId')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        JSON_VALUE(value, '$.sourceType'),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.sourceId')),
        JSON_VALUE(value, '$.recipientType'),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.recipientId')),
        JSON_VALUE(value, '$.eventName'),
        JSON_VALUE(value, '$.preferredChannel'),
        JSON_VALUE(value, '$.selectedChannel'),
        JSON_VALUE(value, '$.attemptedChannels'),
        JSON_VALUE(value, '$.fallbackReason'),
        JSON_VALUE(value, '$.status'),
        JSON_VALUE(value, '$.providerMessageId'),
        JSON_VALUE(value, '$.providerName'),
        JSON_VALUE(value, '$.messagePreview'),
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.sentAt')),
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.confirmedAt')),
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.failedAt')),
        LEFT(JSON_VALUE(value, '$.providerErrorCode'), 20),
        LEFT(JSON_VALUE(value, '$.providerErrorMessage'), 300)
    FROM OPENJSON(@pjsonfile, '$.notificationDispatches');

    BEGIN TRY
        BEGIN TRANSACTION

        IF @action = 1 -- INSERT
        BEGIN
            IF EXISTS (
                SELECT 1 FROM @payload
                GROUP BY companyId, sourceType, sourceId, eventName
                HAVING COUNT(*) > 1
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Duplicate records in payload for same companyId, sourceType, sourceId, eventName.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END;

            IF EXISTS (
                SELECT 1
                FROM dbo.notificationDispatches nd
                INNER JOIN @payload p ON nd.companyId = p.companyId
                                     AND nd.sourceType = p.sourceType
                                     AND nd.sourceId = p.sourceId
                                     AND nd.eventName = p.eventName
                WHERE nd.status IN ('sent', 'confirmed')
            )
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Dispatch already sent or confirmed for this event. No re-send.');
                COMMIT TRANSACTION;
                GOTO Finish;
            END;

            INSERT INTO dbo.notificationDispatches (
                companyId, sourceType, sourceId, recipientType, recipientId, eventName,
                preferredChannel, selectedChannel, attemptedChannels, fallbackReason, status,
                providerMessageId, providerName, messagePreview, sentAt, confirmedAt, failedAt,
                providerErrorCode, providerErrorMessage,
                created_At, updated_at
            )
            SELECT
                p.companyId, p.sourceType, p.sourceId, p.recipientType, p.recipientId, p.eventName,
                p.preferredChannel, p.selectedChannel, p.attemptedChannels, p.fallbackReason, p.status,
                p.providerMessageId, p.providerName, p.messagePreview, p.sentAt, p.confirmedAt, p.failedAt,
                p.providerErrorCode, p.providerErrorMessage,
                GETUTCDATE(), NULL
            FROM @payload p;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2 -- UPDATE
        BEGIN
            UPDATE nd
            SET
                status = ISNULL(p.status, nd.status),
                confirmedAt = ISNULL(p.confirmedAt, nd.confirmedAt),
                failedAt = ISNULL(p.failedAt, nd.failedAt),
                providerErrorCode = ISNULL(p.providerErrorCode, nd.providerErrorCode),
                providerErrorMessage = ISNULL(p.providerErrorMessage, nd.providerErrorMessage),
                updated_at = GETUTCDATE()
            FROM dbo.notificationDispatches nd
            INNER JOIN @payload p ON nd.notificationDispatchId = p.notificationDispatchId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE nd
            FROM dbo.notificationDispatches nd
            INNER JOIN @payload p ON nd.notificationDispatchId = p.notificationDispatchId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH

Finish:
    SELECT
        JSON_VALUE(value,'$.value') AS value,
        JSON_VALUE(value,'$.msg')   AS msg,
        JSON_VALUE(value,'$.error') AS error
    FROM OPENJSON(@Outputmessage,'$.result');
END
GO

IF @@TRANCOUNT = 0
BEGIN
    RAISERROR('Transaction was rolled back by an earlier error. Stopping; nothing after this point runs.', 16, 1);
    SET NOEXEC ON;
END
GO

DECLARE @df SYSNAME = (
    SELECT dc.name FROM sys.default_constraints dc
    JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
    WHERE dc.parent_object_id = OBJECT_ID('dbo.notificationDispatches') AND c.name = 'created_At'
);
IF @df IS NOT NULL AND @df <> 'DF_notificationDispatches_created_At'
    EXEC('ALTER TABLE dbo.notificationDispatches DROP CONSTRAINT [' + @df + ']');
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_notificationDispatches_created_At')
    ALTER TABLE dbo.notificationDispatches
        ADD CONSTRAINT DF_notificationDispatches_created_At DEFAULT (GETUTCDATE()) FOR created_At;
GO

IF @@TRANCOUNT = 0
BEGIN
    RAISERROR('Transaction was rolled back by an earlier error. Stopping; nothing after this point runs.', 16, 1);
    SET NOEXEC ON;
END
GO

COMMIT TRANSACTION;
GO
SET NOEXEC OFF;
GO
