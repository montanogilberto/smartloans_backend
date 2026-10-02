-- =============================================================================
-- Add a Services catalog + expenses.serviceId, for expenseType='general'.
-- =============================================================================
-- Forward-only, additive migration. Mirrors 2026-09-03_add_expense_payroll.sql's
-- own pattern (that one added employeeId for 'payroll'; this adds serviceId
-- for 'general').
--
-- WHY: "Proveedor" (Suppliers) models a goods vendor -- Sam's Club, Costco,
-- someone you buy inventory FROM. A recurring bill -- CFE (electricity),
-- water, internet, rent -- isn't that: there's no inventory, no SKU, just a
-- fixed-ish periodic charge. Forcing those through supplierId meant creating
-- a fake "Supplier" row per utility, corrupting "who did we actually buy
-- goods from" reporting. This adds a dbo.Services catalog (cloned 1:1 from
-- dbo.Suppliers' shape/CRUD pattern in sql_logic/sp_supplier.sql) and a
-- serviceId column expenseType='general' now uses instead of supplierId.
--
-- SCOPE:
--   - New dbo.Services table + sp_services/sp_services_all/sp_services_one,
--     cloned from the Suppliers trio (same per-company duplicate-name check,
--     same action 1/2/3 = INSERT/UPDATE/DELETE shape). Unlike sp_suppliers_all
--     (which reads a stray, seemingly-unused '$.plural' JSON path), sp_services_all
--     reads '$.services[0].companyId' -- the same array-wrapped convention
--     every other SP in this backend uses.
--   - expenses.serviceId INT NULL added, with an FK to dbo.Services.
--   - CK_expenses_party is replaced with a non-breaking, backward-compatible
--     version: 'general' rows now need supplierId OR serviceId (not exactly
--     one), so every existing 'general' row (which already has supplierId,
--     no serviceId) keeps satisfying the constraint. Only going forward does
--     sp_expense actually require serviceId (not supplierId) for new
--     'general' inserts -- see below. 'inventory' still strictly requires
--     supplierId; 'payroll' still strictly requires employeeId. Both unchanged.
-- Then CREATE OR ALTERs [dbo].[sp_expense]: action=1 (INSERT) now requires
-- serviceId (not supplierId) when expenseType='general', validates it exists
-- in dbo.Services for the same company, and nulls supplierId for that row
-- (mirroring exactly how payroll already nulls supplierId today). Inventory
-- behavior (still supplierId-only) is completely unchanged. action=2
-- (UPDATE) can now optionally update serviceId too.
--
-- KNOWN LIMITATION (explicitly accepted, carried over from the payroll
-- migration): [dbo].[sp_expense_all]'s SELECT list wasn't available to
-- either that migration or this one (live DB drift vs this repo's checked-in
-- SQL, see memory note on schema drift) -- it still needs a manual update to
-- return serviceId/service name for the Egresos list page to show it. Until
-- then, a 'general' expense created against serviceId will still show no
-- party name in that list, same gap employeeId already has.
-- =============================================================================

-- ─── dbo.Services ────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.Services', 'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Services] (
        [serviceId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [companyId] INT NOT NULL,
        [serviceName] NVARCHAR(200) NOT NULL,
        [description] NVARCHAR(MAX),
        [active] NVARCHAR(1) NOT NULL DEFAULT '1',
        [created_At] DATETIME NOT NULL DEFAULT GETDATE(),
        [updated_at] DATETIME,
        FOREIGN KEY ([companyId]) REFERENCES [dbo].[companies]([companyId])
    );

    CREATE INDEX IX_Services_CompanyId ON [dbo].[Services] ([companyId]);
    CREATE INDEX IX_Services_ServiceName ON [dbo].[Services] ([serviceName]);
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_services]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage VARCHAR(MAX);
    DECLARE @Action INT;

    DECLARE @payload TABLE (
        action INT,
        serviceId INT,
        companyId INT,
        serviceName NVARCHAR(200),
        description NVARCHAR(MAX),
        active NVARCHAR(1)
    );

    INSERT INTO @payload (action, serviceId, companyId, serviceName, description, active)
    SELECT
        JSON_VALUE(value, '$.action'),
        JSON_VALUE(value, '$.serviceId'),
        JSON_VALUE(value, '$.companyId'),
        JSON_VALUE(value, '$.serviceName'),
        JSON_VALUE(value, '$.description'),
        JSON_VALUE(value, '$.active')
    FROM OPENJSON(@pjsonfile, '$.services');

    SELECT @Action = action FROM @payload;

    IF @Action = 1 -- INSERT
    BEGIN
        IF EXISTS (SELECT 1 FROM [dbo].[Services] s JOIN @payload p ON s.companyId = p.companyId AND s.serviceName = p.serviceName WHERE p.action = 1)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Ya existe un servicio con ese nombre para esta empresa."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        INSERT INTO [dbo].[Services] (companyId, serviceName, description, active, created_At)
        SELECT companyId, serviceName, description, ISNULL(NULLIF(active, ''), '1'), GETDATE()
        FROM @payload
        WHERE action = 1;

        SET @Outputmessage = (SELECT '{{"status": "success", "message": "Service inserted successfully."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE IF @Action = 2 -- UPDATE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [dbo].[Services] s JOIN @payload p ON s.serviceId = p.serviceId WHERE p.action = 2)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Service not found."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        IF EXISTS (SELECT 1 FROM [dbo].[Services] s JOIN @payload p ON s.companyId = p.companyId AND s.serviceName = p.serviceName WHERE p.action = 2 AND s.serviceId != p.serviceId)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Ya existe otro servicio con ese nombre para esta empresa."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        UPDATE s
        SET
            s.companyId = p.companyId,
            s.serviceName = p.serviceName,
            s.description = p.description,
            s.active = p.active,
            s.updated_at = GETDATE()
        FROM [dbo].[Services] s
        JOIN @payload p ON s.serviceId = p.serviceId
        WHERE p.action = 2;

        SET @Outputmessage = (SELECT '{{"status": "success", "message": "Service updated successfully."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE IF @Action = 3 -- DELETE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [dbo].[Services] s JOIN @payload p ON s.serviceId = p.serviceId WHERE p.action = 3)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Service not found."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        IF EXISTS (SELECT 1 FROM [dbo].[expenses] e JOIN @payload p ON e.serviceId = p.serviceId WHERE p.action = 3)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "No se puede eliminar: hay egresos registrados con este servicio."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        DELETE s
        FROM [dbo].[Services] s
        JOIN @payload p ON s.serviceId = p.serviceId
        WHERE p.action = 3;

        SET @Outputmessage = (SELECT '{{"status": "success", "message": "Service deleted successfully."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE
    BEGIN
        SET @Outputmessage = (SELECT '{{"status": "error", "message": "Invalid action specified."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END

Finish:
    SELECT @Outputmessage AS [jsonResult];
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_services_all]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @companyId INT = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')) FROM OPENJSON(@pjsonfile, '$.services')
    );

    SELECT
        s.serviceId,
        s.companyId,
        s.serviceName,
        ISNULL(s.description, '') AS description,
        s.active,
        CONVERT(VARCHAR(30), s.created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), s.updated_at, 126), '') AS updated_at
    FROM [dbo].[Services] s
    WHERE s.companyId = @companyId OR @companyId IS NULL
    ORDER BY s.serviceName
    FOR JSON AUTO, ROOT('services');
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_services_one]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @serviceId INT = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.serviceId')) FROM OPENJSON(@pjsonfile, '$.services')
    );
    DECLARE @companyId INT = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')) FROM OPENJSON(@pjsonfile, '$.services')
    );

    SELECT
        s.serviceId,
        s.companyId,
        s.serviceName,
        ISNULL(s.description, '') AS description,
        s.active,
        CONVERT(VARCHAR(30), s.created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), s.updated_at, 126), '') AS updated_at
    FROM [dbo].[Services] s
    WHERE s.serviceId = @serviceId AND s.companyId = @companyId
    FOR JSON AUTO, ROOT('services');
END;
GO

-- ─── dbo.expenses.serviceId ──────────────────────────────────────────────────
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.expenses') AND name = 'serviceId'
)
BEGIN
    ALTER TABLE [dbo].[expenses] ADD serviceId INT NULL;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_expenses_serviceId'
)
BEGIN
    ALTER TABLE [dbo].[expenses]
        ADD CONSTRAINT FK_expenses_serviceId FOREIGN KEY (serviceId)
        REFERENCES [dbo].[Services] (serviceId);
END
GO

-- Replace CK_expenses_party with a backward-compatible version: 'general'
-- now accepts supplierId OR serviceId (not exactly one), so every existing
-- 'general' row (supplierId set, serviceId NULL) still satisfies it. Only
-- sp_expense's own INSERT logic (below) actually prefers/requires serviceId
-- for NEW 'general' rows going forward.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_expenses_party')
BEGIN
    ALTER TABLE [dbo].[expenses] DROP CONSTRAINT CK_expenses_party;
END
GO

ALTER TABLE [dbo].[expenses]
    ADD CONSTRAINT CK_expenses_party CHECK (
        (expenseType = 'payroll' AND employeeId IS NOT NULL AND supplierId IS NULL AND serviceId IS NULL)
        OR
        (expenseType = 'general' AND employeeId IS NULL AND (supplierId IS NOT NULL OR serviceId IS NOT NULL))
        OR
        (expenseType = 'inventory' AND employeeId IS NULL AND serviceId IS NULL AND supplierId IS NOT NULL)
    );
GO

-- =============================================================================
-- sp_expense — action=1's required party is now:
--   inventory -> supplierId (unchanged)
--   general   -> serviceId (NEW; was supplierId)
--   payroll   -> employeeId (unchanged)
-- Full CREATE OR ALTER (not a diff), same as the payroll migration.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER   PROC [dbo].[sp_expense]
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
