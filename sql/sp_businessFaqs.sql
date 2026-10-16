-- ============================================================
-- FAQs per company (optional branch) for the WhatsApp assistant — it may
-- only answer general questions from these.
--   0  list (activeOnly=1: active, company-wide + that branch)
--   1  insert   2  update (only keys sent)   3  deactivate
-- Table: sql/migrations/2026-10-16_whatsapp_assistant_catalogs.sql
-- ============================================================

IF OBJECT_ID('dbo.sp_businessFaqs', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_businessFaqs;
GO
CREATE PROCEDURE [dbo].[sp_businessFaqs]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action     INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.businessFaqs[0].action'));
        DECLARE @companyId  INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.businessFaqs[0].companyId'));
        DECLARE @branchId   INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.businessFaqs[0].branchId'));
        DECLARE @faqId      INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.businessFaqs[0].faqId'));
        DECLARE @question   NVARCHAR(300)  = JSON_VALUE(@pjsonfile, '$.businessFaqs[0].question');
        DECLARE @answer     NVARCHAR(1500) = JSON_VALUE(@pjsonfile, '$.businessFaqs[0].answer');
        DECLARE @sortOrder  INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.businessFaqs[0].sortOrder'));
        DECLARE @isActive   BIT            = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.businessFaqs[0].isActive'));
        DECLARE @activeOnly BIT            = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.businessFaqs[0].activeOnly')), 0);

        DECLARE @keys TABLE ([key] NVARCHAR(100));
        INSERT INTO @keys SELECT [key] FROM OPENJSON(@pjsonfile, '$.businessFaqs[0]');

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END

        IF @action = 1
        BEGIN
            IF NULLIF(LTRIM(@question), '') IS NULL OR NULLIF(LTRIM(@answer), '') IS NULL
            BEGIN
                SELECT '{"error":"question and answer are required"}' AS jsonResult;
                RETURN;
            END
            INSERT INTO [dbo].[businessFaqs] (companyId, branchId, question, answer, sortOrder, isActive)
            VALUES (@companyId, @branchId, @question, @answer, ISNULL(@sortOrder, 0), ISNULL(@isActive, 1));
        END
        ELSE IF @action = 2
        BEGIN
            UPDATE [dbo].[businessFaqs] SET
                branchId  = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'branchId') THEN @branchId ELSE branchId END,
                question  = ISNULL(NULLIF(LTRIM(@question), ''), question),
                answer    = ISNULL(NULLIF(LTRIM(@answer), ''), answer),
                sortOrder = ISNULL(@sortOrder, sortOrder),
                isActive  = ISNULL(@isActive, isActive),
                updatedAt = GETUTCDATE()
            WHERE faqId = @faqId AND companyId = @companyId;
        END
        ELSE IF @action = 3
        BEGIN
            UPDATE [dbo].[businessFaqs] SET isActive = 0, updatedAt = GETUTCDATE()
            WHERE faqId = @faqId AND companyId = @companyId;
        END

        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT faqId, companyId, branchId, question, answer, sortOrder, isActive
            FROM [dbo].[businessFaqs]
            WHERE companyId = @companyId
              AND (@activeOnly = 0 OR (isActive = 1
                    AND (branchId IS NULL OR @branchId IS NULL OR branchId = @branchId)))
            ORDER BY sortOrder, faqId
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"businessFaqs":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
