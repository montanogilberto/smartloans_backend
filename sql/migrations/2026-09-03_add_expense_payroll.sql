-- =============================================================================
-- Add expenseType='payroll' + employeeId to dbo.expenses
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, AFTER
-- 2026-09-02_add_expense_type_notes_receipturl.sql (this migration's
-- CREATE OR ALTER PROC assumes expenseType/notes/receiptUrl already exist).
--
-- WHY: expenseType so far only distinguished 'inventory' (restocking the
-- company's own sales catalog) from 'general' (a lump-sum bill, e.g. a
-- utility). Salary is neither — it's payroll to an employee, not a payment
-- to a supplier, and forcing it through `supplierId` would mean creating a
-- fake "Supplier" row per employee, corrupting "who did we pay externally"
-- reporting. This adds a third expenseType, 'payroll', that uses employeeId
-- instead of supplierId.
--
-- SCOPE:
--   - expenseType CHECK constraint dropped and recreated to allow 'payroll'
--     alongside the existing 'inventory'/'general' (SQL Server has no
--     ALTER CHECK ADD VALUE — the constraint must be replaced).
--   - employeeId INT NULL added, with an FK to dbo.employees (existence is
--     also explicitly checked in sp_expense for a clearer error message
--     than a raw FK violation).
--   - supplierId is relaxed from NOT NULL to NULL (payroll rows have no
--     supplier). Existing rows are unaffected — they all already have a
--     real supplierId.
--   - New CK_expenses_party constraint enforces exactly one of
--     supplierId/employeeId is set, matching expenseType: payroll rows
--     must have employeeId and no supplierId; inventory/general rows must
--     have supplierId and no employeeId. This is the same
--     "belt-and-suspenders" pattern as CK_expenses_expenseType — the app
--     already enforces this in sp_expense, the constraint just makes it
--     impossible to violate even from a future caller that skips the SP.
-- Then CREATE OR ALTERs [dbo].[sp_expense]: action=1 (INSERT) requires
-- employeeId (not supplierId) when expenseType='payroll', and validates it
-- exists in dbo.employees; action=2 (UPDATE) can optionally update
-- employeeId too. Product handling (still gated on expenseType='inventory')
-- is unchanged — payroll behaves like general in that regard, just with a
-- different required party.
-- Idempotent: the ALTER TABLE steps are guarded by sys.columns/
-- sys.check_constraints/sys.foreign_keys existence checks, safe to run more
-- than once. CREATE OR ALTER is always safe to re-run.
--
-- KNOWN LIMITATION (explicitly accepted, not fixed here): dbo.employees has
-- no companyId column, so this migration cannot validate that a payroll
-- expense's employeeId belongs to the same company as the expense itself
-- (unlike supplierId, which IS companyId-scoped). The frontend employee
-- picker is unfiltered across every company for the same reason. Revisit
-- if/when employees gain a real companyId (directly or via a reliable
-- departmentId/employmentTypeId join).
--
-- FOLLOW-UP (carried over from the previous migration, still true):
-- [dbo].[sp_expense_all] still needs its SELECT list updated to return
-- expenseType, notes, receiptUrl, and now employeeId — its current
-- definition wasn't available when either migration was written.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints WHERE name = 'CK_expenses_expenseType'
)
BEGIN
    RAISERROR('CK_expenses_expenseType not found — run 2026-09-02_add_expense_type_notes_receipturl.sql first.', 16, 1);
END
GO

ALTER TABLE [dbo].[expenses] DROP CONSTRAINT CK_expenses_expenseType;
GO

ALTER TABLE [dbo].[expenses]
    ADD CONSTRAINT CK_expenses_expenseType CHECK (expenseType IN ('inventory', 'general', 'payroll'));
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'employeeId'
)
BEGIN
    ALTER TABLE [dbo].[expenses] ADD employeeId INT NULL;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_expenses_employeeId'
)
BEGIN
    ALTER TABLE [dbo].[expenses]
        ADD CONSTRAINT FK_expenses_employeeId FOREIGN KEY (employeeId)
        REFERENCES [dbo].[employees] (employeeId);
END
GO

-- Defensive: notes/receiptUrl should already exist from
-- 2026-09-02_add_expense_type_notes_receipturl.sql, but that migration may
-- only have been partially applied on some environments (observed: expenseType
-- landed without receiptUrl) — the CREATE OR ALTER PROC below references both,
-- so make this migration self-sufficient rather than trusting migration order.
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'notes'
)
BEGIN
    ALTER TABLE [dbo].[expenses] ADD notes NVARCHAR(255) NULL;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'receiptUrl'
)
BEGIN
    ALTER TABLE [dbo].[expenses] ADD receiptUrl NVARCHAR(500) NULL;
END
GO

-- Relax supplierId to nullable (payroll rows carry employeeId instead).
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'supplierId' AND is_nullable = 0
)
BEGIN
    ALTER TABLE [dbo].[expenses] ALTER COLUMN supplierId INT NULL;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints WHERE name = 'CK_expenses_party'
)
BEGIN
    ALTER TABLE [dbo].[expenses]
        ADD CONSTRAINT CK_expenses_party CHECK (
            (expenseType = 'payroll' AND employeeId IS NOT NULL AND supplierId IS NULL)
            OR
            (expenseType <> 'payroll' AND supplierId IS NOT NULL AND employeeId IS NULL)
        );
END
GO

-- =============================================================================
-- sp_expense — action=1's required party is now supplierId (inventory/
-- general) OR employeeId (payroll); action=2 can optionally update either.
-- Full CREATE OR ALTER (not a diff), same as the previous migration.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
  dbo.sp_expense

  Actions:
    1 = INSERT (single expense with multiple products, a general bill, or a payroll entry)
    2 = UPDATE (header only)
    3 = DELETE (by expenseId)

  Insert behavior (action=1):
    - expenseType='inventory' (default): requires supplierId AND at least one
      product line (expenses[0].products[] preferred, or productId directly
      on each expenses[] entry); RAISERRORs if either is missing.
    - expenseType='general': requires supplierId, no products. Use `notes`
      to record what the expense was for.
    - expenseType='payroll': requires employeeId (validated against
      dbo.employees), NOT supplierId, no products. Use `notes` for pay
      period / detail.
    - `receiptUrl` is optional on all three — a blob URL from
      POST /expenses/upload-image, uploaded separately before this call.
    - Creates ONE row in dbo.expenses either way.

  Notes:
    - Uses ISJSON/OPENJSON/JSON_VALUE/JSON_QUERY only.
*/

ALTER   PROC [dbo].[sp_expense]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  /*
  -- Sample payload (payroll — new)
  DECLARE @pjsonfile NVARCHAR(MAX) = '
  {
    "expenses": [
      {
        "action": 1,
        "expenseType": "payroll",
        "employeeId": 14,
        "notes": "Quincena 16-31 agosto 2026",
        "total": 3500.00,
        "paymentMethod": "Transferencia",
        "paymentDate": "2026-08-31T18:00:00",
        "userId": 1,
        "companyId": 1
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
        @header_employeeId    INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].employeeId')),
        @header_companyId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].companyId')),
        @header_expenseType   NVARCHAR(20)  = ISNULL(NULLIF(JSON_VALUE(@pjsonfile, '$.expenses[0].expenseType'), ''), 'inventory'),
        @header_notes         NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.expenses[0].notes'),
        @header_receiptUrl    NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.expenses[0].receiptUrl');

      IF @header_userId IS NULL OR @header_companyId IS NULL
        RAISERROR('userId and companyId are required for INSERT.', 16, 1);

      IF @header_expenseType NOT IN ('inventory', 'general', 'payroll')
        RAISERROR('expenseType must be ''inventory'', ''general'' or ''payroll''.', 16, 1);

      IF @header_expenseType = 'payroll'
      BEGIN
        IF @header_employeeId IS NULL
          RAISERROR('employeeId is required when expenseType=''payroll''.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM dbo.employees e WHERE e.employeeId = @header_employeeId)
          RAISERROR('employeeId does not exist.', 16, 1);

        -- Payroll rows carry no supplier (matches CK_expenses_party).
        SET @header_supplierId = NULL;
      END
      ELSE
      BEGIN
        IF @header_supplierId IS NULL
          RAISERROR('supplierId is required unless expenseType=''payroll''.', 16, 1);

        -- inventory/general rows carry no employee (matches CK_expenses_party).
        SET @header_employeeId = NULL;
      END

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

      IF @header_expenseType = 'inventory'
      BEGIN
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
          RAISERROR('No products found. Provide expenses[0].products[] or entries with productId, or set expenseType=''general''/''payroll''.', 16, 1);
      END
      -- expenseType='general'/'payroll': @Products intentionally stays empty, no product validation.

      --------------------------------------------------------------------------
      -- Insert expense header
      --------------------------------------------------------------------------
      DECLARE @expenseId INT;

      INSERT INTO dbo.expenses (orderId, total, paymentMethod, paymentDate, userId, supplierId, companyId, expenseType, notes, receiptUrl, employeeId)
      VALUES (NULL, @final_total, @header_paymentMethod, COALESCE(@header_paymentDate, SYSUTCDATETIME()),
              @header_userId, @header_supplierId, @header_companyId, @header_expenseType, @header_notes, @header_receiptUrl, @header_employeeId);

      SET @expenseId = SCOPE_IDENTITY();

      IF @header_expenseType = 'inventory'
      BEGIN
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
      END
      -- expenseType='general'/'payroll': no expenseDetails/expenseDetailOptions rows.

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
          companyId      INT            '$.companyId',
          expenseType    NVARCHAR(20)   '$.expenseType',
          notes          NVARCHAR(255)  '$.notes',
          receiptUrl     NVARCHAR(500)  '$.receiptUrl',
          employeeId     INT            '$.employeeId'
        )
      )
      UPDATE e
         SET orderId       = COALESCE(j.orderId, e.orderId),
             total         = COALESCE(j.total, e.total),
             paymentMethod = COALESCE(j.paymentMethod, e.paymentMethod),
             paymentDate   = COALESCE(j.paymentDate, e.paymentDate),
             userId        = COALESCE(j.userId, e.userId),
             supplierId    = COALESCE(j.supplierId, e.supplierId),
             companyId     = COALESCE(j.companyId, e.companyId),
             expenseType   = COALESCE(j.expenseType, e.expenseType),
             notes         = COALESCE(j.notes, e.notes),
             receiptUrl    = COALESCE(j.receiptUrl, e.receiptUrl),
             employeeId    = COALESCE(j.employeeId, e.employeeId)
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
