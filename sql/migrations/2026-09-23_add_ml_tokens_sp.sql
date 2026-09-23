-- =============================================================================
-- Add dbo.sp_mlTokens — MercadoLibre OAuth token store (upsert / latest)
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/mercadolibre.py::upsert_tokens / get_latest_tokens wrote and
-- read dbo.ml_tokens with 5 raw statements (SELECT/UPDATE/INSERT/SELECT and
-- SELECT). Backend rule: modules never issue raw SQL — every read and
-- mutation goes through an SP.
--
-- Also fixes two races in the old upsert:
--   - "SELECT TOP 1 id" then UPDATE-or-INSERT in separate statements: two
--     concurrent refreshes on an empty table could both INSERT. 'upsert' now
--     runs in one transaction with UPDLOCK, HOLDLOCK on the probe.
--   - The new id was read back with "SELECT TOP 1 id ORDER BY id DESC"
--     instead of SCOPE_IDENTITY().
--
-- SCOPE: one new SP, no table/column changes.
--   - Action-based convention (same as sp_mlOAuthStates):
--     @pjsonfile NVARCHAR(MAX), root $.mlTokens, one [jsonResult] column.
--       {"mlTokens":[{"action":"upsert","access_token":"...",
--                     "refresh_token":"...","expires_at":"2026-09-23T18:00:00"}]}
--       {"mlTokens":[{"action":"latest"}]}
--   - Tokens are read with OPENJSON ... WITH (NVARCHAR(MAX)); JSON_VALUE
--     would silently return NULL above 4000 chars.
--   - expires_at in/out is naive UTC ISO-8601 (style 126), seconds precision.
--   - No companyId: one MercadoLibre app for the platform, not tenant data.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_mlTokens]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.mlTokens[0].action');

        IF @action = 'upsert'
        BEGIN
            DECLARE @accessToken  NVARCHAR(MAX),
                    @refreshToken NVARCHAR(MAX),
                    @expiresAt    DATETIME2(7),
                    @id           INT,
                    @op           NVARCHAR(10);

            SELECT TOP 1
                @accessToken  = access_token,
                @refreshToken = refresh_token,
                @expiresAt    = TRY_CONVERT(DATETIME2(7), expires_at, 126)
            FROM OPENJSON(@pjsonfile, '$.mlTokens')
            WITH (
                access_token  NVARCHAR(MAX) '$.access_token',
                refresh_token NVARCHAR(MAX) '$.refresh_token',
                expires_at    NVARCHAR(40)  '$.expires_at'
            );

            IF @accessToken IS NULL OR @refreshToken IS NULL OR @expiresAt IS NULL
            BEGIN
                SELECT '{"error":"access_token, refresh_token and expires_at are required"}' AS [jsonResult];
                RETURN;
            END

            BEGIN TRANSACTION;

            SELECT TOP 1 @id = id
            FROM dbo.ml_tokens WITH (UPDLOCK, HOLDLOCK)
            ORDER BY id DESC;

            IF @id IS NOT NULL
            BEGIN
                UPDATE dbo.ml_tokens
                   SET access_token  = @accessToken,
                       refresh_token = @refreshToken,
                       expires_at    = @expiresAt,
                       updated_at    = SYSUTCDATETIME()
                 WHERE id = @id;
                SET @op = 'updated';
            END
            ELSE
            BEGIN
                INSERT INTO dbo.ml_tokens (access_token, refresh_token, expires_at)
                VALUES (@accessToken, @refreshToken, @expiresAt);
                SET @id = SCOPE_IDENTITY();
                SET @op = 'inserted';
            END

            COMMIT TRANSACTION;

            SELECT (SELECT @id AS id, @op AS op FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult];
        END

        ELSE IF @action = 'latest'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 id, access_token, refresh_token,
                        CONVERT(VARCHAR(19), expires_at, 126) AS expires_at
                   FROM dbo.ml_tokens
                  ORDER BY id DESC
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{}'
            ) AS [jsonResult];
        END

        ELSE
            SELECT '{"error":"unknown action"}' AS [jsonResult];
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO
