-- =============================================================================
-- Add expenseType / notes / receiptUrl to dbo.expenses; make sp_expense's
-- product requirement conditional on expenseType
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: sp_expense's INSERT path (action=1) unconditionally requires at least
-- one product line (`RAISERROR('No products found...')`), because it was
-- modeled on the same "select a product" flow as a sale. That's correct for
-- an expense that restocks the company's own sellable inventory, but wrong
-- for a general expense (gasoline, a cloud subscription, office supplies) —
-- there is no sensible product from the company's own sales catalog to pick,
-- and there was previously nowhere to record what the expense was actually
-- for (the frontend's old "Descripción" field was captured in the UI but
-- silently dropped before submit, since no column existed to hold it).
--
-- SCOPE: adds 3 columns to the existing dbo.expenses table:
--   - expenseType NVARCHAR(20) NOT NULL DEFAULT 'inventory' — 'inventory'
--     keeps today's behavior (product line(s) required); 'general' skips the
--     product requirement entirely. Existing rows are backfilled to
--     'inventory' by the same DEFAULT, which is behavior-preserving — every
--     expense row created so far went through the product-required path.
--   - notes NVARCHAR(255) NULL — free-text description, only meaningful (and
--     only expected to be sent) when expenseType = 'general'.
--   - receiptUrl NVARCHAR(500) NULL — Azure Blob URL of a photo of the
--     physical receipt/ticket, uploaded via a new POST /expenses/upload-image
--     connector (see modules/expenses.py::upload_expense_receipt_connector,
--     mirroring modules/transferEvidence.py's upload_transfer_evidence_connector
--     two-step pattern: upload bytes -> get blobUrl -> persist it here via
--     sp_expense action=1/2). NVARCHAR(500) matches the existing convention
--     for every other blob-URL column in this DB (evidenceFileUrl, imageUrl,
--     signatureImageUrl, etc).
-- Then CREATE OR ALTERs [dbo].[sp_expense] so action=1 (INSERT) only enforces
-- the "at least one product" rule when expenseType = 'inventory', and always
-- persists notes/expenseType/receiptUrl; action=2 (UPDATE) can optionally
-- update all three. action=3 (DELETE) is unchanged.
-- Idempotent: the ALTER TABLE steps are guarded by sys.columns existence
-- checks, safe to run more than once. CREATE OR ALTER is always safe to
-- re-run.
--
-- FOLLOW-UP (not included here — source not available to this migration):
-- [dbo].[sp_expense_all] (called by GET /all_expense) also needs its SELECT
-- list updated to return expenseType, notes and receiptUrl, or the frontend
-- can save them but never read them back. Update it by hand alongside this
-- migration; its current definition wasn't available when this was written.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'expenseType'
)
BEGIN
    ALTER TABLE [dbo].[expenses] ADD expenseType NVARCHAR(20) NOT NULL DEFAULT 'inventory';
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = 'CK_expenses_expenseType'
)
BEGIN
    ALTER TABLE [dbo].[expenses]
        ADD CONSTRAINT CK_expenses_expenseType CHECK (expenseType IN ('inventory', 'general'));
END
GO

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

-- =============================================================================
-- sp_expense — same INSERT/UPDATE/DELETE shape as before; action=1's product
-- requirement is now conditional on expenseType, and expenseType/notes are
-- persisted on the header. Full CREATE OR ALTER (not a diff) since this
-- procedure isn't checked into sql/ today — its live definition was pulled
-- directly from the database.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
  dbo.sp_expense

  Actions:
    1 = INSERT (single expense with multiple products, or a general expense with none)
    2 = UPDATE (header only)
    3 = DELETE (by expenseId)

  Insert behavior (action=1):
    - expenseType='inventory' (default): same as before — requires
      expenses[0].products[] (preferred) or productId directly on each
      expenses[] entry; RAISERRORs if none found.
    - expenseType='general': product requirement is skipped entirely — no
      expenseDetails/expenseDetailOptions rows are created. Use `notes` to
      record what the expense was for.
    - `receiptUrl` is optional on both actions — a blob URL from
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
  -- Sample payload (inventory — unchanged from before)
  DECLARE @pjsonfile NVARCHAR(MAX) = '
  {
    "expenses": [
      {
        "action": 1,
        "expenseType": "inventory",
        "receiptUrl": "https://...blob.core.windows.net/clients/1/expense_receipts/receipt_....jpg",
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
          }
        ]
      }
    ]
  }';

  -- Sample payload (general — new)
  DECLARE @pjsonfile NVARCHAR(MAX) = '
  {
    "expenses": [
      {
        "action": 1,
        "expenseType": "general",
        "notes": "Gasolina",
        "total": 560.00,
        "paymentMethod": "Tarjeta",
        "paymentDate": "2025-10-23T22:30:00",
        "userId": 1,
        "supplierId": 3,
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
        @header_companyId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].companyId')),
        @header_expenseType   NVARCHAR(20)  = ISNULL(NULLIF(JSON_VALUE(@pjsonfile, '$.expenses[0].expenseType'), ''), 'inventory'),
        @header_notes         NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.expenses[0].notes'),
        @header_receiptUrl    NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.expenses[0].receiptUrl');

      IF @header_userId IS NULL OR @header_supplierId IS NULL OR @header_companyId IS NULL
        RAISERROR('userId, supplierId, and companyId are required for INSERT.', 16, 1);

      IF @header_expenseType NOT IN ('inventory', 'general')
        RAISERROR('expenseType must be ''inventory'' or ''general''.', 16, 1);

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
          RAISERROR('No products found. Provide expenses[0].products[] or entries with productId, or set expenseType=''general''.', 16, 1);
      END
      -- expenseType='general': @Products intentionally stays empty, no product validation.

      --------------------------------------------------------------------------
      -- Insert expense header
      --------------------------------------------------------------------------
      DECLARE @expenseId INT;

      INSERT INTO dbo.expenses (orderId, total, paymentMethod, paymentDate, userId, supplierId, companyId, expenseType, notes, receiptUrl)
      VALUES (NULL, @final_total, @header_paymentMethod, COALESCE(@header_paymentDate, SYSUTCDATETIME()),
              @header_userId, @header_supplierId, @header_companyId, @header_expenseType, @header_notes, @header_receiptUrl);

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
      -- expenseType='general': no expenseDetails/expenseDetailOptions rows.

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
          receiptUrl     NVARCHAR(500)  '$.receiptUrl'
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
             receiptUrl    = COALESCE(j.receiptUrl, e.receiptUrl)
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
