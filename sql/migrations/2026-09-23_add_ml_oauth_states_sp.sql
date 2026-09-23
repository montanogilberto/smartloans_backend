-- =============================================================================
-- Add dbo.sp_mlOAuthStates — MercadoLibre PKCE state -> code_verifier store
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/mercadolibre.py::save_oauth_state / pop_code_verifier wrote
-- and read dbo.ml_oauth_states with raw INSERT/SELECT/UPDATE. Backend rule:
-- modules never issue raw SQL — every read and mutation goes through an SP.
--
-- Also fixes a replay race: pop_code_verifier did SELECT (used_at IS NULL)
-- then a separate UPDATE, so two concurrent callbacks carrying the same
-- state could both receive the verifier. 'pop' is now a single
-- UPDATE ... OUTPUT guarded by used_at IS NULL — exactly one caller wins.
--
-- SCOPE: one new SP, no table/column changes.
--   - Action-based SP convention (same shape as sp_loanInstallments):
--     @pjsonfile NVARCHAR(MAX), fields via JSON_VALUE on $.mlOAuthStates[0],
--     one [jsonResult] column, FOR JSON PATH, WITHOUT_ARRAY_WRAPPER.
--   - Caller payloads:
--       {"mlOAuthStates":[{"action":"save","state":"...","code_verifier":"..."}]}
--       {"mlOAuthStates":[{"action":"pop","state":"..."}]}
--   - No companyId: dbo.ml_oauth_states is platform-level integration state
--     (one MercadoLibre app), not tenant data — same as today's raw SQL.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_mlOAuthStates]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.mlOAuthStates[0].action');
        DECLARE @state  NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.mlOAuthStates[0].state');

        IF @state IS NULL OR @state = ''
        BEGIN
            SELECT '{"error":"state is required"}' AS [jsonResult];
            RETURN;
        END

        IF @action = 'save'
        BEGIN
            DECLARE @codeVerifier NVARCHAR(400) = JSON_VALUE(@pjsonfile, '$.mlOAuthStates[0].code_verifier');
            IF @codeVerifier IS NULL OR @codeVerifier = ''
            BEGIN
                SELECT '{"error":"code_verifier is required"}' AS [jsonResult];
                RETURN;
            END

            INSERT INTO dbo.ml_oauth_states (state, code_verifier)
            VALUES (@state, @codeVerifier);

            SELECT (SELECT @state AS state FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult];
        END

        ELSE IF @action = 'pop'
        BEGIN
            -- Atomic claim: only the first caller for an unused state gets a row.
            DECLARE @popped TABLE (code_verifier NVARCHAR(400));

            UPDATE dbo.ml_oauth_states
               SET used_at = SYSUTCDATETIME()
            OUTPUT inserted.code_verifier INTO @popped
             WHERE state = @state
               AND used_at IS NULL;

            SELECT ISNULL(
                (SELECT TOP 1 code_verifier FROM @popped FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{}'
            ) AS [jsonResult];
        END

        ELSE
            SELECT '{"error":"unknown action"}' AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO
