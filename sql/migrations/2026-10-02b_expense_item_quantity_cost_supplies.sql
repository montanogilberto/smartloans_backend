-- =============================================================================
-- Expense line items: quantity + unit cost, and "supply" products
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB.
--
-- WHY: an inventory egreso could only record one unit of each product, with no
-- purchase cost (the form even totalled the product's SALE price). Real
-- purchases (a Sam's/Costco ticket) are many lines, each with quantity + cost,
-- and mostly consumables (detergent, soap) that don't belong in the POS menu.
--
-- WHAT:
--   * dbo.expenseDetails: + quantity DECIMAL(18,3) NOT NULL DEFAULT 1, + unitCost DECIMAL(18,2) NULL
--     (existing rows become quantity 1, cost NULL).
--   * dbo.products: + isSupply BIT NOT NULL DEFAULT 0. Supplies are created
--     WITHOUT productOptions, and sp_products_by_company only lists products
--     that have options, so they never reach the POS sales menu.
--   * sp_expense: reads products[].quantity / products[].unitCost (defaults 1 / NULL).
--   * sp_products_save: accepts products[].isSupply on insert/update.
--   * sp_products_all: also returns isSupply.
-- Bodies below are the LIVE definitions read 2026-10-02 (the repo copies have
-- drifted) with only those lines added. CREATE OR ALTER, so re-runnable.
-- NOT CHANGED ON PURPOSE: stock. dbo.inventoryStock/inventoryMovements and
-- productDetails.stockQuantity are two competing stock models; purchases do not
-- touch either until one is chosen.
-- ROLLBACK: re-run the previous definitions; the new columns are harmless.
-- =============================================================================

IF COL_LENGTH('dbo.expenseDetails','quantity') IS NULL
    ALTER TABLE dbo.expenseDetails ADD quantity DECIMAL(18,3) NOT NULL CONSTRAINT DF_expenseDetails_quantity DEFAULT 1;
IF COL_LENGTH('dbo.expenseDetails','unitCost') IS NULL
    ALTER TABLE dbo.expenseDetails ADD unitCost DECIMAL(18,2) NULL;
IF COL_LENGTH('dbo.products','isSupply') IS NULL
    ALTER TABLE dbo.products ADD isSupply BIT NOT NULL CONSTRAINT DF_products_isSupply DEFAULT 0;
GO

CREATE OR ALTER PROC [dbo].[sp_expense]
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
        @header_serviceId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].serviceId')),
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

        -- Payroll rows carry no supplier/service (matches CK_expenses_party).
        SET @header_supplierId = NULL;
        SET @header_serviceId = NULL;
      END
      ELSE IF @header_expenseType = 'general'
      BEGIN
        IF @header_serviceId IS NULL
          RAISERROR('serviceId is required when expenseType=''general''.', 16, 1);

        IF NOT EXISTS (SELECT 1 FROM dbo.Services sv WHERE sv.serviceId = @header_serviceId AND sv.companyId = @header_companyId)
          RAISERROR('serviceId does not exist for this company.', 16, 1);

        -- general rows carry a service, not a supplier or employee -- the
        -- whole point of this migration (see file header).
        SET @header_supplierId = NULL;
        SET @header_employeeId = NULL;
      END
      ELSE -- inventory
      BEGIN
        IF @header_supplierId IS NULL
          RAISERROR('supplierId is required when expenseType=''inventory''.', 16, 1);

        SET @header_employeeId = NULL;
        SET @header_serviceId = NULL;
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
        optionsJson NVARCHAR(MAX) NULL,
        quantity    DECIMAL(18,3) NOT NULL DEFAULT 1,
        unitCost    DECIMAL(18,2) NULL
      );

      IF @header_expenseType = 'inventory'
      BEGIN
        -- Preferred: expenses[0].products[]
        IF ISJSON(JSON_QUERY(@pjsonfile, '$.expenses[0].products')) = 1
        BEGIN
          INSERT INTO @Products (productId, optionsJson, quantity, unitCost)
          SELECT TRY_CONVERT(INT, JSON_VALUE(p.value, '$.productId')),
                 JSON_QUERY(p.value, '$.options'),
                 ISNULL(TRY_CONVERT(DECIMAL(18,3), JSON_VALUE(p.value, '$.quantity')), 1),
                 TRY_CONVERT(DECIMAL(18,2), JSON_VALUE(p.value, '$.unitCost'))
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

      INSERT INTO dbo.expenses (orderId, total, paymentMethod, paymentDate, userId, supplierId, companyId, expenseType, notes, receiptUrl, employeeId, serviceId)
      VALUES (NULL, @final_total, @header_paymentMethod, COALESCE(@header_paymentDate, SYSUTCDATETIME()),
              @header_userId, @header_supplierId, @header_companyId, @header_expenseType, @header_notes, @header_receiptUrl, @header_employeeId, @header_serviceId);

      SET @expenseId = SCOPE_IDENTITY();

      IF @header_expenseType = 'inventory'
      BEGIN
        --------------------------------------------------------------------------
        -- STAGING + MERGE to get (idx -> expenseDetailId) mapping
        --------------------------------------------------------------------------
        DECLARE @Staging TABLE (
          idx INT PRIMARY KEY,
          expenseId INT NOT NULL,
          productId INT NOT NULL,
          quantity DECIMAL(18,3) NOT NULL,
          unitCost DECIMAL(18,2) NULL
        );

        INSERT INTO @Staging (idx, expenseId, productId, quantity, unitCost)
        SELECT idx, @expenseId, productId, quantity, unitCost
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
          INSERT (expenseId, productId, quantity, unitCost)
          VALUES (S.expenseId, S.productId, S.quantity, S.unitCost)
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
          employeeId     INT            '$.employeeId',
          serviceId      INT            '$.serviceId'
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
             employeeId    = COALESCE(j.employeeId, e.employeeId),
             serviceId     = COALESCE(j.serviceId, e.serviceId)
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

CREATE OR ALTER PROC [dbo].[sp_products_save]
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
            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, categoryId, companyId, isSupply)
            SELECT 
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), JSON_VALUE(value, '$.code'),
                JSON_VALUE(value, '$.dateOfExpire'), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT), 0)
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
                p.categoryId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.categoryId') AS INT), p.categoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isSupply') AS BIT), p.isSupply)
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

CREATE OR ALTER PROC [dbo].[sp_products_all]
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
        ,isSupply
    FROM [montanogilberto_smartloans].[dbo].[products]
    FOR JSON AUTO, ROOT('products');

END
GO
