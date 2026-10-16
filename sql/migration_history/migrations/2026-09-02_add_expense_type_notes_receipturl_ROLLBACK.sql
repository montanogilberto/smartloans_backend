-- =============================================================================
-- ROLLBACK for 2026-09-02_add_expense_type_notes_receipturl.sql
-- =============================================================================
-- Restores sp_expense to its pre-migration form (product line(s) always
-- required on INSERT, no expenseType/notes/receiptUrl columns), then drops
-- the columns.
--
-- SAFE ONLY if no expense row has yet been created with expenseType='general'
-- OR with a non-null receiptUrl (i.e. before the updated ExpenseForm.tsx
-- ships and starts using either). ALWAYS run BOTH guard queries below FIRST.
-- If either returns any row with row_count > 0, STOP — do not proceed.
-- General-expense rows have no expenseDetails (by design), so restoring the
-- old product-required sp_expense doesn't touch them, but dropping the
-- expenseType/notes/receiptUrl columns would silently discard the only
-- record of what they were for / the uploaded proof of purchase.
-- =============================================================================

-- Guard 1 — expected result: zero rows.
SELECT expenseType, COUNT(*) AS row_count
FROM dbo.expenses
WHERE expenseType = 'general'
GROUP BY expenseType;

-- Guard 2 — expected result: zero rows.
SELECT COUNT(*) AS row_count
FROM dbo.expenses
WHERE receiptUrl IS NOT NULL;

-- Only proceed past this point if BOTH guard queries above returned nothing.

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[sp_expense]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE
    @Outputmessage NVARCHAR(MAX) = N'{"result":[{"value":"","msg":"","error":""}]}',
    @Error NVARCHAR(500) = N'';

  BEGIN TRY
    IF @pjsonfile IS NULL OR TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].action')) IS NULL
      RAISERROR('Invalid or missing JSON/action.', 16, 1);

    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].action'));

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
      DECLARE
        @header_total         DECIMAL(10,2) = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(@pjsonfile, '$.expenses[0].total')),
        @header_paymentMethod NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.expenses[0].paymentMethod'),
        @header_paymentDate   DATETIME2     = TRY_CONVERT(DATETIME2, JSON_VALUE(@pjsonfile, '$.expenses[0].paymentDate')),
        @header_userId        INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].userId')),
        @header_supplierId    INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].supplierId')),
        @header_companyId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].companyId'));

      IF @header_userId IS NULL OR @header_supplierId IS NULL OR @header_companyId IS NULL
        RAISERROR('userId, supplierId, and companyId are required for INSERT.', 16, 1);

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

      IF ISJSON(JSON_QUERY(@pjsonfile, '$.expenses[0].products')) = 1
      BEGIN
        INSERT INTO @Products (productId, optionsJson)
        SELECT TRY_CONVERT(INT, JSON_VALUE(p.value, '$.productId')),
               JSON_QUERY(p.value, '$.options')
        FROM OPENJSON(JSON_QUERY(@pjsonfile, '$.expenses[0].products')) p;
      END
      ELSE
      BEGIN
        INSERT INTO @Products (productId, optionsJson)
        SELECT TRY_CONVERT(INT, JSON_VALUE(j.value,'$.productId')),
               JSON_QUERY(j.value, '$.options')
        FROM OPENJSON(@pjsonfile, '$.expenses') j;
      END

      IF NOT EXISTS (SELECT 1 FROM @Products WHERE productId IS NOT NULL)
        RAISERROR('No products found. Provide expenses[0].products[] or entries with productId.', 16, 1);

      DECLARE @expenseId INT;

      INSERT INTO dbo.expenses (orderId, total, paymentMethod, paymentDate, userId, supplierId, companyId)
      VALUES (NULL, @final_total, @header_paymentMethod, COALESCE(@header_paymentDate, SYSUTCDATETIME()),
              @header_userId, @header_supplierId, @header_companyId);

      SET @expenseId = SCOPE_IDENTITY();

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

-- Drop the check constraint before dropping the column it references.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_expenses_expenseType')
BEGIN
    ALTER TABLE [dbo].[expenses] DROP CONSTRAINT CK_expenses_expenseType;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'expenseType')
BEGIN
    ALTER TABLE [dbo].[expenses] DROP COLUMN expenseType;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'notes')
BEGIN
    ALTER TABLE [dbo].[expenses] DROP COLUMN notes;
END
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'receiptUrl')
BEGIN
    ALTER TABLE [dbo].[expenses] DROP COLUMN receiptUrl;
END
GO
GO
