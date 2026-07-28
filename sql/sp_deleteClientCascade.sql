CREATE OR ALTER PROC [dbo].[sp_deleteClientCascade] (@pjsonfile VARCHAR(MAX))
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


-- ============================================================
-- Example call: delete the batch, clientId 1 is skipped.
-- (2116 appears twice — the second pass reports "no encontrado" since the
--  first already removed it, and the batch continues either way.)
-- ============================================================
EXEC [dbo].[sp_deleteClientCascade] @pjsonfile = N'{
  "clients": [
    { "clientId": 2116 },
    { "clientId": 2116 },
    { "clientId": 2151 },
    { "clientId": 2157 },
    { "clientId": 2046 },
    { "clientId": 2156 },
    { "clientId": 1 }
  ]
}';
