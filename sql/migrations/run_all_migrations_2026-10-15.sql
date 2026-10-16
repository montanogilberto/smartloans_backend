/* =============================================================================
   ALL FORWARD MIGRATIONS — single execution against the EXISTING live DB
   Generated 2026-10-15 from sql/migration_history/migrations/ (67 forward files, *_ROLLBACK.sql excluded)
   Do NOT edit by hand: regenerate from sql/migration_history/migrations/ if a file changes.
   =============================================================================
   Not included: sql/migration_history/snapshot_2026-08-15/ (01_schema / 02_programmability / 03_data). That
   folder is a full snapshot (2026-08-15) for building a NEW empty DB; running it
   on the live DB would duplicate data (03_data is not idempotent).

   HOW TO RUN (pick one):
     sqlcmd -b -S <server> -d <database> -U <user> -i sql/migrations/run_all_migrations_2026-10-15.sql
        -b = stop at the first error (recommended).
     SSMS / Azure Data Studio: open the file, select the live DB, Execute.
        SSMS keeps going after a failed batch — read the Messages tab for
        "Msg" errors, and use the ">>> [nn/67]" markers to see where it was.

   SAFE TO RE-RUN: every file is written idempotent (IF NOT EXISTS / COL_LENGTH
   guards, CREATE OR ALTER, MERGE, data fixes that only touch unfixed rows).
   Files run in date order, so a file that redeploys an SP that a later file
   changes again ends with the later version.

   Some files return BEFORE/AFTER result sets (accounting repairs) — expected.
   Three files (10-01d, 10-01h, 10-01j) refuse to alter sp_journalEntries if the
   live definition drifted from the repo (RAISERROR + NOEXEC); that error is a
   deliberate stop, not a bug.

   ORDER:
     01. 2026-08-11_add_capital_vocabulary.sql
     02. 2026-08-13_add_offer_consent.sql
     03. 2026-09-02_add_expense_type_notes_receipturl.sql
     04. 2026-09-03_add_expense_payroll.sql
     05. 2026-09-08_add_notificationDispatch.sql
     06. 2026-09-10_fix_ticket_tracking_print_action.sql
     07. 2026-09-11_add_income_monthly.sql
     08. 2026-09-11_add_pos_support_chat.sql
     09. 2026-09-12_add_client_login_codes.sql
     10. 2026-09-14_add_pos_client_type.sql
     11. 2026-09-14_add_pos_support_chat_close_conversation.sql
     12. 2026-09-14_fix_pos_support_chat_list_messages_scoping.sql
     13. 2026-09-18_backfill_clienttype_pos_companies.sql
     14. 2026-09-18_rename_client_role_to_pos.sql
     15. 2026-09-23_add_income_one.sql
     16. 2026-09-23_add_loanInstallments_one.sql
     17. 2026-09-23_add_ml_oauth_states_sp.sql
     18. 2026-09-23_add_ml_tokens_sp.sql
     19. 2026-09-23_add_notificationDispatchPolicy_one.sql
     20. 2026-09-23_add_notificationDispatches_lookup.sql
     21. 2026-09-23_add_pushNotifications_resolveUsers.sql
     22. 2026-09-23_add_reservations.sql
     23. 2026-09-23_add_userCompanies_role.sql
     24. 2026-09-23_ticket_discount_fields.sql
     25. 2026-09-24_reservation_catalogs.sql
     26. 2026-09-28_whatsapp_channels.sql
     27. 2026-09-29_income_monthly_any_month.sql
     28. 2026-09-30_add_employees_ui_feature.sql
     29. 2026-09-30_employees_companyId.sql
     30. 2026-09-30_expense_all_return_new_columns.sql
     31. 2026-09-30_expense_monthly.sql
     32. 2026-09-30_fix_expense_paymentdate_midnight.sql
     33. 2026-09-30_fix_income_monthly_dateadd.sql
     34. 2026-09-30_fix_statuses_table_rename.sql
     35. 2026-09-30_income_terminal_commission.sql
     36. 2026-09-30_mercadopago_rate_4_2.sql
     37. 2026-09-30_redeploy_commissionTerminals_sps.sql
     38. 2026-09-30_redeploy_sp_suppliers_quoted_identifier.sql
     39. 2026-10-01_fix_trialBalance_aggregation.sql
     40. 2026-10-01b_journal_accountTotals_fn.sql
     41. 2026-10-01c_chartOfAccounts_ensure_base.sql
     42. 2026-10-01d_journalEntries_duplicate_guard.sql
     43. 2026-10-01e_backfill_income_commissions_sp.sql
     44. 2026-10-01f_run_income_commission_backfill.sql
     45. 2026-10-01g_income_reverse_on_delete.sql
     46. 2026-10-01h_opening_balance_guard.sql
     47. 2026-10-01i_reconcile_and_backfill_movements.sql
     48. 2026-10-01j_run_books_period_repair.sql
     49. 2026-10-01k_add_income_payments.sql
     50. 2026-10-01k_balance_sheet.sql
     51. 2026-10-01l_add_expense_service.sql
     52. 2026-10-01l_correct_entry_dates.sql
     53. 2026-10-01m_run_correct_entry_dates.sql
     54. 2026-10-02_expense_return_serviceid.sql
     55. 2026-10-02b_expense_item_quantity_cost_supplies.sql
     56. 2026-10-02c_company_token_ledger.sql
     57. 2026-10-02c_expense_ledger_sync_reads.sql
     58. 2026-10-06_backfill_client_companyId_from_sales.sql
     59. 2026-10-07_products_net_content_no_expire.sql
     60. 2026-10-11_products_auto_code.sql
     61. 2026-10-11b_products_by_company_all_products.sql
     62. 2026-10-15_products_productCategoryId.sql
     63. 2026-10-15b_products_by_company_category_filter.sql
     64. 2026-10-15c_inventory_single_source.sql
     65. 2026-10-15d_catalog_hierarchy.sql
     66. 2026-10-15e_option_choice_measurements.sql
     67. 2026-10-16_gmo_catalog.sql
   ============================================================================= */

SET NOCOUNT ON;
GO

-- #############################################################################
-- [01/67] 2026-08-11_add_capital_vocabulary.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [01/67] 2026-08-11_add_capital_vocabulary.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- PR1b — Add CAPITAL_* entryType vocabulary to walletTransactions_entryType
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- this file is the reviewable artifact; see MD/PR1B_CAPITAL_VOCABULARY_MIGRATION.md
-- for the full scope boundary and MD/PAYMENT_SCHEMA_RECONCILIATION.md (PR1a,
-- github.com/montanogilberto/smartloans_backend/pull/66) for the verified live
-- baseline this migration is built against.
--
-- SCOPE: adds exactly 3 new rows to the existing dbo.walletTransactions_entryType
-- lookup table. Nothing else. Does not touch existing DEPOSIT/WITHDRAWAL/
-- LOAN_FUNDING/... rows or their historical walletTransactions entries (7 live
-- rows as of 2026-08-11, never rewritten); does not touch clientWallets,
-- bankAccounts/bankAccountSnapshots, transfers/STP, or Stripe; moves no real
-- money.
--
-- Idempotent: mirrors the exact MERGE ... WHEN NOT MATCHED pattern already
-- live in sql/sp_walletTransactions.sql:18-36 — safe to run more than once.
--
-- Semantics (see MD/PAYMENT_SCHEMA_RECONCILIATION.md "Semantic boundary"):
-- these three values describe lender-declared capital availability/commitment
-- state. They must never be interpreted as SmartLoans holding, receiving, or
-- moving the lender's money — no writer of these entryTypes should ever imply
-- custody.
-- =============================================================================

MERGE [dbo].[walletTransactions_entryType] AS t
USING (VALUES
    ('CAPITAL_DECLARED',   14, 'Lender declares capital available to lend -- no money received by SmartLoans'),
    ('CAPITAL_COMMITTED',  15, 'Capital committed to a loan funding (lender sent SPEI w/ evidence) -- no money via SmartLoans'),
    ('CAPITAL_UNDECLARED', 16, 'Previously declared capital released/withdrawn by the lender -- no money returned by SmartLoans')
) AS s (entryType, sortOrder, description)
ON t.entryType = s.entryType
WHEN NOT MATCHED THEN
    INSERT (entryType, sortOrder, description) VALUES (s.entryType, s.sortOrder, s.description);
GO

-- #############################################################################
-- [02/67] 2026-08-13_add_offer_consent.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [02/67] 2026-08-13_add_offer_consent.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add consentAccepted / consentAcceptedAt to dbo.loanOffers
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, then re-run
-- sql/sp_loanOffers.sql to update the stored procedures.
--
-- WHY: "Publicar capital disponible" gates the submit button on a checkbox
-- ("Declaro que el capital indicado está disponible..."), but the agreement
-- itself was never persisted anywhere — only enforced client-side. This adds
-- a durable, per-offer audit record of that consent.
--
-- SCOPE: adds exactly 2 nullable/defaulted columns to the existing
-- dbo.loanOffers table. Does not touch any other table, does not rewrite
-- existing rows (they get consentAccepted=0/consentAcceptedAt=NULL, which is
-- honest — they predate this feature and never captured explicit consent).
-- Idempotent: guarded by sys.columns existence checks, safe to run more than
-- once.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.loanOffers') AND name = 'consentAccepted'
)
BEGIN
    ALTER TABLE [dbo].[loanOffers] ADD consentAccepted BIT NOT NULL DEFAULT 0;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.loanOffers') AND name = 'consentAcceptedAt'
)
BEGIN
    -- DATETIME (not DATETIME2) to match every other timestamp column already
    -- in this table (sp_loanOffers.sql's own comment: factory reviewer_agent
    -- auto-errors DATETIME2 outside IOT modules).
    ALTER TABLE [dbo].[loanOffers] ADD consentAcceptedAt DATETIME NULL;
END
GO

-- #############################################################################
-- [03/67] 2026-09-02_add_expense_type_notes_receipturl.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [03/67] 2026-09-02_add_expense_type_notes_receipturl.sql', 0, 1) WITH NOWAIT;
GO

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

-- #############################################################################
-- [04/67] 2026-09-03_add_expense_payroll.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [04/67] 2026-09-03_add_expense_payroll.sql', 0, 1) WITH NOWAIT;
GO

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

-- #############################################################################
-- [05/67] 2026-09-08_add_notificationDispatch.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [05/67] 2026-09-08_add_notificationDispatch.sql', 0, 1) WITH NOWAIT;
GO

-- notificationDispatch: cost-minimizing Push -> WhatsApp -> SMS notification cascade.
-- See docs/notifications-income-expenses-tickets.md (frontend repo) for the full design.

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'notificationDispatch_status')
CREATE TABLE [dbo].[notificationDispatch_status] (
    statusCode  NVARCHAR(20) NOT NULL,
    description NVARCHAR(100) NOT NULL,
    created_At  DATETIME NOT NULL DEFAULT GETDATE(),
    updated_at  DATETIME NULL,
    CONSTRAINT PK_notificationDispatch_status PRIMARY KEY CLUSTERED (statusCode)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'notificationDispatch_policy')
CREATE TABLE [dbo].[notificationDispatch_policy] (
    eventName           NVARCHAR(40) NOT NULL,
    channel_list_json   NVARCHAR(MAX) NOT NULL,
    allow_sms_fallback  BIT NOT NULL DEFAULT 0,
    created_At          DATETIME NOT NULL DEFAULT GETDATE(),
    updated_at          DATETIME NULL,
    CONSTRAINT PK_notificationDispatch_policy PRIMARY KEY CLUSTERED (eventName)
);
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'notificationDispatches')
CREATE TABLE [dbo].[notificationDispatches] (
    notificationDispatchId  INT IDENTITY(1,1) NOT NULL,
    companyId               INT NOT NULL,
    sourceType              NVARCHAR(20) NOT NULL,
    sourceId                INT NOT NULL,
    recipientType           NVARCHAR(10) NOT NULL,
    recipientId             INT NOT NULL,
    eventName               NVARCHAR(40) NOT NULL,
    preferredChannel        NVARCHAR(20) NOT NULL,
    selectedChannel         NVARCHAR(20) NOT NULL,
    attemptedChannels       NVARCHAR(MAX) NOT NULL,
    fallbackReason          NVARCHAR(30) NULL,
    status                  NVARCHAR(20) NOT NULL,
    providerMessageId       NVARCHAR(100) NULL,
    providerName            NVARCHAR(30) NULL,
    messagePreview          NVARCHAR(200) NULL,
    sentAt                  DATETIME NULL,
    confirmedAt             DATETIME NULL,
    failedAt                DATETIME NULL,
    created_At              DATETIME NOT NULL DEFAULT GETDATE(),
    updated_at              DATETIME NULL,
    CONSTRAINT PK_notificationDispatches PRIMARY KEY CLUSTERED (notificationDispatchId),
    CONSTRAINT FK_notificationDispatches_companies FOREIGN KEY (companyId) REFERENCES dbo.companies(companyId),
    CONSTRAINT FK_notificationDispatches_policy FOREIGN KEY (eventName) REFERENCES dbo.notificationDispatch_policy(eventName),
    CONSTRAINT FK_notificationDispatches_status FOREIGN KEY (status) REFERENCES dbo.notificationDispatch_status(statusCode)
);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_companyId' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_companyId ON dbo.notificationDispatches (companyId);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_status' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_status ON dbo.notificationDispatches (status);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_eventName' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_eventName ON dbo.notificationDispatches (eventName);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_sourceType_sourceId' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_sourceType_sourceId ON dbo.notificationDispatches (sourceType, sourceId);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_recipientType_recipientId' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_recipientType_recipientId ON dbo.notificationDispatches (recipientType, recipientId);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_providerMessageId' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_providerMessageId ON dbo.notificationDispatches (providerMessageId);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_notificationDispatches_sentAt' AND object_id = OBJECT_ID('dbo.notificationDispatches'))
CREATE NONCLUSTERED INDEX IX_notificationDispatches_sentAt ON dbo.notificationDispatches (sentAt);
GO

-- Seed: status lookup (required by FK_notificationDispatches_status)
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_status WHERE statusCode = 'pending')
INSERT INTO dbo.notificationDispatch_status (statusCode, description) VALUES ('pending', 'Row created, no channel resolved yet');
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_status WHERE statusCode = 'sent')
INSERT INTO dbo.notificationDispatch_status (statusCode, description) VALUES ('sent', 'Dispatched successfully on selectedChannel');
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_status WHERE statusCode = 'confirmed')
INSERT INTO dbo.notificationDispatch_status (statusCode, description) VALUES ('confirmed', 'Provider delivery callback confirmed receipt');
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_status WHERE statusCode = 'failed')
INSERT INTO dbo.notificationDispatch_status (statusCode, description) VALUES ('failed', 'Every channel in the cascade was exhausted without success');
GO

-- Seed: starting cascade policy per event (required by FK_notificationDispatches_policy).
-- Adjust freely -- this table is meant to be edited without a code deploy.
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'income_created')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('income_created', '["push","whatsapp","sms"]', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'ticket_ready')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('ticket_ready', '["push","whatsapp","sms"]', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.notificationDispatch_policy WHERE eventName = 'expense_created')
INSERT INTO dbo.notificationDispatch_policy (eventName, channel_list_json, allow_sms_fallback)
VALUES ('expense_created', '["push","whatsapp"]', 0);
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
        failedAt                DATETIME NULL
    );

    INSERT INTO @payload (
        notificationDispatchId, companyId, sourceType, sourceId, recipientType, recipientId,
        eventName, preferredChannel, selectedChannel, attemptedChannels, fallbackReason, status,
        providerMessageId, providerName, messagePreview, sentAt, confirmedAt, failedAt
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
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.failedAt'))
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
                created_At, updated_at
            )
            SELECT
                p.companyId, p.sourceType, p.sourceId, p.recipientType, p.recipientId, p.eventName,
                p.preferredChannel, p.selectedChannel, p.attemptedChannels, p.fallbackReason, p.status,
                p.providerMessageId, p.providerName, p.messagePreview, p.sentAt, p.confirmedAt, p.failedAt,
                GETDATE(), NULL
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
                updated_at = GETDATE()
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

CREATE OR ALTER PROC [dbo].[sp_notificationDispatches_all] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT;
    SET @companyId = TRY_CONVERT(INT,
        (SELECT TOP 1 JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.notificationDispatches'))
    );

    SELECT
        [notificationDispatchId],
        ISNULL([companyId], 0) AS companyId,
        ISNULL([sourceType], '') AS sourceType,
        ISNULL([sourceId], 0) AS sourceId,
        ISNULL([recipientType], '') AS recipientType,
        ISNULL([recipientId], 0) AS recipientId,
        ISNULL([eventName], '') AS eventName,
        ISNULL([preferredChannel], '') AS preferredChannel,
        ISNULL([selectedChannel], '') AS selectedChannel,
        ISNULL([attemptedChannels], '') AS attemptedChannels,
        ISNULL([fallbackReason], '') AS fallbackReason,
        ISNULL([status], '') AS status,
        ISNULL([providerMessageId], '') AS providerMessageId,
        ISNULL([providerName], '') AS providerName,
        ISNULL([messagePreview], '') AS messagePreview,
        ISNULL(CONVERT(VARCHAR(30), sentAt, 126), '') AS sentAt,
        ISNULL(CONVERT(VARCHAR(30), confirmedAt, 126), '') AS confirmedAt,
        ISNULL(CONVERT(VARCHAR(30), failedAt, 126), '') AS failedAt,
        [created_At],
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.notificationDispatches
    WHERE companyId = @companyId
    FOR JSON AUTO, ROOT('notificationDispatches');
END
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatches_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @notificationDispatchId INT;
    SET @notificationDispatchId = CAST(
        (SELECT TOP 1 JSON_VALUE(value, '$.notificationDispatchId')
         FROM OPENJSON(@pjsonfile, '$.notificationDispatches')) AS INT
    );

    SELECT
        [notificationDispatchId],
        ISNULL([companyId], 0) AS companyId,
        ISNULL([sourceType], '') AS sourceType,
        ISNULL([sourceId], 0) AS sourceId,
        ISNULL([recipientType], '') AS recipientType,
        ISNULL([recipientId], 0) AS recipientId,
        ISNULL([eventName], '') AS eventName,
        ISNULL([preferredChannel], '') AS preferredChannel,
        ISNULL([selectedChannel], '') AS selectedChannel,
        ISNULL([attemptedChannels], '') AS attemptedChannels,
        ISNULL([fallbackReason], '') AS fallbackReason,
        ISNULL([status], '') AS status,
        ISNULL([providerMessageId], '') AS providerMessageId,
        ISNULL([providerName], '') AS providerName,
        ISNULL([messagePreview], '') AS messagePreview,
        ISNULL(CONVERT(VARCHAR(30), sentAt, 126), '') AS sentAt,
        ISNULL(CONVERT(VARCHAR(30), confirmedAt, 126), '') AS confirmedAt,
        ISNULL(CONVERT(VARCHAR(30), failedAt, 126), '') AS failedAt,
        [created_At],
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.notificationDispatches
    WHERE notificationDispatchId = @notificationDispatchId
    FOR JSON AUTO, ROOT('notificationDispatches');
END
GO

-- #############################################################################
-- [06/67] 2026-09-10_fix_ticket_tracking_print_action.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [06/67] 2026-09-10_fix_ticket_tracking_print_action.sql', 0, 1) WITH NOWAIT;
GO

-- sp_ticket_tracking never had a branch for @action = 'print' -- every call
-- from the receipt print flow fell through with no SELECT ever executing,
-- so pymssql's fetchone() raised "Statement not executed or executed
-- statement has no resultset" on every single print (500, tracking lost).
-- This adds a 'print' branch mirroring the existing 'whatsapp'/'sms' ones.

CREATE OR ALTER PROC [dbo].[sp_ticket_tracking]
(
    @pjsonfile NVARCHAR(MAX)
)
AS
BEGIN

    SET NOCOUNT ON;

    DECLARE
        @action VARCHAR(50),
        @incomeId INT,
        @companyId INT,
        @fileName VARCHAR(500),
        @containerName VARCHAR(100),
        @receiptUrl VARCHAR(MAX),
        @phone VARCHAR(50);

    SELECT
        @action = JSON_VALUE(@pjsonfile,'$.ticket[0].action'),
        @incomeId = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.ticket[0].incomeId')),
        @companyId = TRY_CONVERT(INT,JSON_VALUE(@pjsonfile,'$.ticket[0].companyId')),
        @fileName = JSON_VALUE(@pjsonfile,'$.ticket[0].fileName'),
        @containerName = JSON_VALUE(@pjsonfile,'$.ticket[0].containerName'),
        @receiptUrl = JSON_VALUE(@pjsonfile,'$.ticket[0].receiptUrl'),
        @phone = JSON_VALUE(@pjsonfile,'$.ticket[0].phone');

    ---------------------------------------------------------
    -- VALIDATE
    ---------------------------------------------------------
    IF @action = 'validate'
    BEGIN

        SELECT
            ticketId,
            incomeId,
            shortCode,
            fileName,
            receiptUrl,
            uploadAzure,
            whatsappSent,
            smsSent,
            printed,
            printedDate,
            generationStatus,
            generatedDate,
            errorMessage
        FROM dbo.tickets
        WHERE incomeId = @incomeId
        FOR JSON PATH, ROOT('tickets');

        RETURN;

    END

    ---------------------------------------------------------
    -- SAVE RECEIPT
    ---------------------------------------------------------
    IF @action = 'save'
    BEGIN

        IF EXISTS
        (
            SELECT 1
            FROM dbo.tickets
            WHERE incomeId = @incomeId
        )
        BEGIN

            UPDATE dbo.tickets
            SET
                companyId = @companyId,
                fileName = @fileName,
                containerName = @containerName,
                receiptUrl = @receiptUrl,
                uploadAzure = 1,
                uploadAzureDate = GETDATE(),
                updated_At = GETDATE()
            WHERE incomeId = @incomeId;

            -- Generate shortCode if missing
            UPDATE dbo.tickets
            SET shortCode = CONCAT('T', incomeId)
            WHERE incomeId = @incomeId
              AND shortCode IS NULL;

        END
        ELSE
        BEGIN

            INSERT INTO dbo.tickets
            (
                incomeId,
                companyId,
                fileName,
                containerName,
                receiptUrl,
                shortCode,
                uploadAzure,
                uploadAzureDate,
                created_At
            )
            VALUES
            (
                @incomeId,
                @companyId,
                @fileName,
                @containerName,
                @receiptUrl,
                CONCAT('T', @incomeId),
                1,
                GETDATE(),
                GETDATE()
            );

        END

        SELECT
            1 AS success,
            'Receipt saved' AS message
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- WHATSAPP SUCCESS
    ---------------------------------------------------------
    IF @action = 'whatsapp'
    BEGIN

        UPDATE dbo.tickets
        SET
            whatsappSent = 1,
            whatsappSentDate = GETDATE(),
            whatsappPhone = @phone,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- SMS SUCCESS
    ---------------------------------------------------------
    IF @action = 'sms'
    BEGIN

        UPDATE dbo.tickets
        SET
            smsSent = 1,
            smsSentDate = GETDATE(),
            smsPhone = @phone,
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

    ---------------------------------------------------------
    -- PRINT SUCCESS (new -- this branch never existed before)
    ---------------------------------------------------------
    IF @action = 'print'
    BEGIN

        UPDATE dbo.tickets
        SET
            printed = 1,
            printedDate = GETDATE(),
            updated_At = GETDATE()
        WHERE incomeId = @incomeId;

        SELECT
            1 AS success
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

        RETURN;

    END

END
GO

-- #############################################################################
-- [07/67] 2026-09-11_add_income_monthly.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [07/67] 2026-09-11_add_income_monthly.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_income_monthly — current-month, single-company income read
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: GET /all_income (dbo.sp_income_all) returns every income row ever
-- recorded, across every company, with no filter at all. The POS Dashboard
-- only needs the current month's numbers for its own company, but was still
-- paying to transfer and parse the entire history (674+ rows and growing)
-- on every load/refresh. dbo.sp_income_all is left untouched — the Incomes
-- module (src/pages/finance/IncomesPage.tsx, MovementsPage.tsx) still needs
-- the full history for browsing/searching past records.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Factory convention: every SP (reads included) takes a single
--     @pjsonfile VARCHAR(MAX) and pulls its fields via JSON_VALUE/OPENJSON —
--     no typed SQL parameters. Caller passes {"income":[{"companyId": N}]},
--     matching the JSON root key sp_income/sp_income_all already use for
--     this module.
--   - companyId is mandatory (multi-tenancy rule — never return
--     cross-company data). sp_income_all's lack of a companyId filter is a
--     pre-existing gap this migration does not attempt to fix.
--   - "Current month" is computed in Hermosillo local time (UTC-7, no DST),
--     matching src/utils/format.ts::toHermosilloDate on the frontend — the
--     same convention used for every other monthly total in the app.
--     paymentDate is stored as UTC (no offset marker), so the month boundary
--     is converted back to UTC before filtering.
--   - Same output shape/columns as sp_income_all, so the frontend can reuse
--     its existing Income type.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_income_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN
    DECLARE @companyId INT;
    SET @companyId = TRY_CONVERT(INT,
        (SELECT TOP 1 JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.income'))
    );

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7,
        DATEFROMPARTS(YEAR(@HermosilloNow), MONTH(@HermosilloNow), 1));
    DECLARE @MonthEndUtc DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);

    IF EXISTS (
        SELECT 1 FROM [dbo].[income]
        WHERE companyId = @companyId
          AND paymentDate >= @MonthStartUtc
          AND paymentDate < @MonthEndUtc
    )
    BEGIN
        SELECT
            i.incomeId,
            i.orderId,
            i.total,
            i.paymentMethod,
            i.paymentDate,
            i.userId,
            i.clientId,
            i.companyId,
            ISNULL(i.discountAmount,0) AS discountAmount
        FROM [dbo].[income] i
        WHERE i.companyId = @companyId
          AND i.paymentDate >= @MonthStartUtc
          AND i.paymentDate < @MonthEndUtc
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [income]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO

-- #############################################################################
-- [08/67] 2026-09-11_add_pos_support_chat.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [08/67] 2026-09-11_add_pos_support_chat.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.posSupportConversations / dbo.posSupportMessages + sp_posSupportChat
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: new "Soporte POS" chat, distinct from the existing loanChat (borrower/
-- lender loan negotiation) — a POS cashier/admin chatting with a topic-scoped
-- support agent (Clientes now; Income/Expenses/Accounting planned later, see
-- LoanAgents_SmartLoans' agents/pos_clients_support). Deliberately a much
-- simpler schema than loanConversations/loanMessages: no borrower/lender
-- roles, no proposal/amount/rate fields — just one user, one topic, messages.
--
-- SCOPE:
--   - dbo.posSupportConversations: one row per (companyId, userId, topic) —
--     reused across messages the same way loanChat reuses an 'open' thread.
--   - dbo.posSupportMessages: senderRole 'user'|'agent'.
--   - sp_posSupportChat actions: start_conversation | send_message |
--     list_messages | list_conversations — same @pjsonfile/JSON-result shape
--     as sp_loanChat (single-row FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), so
--     modules/posSupportChat.py's _sp() helper is a straight copy of
--     modules/loanChat.py's.
--   - topic is free-text NVARCHAR(20), not a CHECK-constrained enum: new
--     topics (income/expenses/accounting) are additive, no migration needed
--     to add one — validation of which topics are actually wired to an agent
--     lives in the backend module, not the schema.
-- Idempotent: CREATE OR ALTER is always safe to re-run; tables guarded by
-- sys.tables existence checks.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posSupportConversations')
CREATE TABLE [dbo].[posSupportConversations] (
    conversationId  INT IDENTITY PRIMARY KEY,
    companyId       INT NOT NULL,
    userId          INT NOT NULL,
    topic           NVARCHAR(20) NOT NULL,     -- 'clients' | 'income' | 'expenses' | 'accounting'
    status          NVARCHAR(20) NOT NULL DEFAULT 'open',
    lastMessageAt   DATETIME2 NULL,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2 NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posSupportMessages')
CREATE TABLE [dbo].[posSupportMessages] (
    messageId       INT IDENTITY PRIMARY KEY,
    conversationId  INT NOT NULL,
    senderRole      NVARCHAR(10) NOT NULL,     -- 'user' | 'agent'
    body            NVARCHAR(MAX) NULL,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE()
)
GO

CREATE OR ALTER PROC [dbo].[sp_posSupportChat]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.chat[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.chat[0].companyId')
    DECLARE @conversationId  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].conversationId')
    DECLARE @userId          INT           = JSON_VALUE(@pjsonfile, '$.chat[0].userId')
    DECLARE @topic           NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.chat[0].topic')

    -- ── start_conversation ───────────────────────────────────
    -- Reuses this user's existing open conversation for the topic, same
    -- one-open-thread-per-pair idiom as sp_loanChat's start_conversation.
    IF @action = 'start_conversation'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM posSupportConversations
            WHERE companyId = @companyId AND userId = @userId
              AND topic = @topic AND status = 'open'
        )
        BEGIN
            SELECT (SELECT TOP 1 conversationId, companyId, userId, topic,
                status, lastMessageAt, created_At
                FROM posSupportConversations
                WHERE companyId = @companyId AND userId = @userId
                  AND topic = @topic AND status = 'open'
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
        ELSE
        BEGIN
            INSERT INTO posSupportConversations
                (companyId, userId, topic, lastMessageAt)
            VALUES
                (@companyId, @userId, @topic, GETUTCDATE())

            DECLARE @newConvId INT = SCOPE_IDENTITY()
            SELECT (SELECT conversationId, companyId, userId, topic,
                status, created_At
                FROM posSupportConversations WHERE conversationId = @newConvId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
    END

    -- ── send_message ─────────────────────────────────────────
    ELSE IF @action = 'send_message'
    BEGIN
        DECLARE @senderRole NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')
        DECLARE @body       NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.chat[0].body')

        INSERT INTO posSupportMessages (conversationId, senderRole, body)
        VALUES (@conversationId, @senderRole, @body)

        DECLARE @newMsgId INT = SCOPE_IDENTITY()

        UPDATE posSupportConversations
        SET lastMessageAt = GETUTCDATE(), updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId

        SELECT (SELECT @newMsgId AS messageId, @conversationId AS conversationId,
            @senderRole AS senderRole, @body AS body
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    -- ── list_messages ─────────────────────────────────────────
    ELSE IF @action = 'list_messages'
    BEGIN
        SELECT ISNULL(
            (SELECT messageId, conversationId, senderRole, body, created_At
                FROM posSupportMessages
                WHERE conversationId = @conversationId
                ORDER BY messageId
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── list_conversations ────────────────────────────────────
    ELSE IF @action = 'list_conversations'
    BEGIN
        SELECT ISNULL(
            (SELECT conversationId, companyId, userId, topic, status,
                lastMessageAt, created_At
                FROM posSupportConversations
                WHERE companyId = @companyId AND userId = @userId
                ORDER BY lastMessageAt DESC
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- #############################################################################
-- [09/67] 2026-09-12_add_client_login_codes.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [09/67] 2026-09-12_add_client_login_codes.sql', 0, 1) WITH NOWAIT;
GO

-- clientLoginCodes: persisted SMS one-time-code login for POS customers
-- (dbo.clients rows with no dbo.users login at all). Mirrors the existing
-- in-memory OTP pair in modules/users.py (send_verification_code/verify_code)
-- but persisted, phone-scoped, and paired with client identity lookup +
-- attempt limiting, since that in-memory store was never designed for
-- "log a brand-new identity into a session," only "re-verify an existing one."
--
-- Code generation and the actual users/userCompanies auto-provisioning logic
-- stay in Python (modules/client_login.py) -- this proc is intentionally
-- thin CRUD, matching the sp_chartOfAccounts/sp_journalEntries split of
-- "business logic in Python, storage in a plain proc" used elsewhere.

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'clientLoginCodes')
CREATE TABLE [dbo].[clientLoginCodes] (
    clientLoginCodeId  INT IDENTITY(1,1) NOT NULL,
    phone               NVARCHAR(20)  NOT NULL,   -- E.164, matches dbo.clients.cellphone
    code                VARCHAR(6)    NOT NULL,
    expiresAt           DATETIME2(7)  NOT NULL,
    attempts            INT           NOT NULL DEFAULT (0),
    consumedAt          DATETIME2(7)  NULL,
    created_At          DATETIME2(7)  NOT NULL DEFAULT (GETUTCDATE()),
    CONSTRAINT PK_clientLoginCodes PRIMARY KEY CLUSTERED (clientLoginCodeId)
);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_clientLoginCodes_phone' AND object_id = OBJECT_ID('dbo.clientLoginCodes'))
CREATE NONCLUSTERED INDEX IX_clientLoginCodes_phone ON dbo.clientLoginCodes (phone, consumedAt);
GO

-- action 1 -- insert a freshly generated code (Python generates code + expiresAt).
-- action 2 -- verify: body { phone, code }. Looks up the latest non-consumed,
--             non-expired row for phone; compares code; increments attempts on
--             mismatch (max 5, then that row can no longer succeed); marks
--             consumedAt on match. Also resolves + returns the linked client
--             (and, if any, linked user) so Python doesn't need a second round
--             trip to know what to auto-provision.
CREATE OR ALTER PROC [dbo].[sp_clientLoginCodes] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @Outputmessage NVARCHAR(MAX) = '{
      "result": [
        { "value": "", "msg": "", "error": "" }
      ]
    }'

    DECLARE @action INT = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.clientLoginCodes')
    );
    DECLARE @phone   NVARCHAR(20) = (
        SELECT TOP 1 JSON_VALUE(value, '$.phone') FROM OPENJSON(@pjsonfile, '$.clientLoginCodes')
    );

    BEGIN TRY
        IF @action = 1
        BEGIN
            DECLARE @code      VARCHAR(6)   = (SELECT TOP 1 JSON_VALUE(value, '$.code')      FROM OPENJSON(@pjsonfile, '$.clientLoginCodes'));
            DECLARE @expiresAt DATETIME2(7) = (SELECT TOP 1 TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.expiresAt')) FROM OPENJSON(@pjsonfile, '$.clientLoginCodes'));

            INSERT INTO dbo.clientLoginCodes (phone, code, expiresAt)
            VALUES (@phone, @code, @expiresAt);

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(SCOPE_IDENTITY() AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Code stored');
            GOTO Finish;
        END

        IF @action = 2
        BEGIN
            DECLARE @inputCode VARCHAR(6) = (SELECT TOP 1 JSON_VALUE(value, '$.code') FROM OPENJSON(@pjsonfile, '$.clientLoginCodes'));

            DECLARE @codeId INT, @storedCode VARCHAR(6), @expires DATETIME2(7), @attempts INT;
            SELECT TOP 1 @codeId = clientLoginCodeId, @storedCode = code, @expires = expiresAt, @attempts = attempts
            FROM dbo.clientLoginCodes
            WHERE phone = @phone AND consumedAt IS NULL
            ORDER BY clientLoginCodeId DESC;

            IF @codeId IS NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No hay código para este número.');
                GOTO Finish;
            END

            IF @attempts >= 5
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Demasiados intentos. Solicita un código nuevo.');
                GOTO Finish;
            END

            IF GETUTCDATE() > @expires
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'El código expiró.');
                GOTO Finish;
            END

            IF @storedCode <> @inputCode
            BEGIN
                UPDATE dbo.clientLoginCodes SET attempts = attempts + 1 WHERE clientLoginCodeId = @codeId;
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Código incorrecto.');
                GOTO Finish;
            END

            UPDATE dbo.clientLoginCodes SET consumedAt = GETUTCDATE() WHERE clientLoginCodeId = @codeId;

            -- Resolve the client + any already-linked user in the same call,
            -- so Python knows in one round trip whether to auto-provision.
            -- firstLoginCompleted rides along too so verify_client_login_code
            -- doesn't need a second round trip to decide password-step vs skip.
            -- Compare by last-10-digits, NOT exact string: dbo.clients.cellphone
            -- is stored however it was originally typed (often plain 10-digit,
            -- no +52), while @phone here is always E.164-normalized (Python's
            -- _normalize_phone) -- an exact match silently fails for most real
            -- clients. Same normalization ClientSelector.tsx already uses
            -- client-side (normalizePhoneDigits + endsWith).
            DECLARE @clientJson NVARCHAR(MAX) = (
                SELECT TOP 1
                    c.clientId, c.companyId, c.first_name, c.last_name,
                    u.userId AS existingUserId,
                    ISNULL(u.firstLoginCompleted, 0) AS firstLoginCompleted,
                    -- 2026-09-28: the user's CURRENT role in this company, so
                    -- client_login.py never overwrites it with 'pos'.
                    -- hasCompanyRole is never NULL (FOR JSON PATH drops NULLs).
                    CASE WHEN uc.userId IS NOT NULL THEN 1 ELSE 0 END AS hasCompanyRole,
                    uc.roleName AS existingRoleCode,
                    r.name AS existingRoleName
                FROM dbo.clients c
                LEFT JOIN dbo.users u ON u.clientId = c.clientId
                LEFT JOIN dbo.userCompanies uc ON uc.userId = u.userId AND uc.companyId = c.companyId
                LEFT JOIN dbo.roles r ON r.code = uc.roleName
                WHERE RIGHT(REPLACE(c.cellphone, '+', ''), 10) = RIGHT(REPLACE(@phone, '+', ''), 10)
                ORDER BY CASE WHEN u.userId IS NOT NULL THEN 0 ELSE 1 END
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            IF @clientJson IS NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No encontramos un cliente con ese teléfono.');
                GOTO Finish;
            END

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Verified');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@codeId AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].client', JSON_QUERY(@clientJson));
        END

        -- action 3 -- status: body { phone }. No code/password involved --
        -- just "does this phone have an account, and has that account
        -- finished first-login password onboarding". Lets Python decide
        -- whether to send an OTP SMS at all (send_client_login_code) without
        -- ever touching dbo.clients/dbo.users directly.
        IF @action = 3
        BEGIN
            -- companyName rides along so Python can brand the OTP SMS as this
            -- client's own company (e.g. "Lavanderia") instead of the
            -- _send_sms_otp default of "SmartLoans" -- see modules/users.py.
            DECLARE @statusJson NVARCHAR(MAX) = (
                SELECT TOP 1
                    c.clientId, c.companyId, c.first_name, c.last_name,
                    co.name AS companyName,
                    u.userId AS existingUserId,
                    ISNULL(u.firstLoginCompleted, 0) AS firstLoginCompleted
                FROM dbo.clients c
                LEFT JOIN dbo.users u ON u.clientId = c.clientId
                LEFT JOIN dbo.companies co ON co.companyId = c.companyId
                WHERE RIGHT(REPLACE(c.cellphone, '+', ''), 10) = RIGHT(REPLACE(@phone, '+', ''), 10)
                ORDER BY CASE WHEN u.userId IS NOT NULL THEN 0 ELSE 1 END
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            IF @statusJson IS NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No encontramos una cuenta con ese número.');
                GOTO Finish;
            END

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Status');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].client', JSON_QUERY(@statusJson));
        END

        -- action 4 -- password login: body { phone, password }. Returning
        -- client only (firstLoginCompleted=1 from action 3/2) -- no OTP.
        -- Password compared in SQL so Python never sees/handles the stored
        -- value directly. Plaintext compare matches sp_login's existing
        -- staff password scheme (dbo.users.password varchar(50), no
        -- hashing anywhere in this backend today).
        IF @action = 4
        BEGIN
            DECLARE @inputPassword VARCHAR(50) = (
                SELECT TOP 1 JSON_VALUE(value, '$.password') FROM OPENJSON(@pjsonfile, '$.clientLoginCodes')
            );

            DECLARE @pwClientJson NVARCHAR(MAX) = (
                SELECT TOP 1
                    c.clientId, c.companyId, c.first_name, c.last_name, u.userId,
                    uc.roleName AS existingRoleCode,
                    r.name AS existingRoleName
                FROM dbo.clients c
                INNER JOIN dbo.users u ON u.clientId = c.clientId
                LEFT JOIN dbo.userCompanies uc ON uc.userId = u.userId AND uc.companyId = c.companyId
                LEFT JOIN dbo.roles r ON r.code = uc.roleName
                WHERE RIGHT(REPLACE(c.cellphone, '+', ''), 10) = RIGHT(REPLACE(@phone, '+', ''), 10)
                  AND u.password IS NOT NULL AND u.password <> ''
                  AND u.password = @inputPassword
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            IF @pwClientJson IS NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Teléfono o contraseña incorrectos.');
                GOTO Finish;
            END

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Verified');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].client', JSON_QUERY(@pwClientJson));
        END
    END TRY
    BEGIN CATCH
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH

Finish:
    SELECT @Outputmessage AS jsonResult;
END
GO

-- #############################################################################
-- [10/67] 2026-09-14_add_pos_client_type.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [10/67] 2026-09-14_add_pos_client_type.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add 'pos' as a valid dbo.clients.clientType value
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: clientType's CHECK constraint (CK_clients_clientType) only ever
-- allowed 'borrower' | 'lender' | 'both' | 'lawyer' — all four are
-- SmartLoans lending roles. There was no honest value for a plain POS
-- retail customer with no lending relationship at all; the wizard's
-- default silently labeled them 'borrower' (loan applicant), which is
-- semantically wrong even though it doesn't break anything functional
-- (reward points are NOT gated by clientType — see sql/sp_rewardBenefits.sql
-- / modules/rewardBenefits.py, neither references this column — so this
-- migration is purely a correctness fix for how the client is labeled and
-- displayed, not a prerequisite for rewards to work).
--
-- Confirmed via live query before writing this: today's real data is 122
-- 'borrower', 2 'both', 2 'lender', 0 'lawyer', 0 anything else — every
-- client in this table so far has been a lending participant.
--
-- Uses lowercase 'pos' to match the existing all-lowercase convention
-- (borrower/lender/both/lawyer), not the uppercase 'POS' first suggested.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_clients_clientType')
    ALTER TABLE dbo.clients DROP CONSTRAINT CK_clients_clientType
GO

ALTER TABLE dbo.clients
    ADD CONSTRAINT CK_clients_clientType
    CHECK ([clientType]='lawyer' OR [clientType]='both' OR [clientType]='lender' OR [clientType]='borrower' OR [clientType]='pos')
GO

-- #############################################################################
-- [11/67] 2026-09-14_add_pos_support_chat_close_conversation.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [11/67] 2026-09-14_add_pos_support_chat_close_conversation.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add a close_conversation action to sp_posSupportChat ("clear history")
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: start_conversation reuses the caller's existing 'open' thread for a
-- topic indefinitely — there was no way to end one and start fresh. Marks
-- the given conversation 'closed'; the next start_conversation for that
-- (companyId, userId, topic) will then create a genuinely new one (existing
-- logic, unchanged). Scoped by companyId + userId, same ownership check as
-- the 2026-09-14 list_messages fix — a caller can only close their own
-- conversation.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_posSupportChat]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.chat[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.chat[0].companyId')
    DECLARE @conversationId  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].conversationId')
    DECLARE @userId          INT           = JSON_VALUE(@pjsonfile, '$.chat[0].userId')
    DECLARE @topic           NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.chat[0].topic')

    IF @action = 'start_conversation'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM posSupportConversations
            WHERE companyId = @companyId AND userId = @userId
              AND topic = @topic AND status = 'open'
        )
        BEGIN
            SELECT (SELECT TOP 1 conversationId, companyId, userId, topic,
                status, lastMessageAt, created_At
                FROM posSupportConversations
                WHERE companyId = @companyId AND userId = @userId
                  AND topic = @topic AND status = 'open'
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
        ELSE
        BEGIN
            INSERT INTO posSupportConversations
                (companyId, userId, topic, lastMessageAt)
            VALUES
                (@companyId, @userId, @topic, GETUTCDATE())

            DECLARE @newConvId INT = SCOPE_IDENTITY()
            SELECT (SELECT conversationId, companyId, userId, topic,
                status, created_At
                FROM posSupportConversations WHERE conversationId = @newConvId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
    END

    ELSE IF @action = 'send_message'
    BEGIN
        DECLARE @senderRole NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')
        DECLARE @body       NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.chat[0].body')

        INSERT INTO posSupportMessages (conversationId, senderRole, body)
        VALUES (@conversationId, @senderRole, @body)

        DECLARE @newMsgId INT = SCOPE_IDENTITY()

        UPDATE posSupportConversations
        SET lastMessageAt = GETUTCDATE(), updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId

        SELECT (SELECT @newMsgId AS messageId, @conversationId AS conversationId,
            @senderRole AS senderRole, @body AS body
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    ELSE IF @action = 'list_messages'
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM posSupportConversations
            WHERE conversationId = @conversationId
              AND companyId = @companyId AND userId = @userId
        )
        BEGIN
            SELECT '[]' AS [jsonResult]
        END
        ELSE
        BEGIN
            SELECT ISNULL(
                (SELECT messageId, conversationId, senderRole, body, created_At
                    FROM posSupportMessages
                    WHERE conversationId = @conversationId
                    ORDER BY messageId
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END
    END

    ELSE IF @action = 'list_conversations'
    BEGIN
        SELECT ISNULL(
            (SELECT conversationId, companyId, userId, topic, status,
                lastMessageAt, created_At
                FROM posSupportConversations
                WHERE companyId = @companyId AND userId = @userId
                ORDER BY lastMessageAt DESC
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── close_conversation ("clear history") ─────────────────
    -- Scoped the same way as list_messages: only the owning (companyId,
    -- userId) can close it. Silently no-ops if it doesn't belong to the
    -- caller or doesn't exist — same "don't confirm/deny" posture as
    -- list_messages, rather than raising an error.
    ELSE IF @action = 'close_conversation'
    BEGIN
        UPDATE posSupportConversations
        SET status = 'closed', updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId
          AND companyId = @companyId AND userId = @userId
          AND status = 'open'

        SELECT (SELECT @conversationId AS conversationId, 'closed' AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- #############################################################################
-- [12/67] 2026-09-14_fix_pos_support_chat_list_messages_scoping.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [12/67] 2026-09-14_fix_pos_support_chat_list_messages_scoping.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Fix sp_posSupportChat: list_messages had NO tenant/ownership scoping
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB (same convention as the
-- 2026-09-11 migration this fixes).
--
-- WHY: the original sp_posSupportChat's list_messages branch filtered ONLY
-- by @conversationId:
--
--     SELECT ... FROM posSupportMessages WHERE conversationId = @conversationId
--
-- start_conversation and list_conversations both correctly scope by
-- companyId + userId; list_messages did not. conversationId is a plain
-- auto-incrementing INT IDENTITY, so any authenticated caller could read
-- any OTHER user's or company's support-chat messages by requesting
-- conversationId = 1, 2, 3... — including client names/phone numbers today,
-- and real income/expense/accounting figures once those topics see traffic.
--
-- FIX: list_messages now requires @companyId and @userId (same as
-- start_conversation/list_conversations) and verifies the conversation
-- actually belongs to that (companyId, userId) pair via
-- dbo.posSupportConversations before returning anything — mismatched
-- ownership returns an empty list, not an error (avoids confirming/denying
-- whether a given conversationId exists to a caller who shouldn't see it).
--
-- CALLER IMPACT: modules/posSupportChat.py passes the request payload
-- through unchanged, so no Python change is needed there — but the
-- FRONTEND's posSupportChatApi.ts::listMessages() must now send companyId
-- and userId alongside conversationId (see accompanying frontend change).
-- A list_messages call that omits them will now always get back [].
--
-- NOTE: this does NOT fix the deeper issue that companyId/userId are
-- entirely client-asserted with no server-side identity verification
-- anywhere on this route (no auth middleware, no Depends() check) — that
-- is a separate, codebase-wide problem, not unique to posSupportChat, and
-- is out of scope for this migration.
--
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_posSupportChat]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.chat[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.chat[0].companyId')
    DECLARE @conversationId  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].conversationId')
    DECLARE @userId          INT           = JSON_VALUE(@pjsonfile, '$.chat[0].userId')
    DECLARE @topic           NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.chat[0].topic')

    -- ── start_conversation ───────────────────────────────────
    -- Reuses this user's existing open conversation for the topic, same
    -- one-open-thread-per-pair idiom as sp_loanChat's start_conversation.
    IF @action = 'start_conversation'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM posSupportConversations
            WHERE companyId = @companyId AND userId = @userId
              AND topic = @topic AND status = 'open'
        )
        BEGIN
            SELECT (SELECT TOP 1 conversationId, companyId, userId, topic,
                status, lastMessageAt, created_At
                FROM posSupportConversations
                WHERE companyId = @companyId AND userId = @userId
                  AND topic = @topic AND status = 'open'
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
        ELSE
        BEGIN
            INSERT INTO posSupportConversations
                (companyId, userId, topic, lastMessageAt)
            VALUES
                (@companyId, @userId, @topic, GETUTCDATE())

            DECLARE @newConvId INT = SCOPE_IDENTITY()
            SELECT (SELECT conversationId, companyId, userId, topic,
                status, created_At
                FROM posSupportConversations WHERE conversationId = @newConvId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
    END

    -- ── send_message ─────────────────────────────────────────
    ELSE IF @action = 'send_message'
    BEGIN
        DECLARE @senderRole NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')
        DECLARE @body       NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.chat[0].body')

        INSERT INTO posSupportMessages (conversationId, senderRole, body)
        VALUES (@conversationId, @senderRole, @body)

        DECLARE @newMsgId INT = SCOPE_IDENTITY()

        UPDATE posSupportConversations
        SET lastMessageAt = GETUTCDATE(), updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId

        SELECT (SELECT @newMsgId AS messageId, @conversationId AS conversationId,
            @senderRole AS senderRole, @body AS body
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    -- ── list_messages ─────────────────────────────────────────
    -- FIXED: now requires @companyId/@userId and verifies ownership via
    -- posSupportConversations before returning anything. A mismatched
    -- conversationId (wrong owner, or one that doesn't exist) returns an
    -- empty list rather than an error, so this endpoint never confirms or
    -- denies the existence of a conversationId to a caller who can't see it.
    ELSE IF @action = 'list_messages'
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM posSupportConversations
            WHERE conversationId = @conversationId
              AND companyId = @companyId AND userId = @userId
        )
        BEGIN
            SELECT '[]' AS [jsonResult]
        END
        ELSE
        BEGIN
            SELECT ISNULL(
                (SELECT messageId, conversationId, senderRole, body, created_At
                    FROM posSupportMessages
                    WHERE conversationId = @conversationId
                    ORDER BY messageId
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END
    END

    -- ── list_conversations ────────────────────────────────────
    ELSE IF @action = 'list_conversations'
    BEGIN
        SELECT ISNULL(
            (SELECT conversationId, companyId, userId, topic, status,
                lastMessageAt, created_At
                FROM posSupportConversations
                WHERE companyId = @companyId AND userId = @userId
                ORDER BY lastMessageAt DESC
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO

-- #############################################################################
-- [13/67] 2026-09-18_backfill_clienttype_pos_companies.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [13/67] 2026-09-18_backfill_clienttype_pos_companies.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Backfill dbo.clients.clientType = 'pos' for existing POS customers that
-- predate the 'pos' clientType value (added by
-- 2026-09-14_add_pos_client_type.sql) and predate the CreateAccount.tsx fix
-- that stopped silently defaulting new POS-profile clients to 'borrower'.
--
-- NOT YET EXECUTED against any database — run manually against
-- smartloansbackend's live DB, same convention as every other file in this
-- migrations/ folder. Forward-only, additive in effect (only ever narrows
-- clientType away from a default that was never a real choice), safe to
-- re-run (WHERE clause only ever matches rows still at 'borrower').
--
-- WHY THIS SCOPE, NOT "every clientType='borrower' row":
-- Live counts checked via GET /all_clients before writing this (read-only,
-- no raw DB query needed):
--   (companyId=0,    clientType='borrower')  98 rows  <- EXCLUDED, see below
--   (companyId=1,    clientType='borrower')  36 rows  <- TARGET
--   (companyId=1008, clientType='borrower')   3 rows  <- EXCLUDED, see below
--   (companyId=1,    clientType='both')       2 rows  <- untouched, explicit choice
--   (companyId=0,    clientType='pos')        2 rows  <- untouched, already correct
--   (companyId=0,    clientType='lender')     1 row   <- untouched, explicit choice
--   (companyId=1008, clientType='lender')     1 row   <- untouched, explicit choice
--   (companyId=1,    clientType='pos')        1 row   <- untouched, already correct
--
-- companyId=1008 IS the SmartLoans company itself -- those 3 rows are real
-- loan participants, not POS customers. Excluded explicitly.
--
-- companyId=0 (98 rows) is deliberately EXCLUDED even though it's the
-- largest group: it is not "no company", it is ambiguous. CreateAccount.tsx
-- itself documents (see the effect near "autoSelectSmartLoans") that step
-- "Acceso" could previously finish with no company selected at all, which
-- is a real, separate, already-fixed bug that historically left real
-- SmartLoans borrowers with companyId=0/unset. Retagging that group risks
-- relabeling genuine loan customers as POS customers -- worse than leaving
-- the label imprecise. If companyId=0 needs a real fix, it needs its own
-- investigation (e.g. cross-referencing dbo.loans), not a blanket guess
-- bundled into this migration.
--
-- companyId=1 (Lavanderia, the one real POS company with clients today) +
-- clientType='borrower' is the clean signal: these clients belong to a POS
-- company (never SmartLoans), and 'borrower' was never a choice anyone
-- made for them -- it was the only value the old CHECK constraint allowed
-- before 2026-09-14, so every POS-created client landed there by default.
--
-- WHERE companyId > 0 AND companyId <> 1008 (not "= 1") so this also
-- covers Vending Agua (2) / FoodTruck (3) or any future POS company
-- automatically -- both currently have zero clients, so today this only
-- matches companyId=1, but the migration doesn't need rewriting when that
-- changes.
-- =============================================================================

-- Preview — run this first and read it before running the UPDATE below.
SELECT clientId, companyId, first_name, last_name, cellphone, clientType, updated_at
FROM dbo.clients
WHERE clientType = 'borrower'
  AND companyId > 0
  AND companyId <> 1008
ORDER BY companyId, clientId;

-- The actual backfill.
UPDATE dbo.clients
SET clientType = 'pos',
    updated_at = GETUTCDATE()
WHERE clientType = 'borrower'
  AND companyId > 0
  AND companyId <> 1008;

-- Verification — row count should match the preview's row count above.
SELECT companyId, clientType, COUNT(*) AS n
FROM dbo.clients
GROUP BY companyId, clientType
ORDER BY companyId, clientType;
GO

-- #############################################################################
-- [14/67] 2026-09-18_rename_client_role_to_pos.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [14/67] 2026-09-18_rename_client_role_to_pos.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Renames the 'client' role code to 'pos' — the roleCode a client_login.py
-- self-service session (see modules/client_login.py) gets. 'client' was
-- ambiguous: every participant in this system (borrower, lender, staff) is
-- also a "client" of some kind; this role specifically means a plain POS
-- customer, which is what dbo.clients.clientType='pos' already calls it.
-- Matches that naming instead of colliding with it.
--
-- NOT YET EXECUTED against any database — run manually, same convention as
-- every other file in this migrations/ folder. Run this BEFORE re-running
-- sql/sp_roles.sql (which has already been updated to say 'pos' instead of
-- 'client') -- sp_roles.sql's seeding joins on dbo.roles.code, so until this
-- rename runs, re-running sp_roles.sql would silently match nothing for
-- this role (in particular the 'myRewards' uiFeature grant, which is
-- correctly written in sp_roles.sql but was never live-seeded because the
-- role catalog still said 'client' when it last ran).
--
-- dbo.userCompanies.roleName is a DENORMALIZED COPY of the roleCode string
-- (set directly by @roleCode in sp_users, not a foreign key to
-- dbo.roles.code — confirmed by reading sql/migration_history/snapshot_2026-08-15/02_programmability.sql:
-- "roleName = ISNULL(@roleCode, roleName)") — so existing sessions with
-- roleName='client' need their own UPDATE, the roles-table rename alone
-- does not fix them retroactively.
--
-- Scope at time of writing: 2 live userCompanies rows (userId 32, 33 —
-- the test accounts created while verifying the /client-login flow this
-- session), 1 live dbo.roles row (roleId 4).
-- =============================================================================

-- Preview — run first.
SELECT roleId, code, name FROM dbo.roles WHERE code = 'client';
SELECT userId, companyId, roleId, roleName FROM dbo.userCompanies WHERE roleName = 'client';

-- The rename.
UPDATE dbo.roles
SET code = 'pos'
WHERE code = 'client';

UPDATE dbo.userCompanies
SET roleName = 'pos'
WHERE roleName = 'client';

-- Verification.
SELECT roleId, code, name FROM dbo.roles WHERE code IN ('client', 'pos');
SELECT userId, companyId, roleId, roleName FROM dbo.userCompanies WHERE roleName IN ('client', 'pos');

-- After this runs successfully, re-run sql/sp_roles.sql (safe/idempotent,
-- additive-only) to pick up the 'myRewards' uiFeature grant for the
-- now-renamed 'pos' role.
GO

-- #############################################################################
-- [15/67] 2026-09-23_add_income_one.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [15/67] 2026-09-23_add_income_one.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_income_one — single income row (total + applied promo discount)
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/income.py::_get_final_total_and_discount read back the
-- authoritative total/discountAmount/promotionCode (sp_income can recompute
-- total server-side for B2G1 promos) with a raw
-- "SELECT ... FROM dbo.income WHERE incomeId = %s". Backend rule: modules
-- never issue raw SQL — every read goes through an SP.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Factory convention: single @pjsonfile VARCHAR(MAX), fields pulled via
--     OPENJSON/JSON_VALUE. Caller passes
--     {"income":[{"incomeId": N, "companyId": N}]}, same root key as
--     sp_income/sp_income_all/sp_income_monthly.
--   - companyId is mandatory (multi-tenancy rule — never return
--     cross-company data).
--   - FOR JSON AUTO, ROOT('income'); no match → '[]' like sp_income_monthly.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_income_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN
    DECLARE @incomeId INT, @companyId INT;

    SELECT TOP 1
        @incomeId  = TRY_CONVERT(INT, JSON_VALUE(value, '$.incomeId')),
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId'))
    FROM OPENJSON(@pjsonfile, '$.income');

    IF EXISTS (
        SELECT 1 FROM [dbo].[income]
        WHERE incomeId = @incomeId AND companyId = @companyId
    )
    BEGIN
        SELECT
            i.incomeId,
            i.companyId,
            i.clientId,
            i.total,
            i.discountAmount,
            i.promotionCode
        FROM [dbo].[income] i
        WHERE i.incomeId = @incomeId
          AND i.companyId = @companyId
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [income]
    END
END
GO

-- #############################################################################
-- [16/67] 2026-09-23_add_loanInstallments_one.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [16/67] 2026-09-23_add_loanInstallments_one.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_loanInstallments_one — one installment row, tenant-scoped
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: two modules read dbo.loanInstallments with raw SQL because
-- sp_loanInstallments' 'list' action omits clientId/lenderId/dueDate/paidAt:
--   - modules/automatedPayments.py::pay_installment_spei (ownership check +
--     lender counterpart before moving money)
--   - modules/rewardBenefits.py::_installment_is_on_time (on-time points)
-- Backend rule: modules never issue raw SQL — when an SP's projection is
-- missing columns, extend the SP layer instead of bypassing it.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Same convention as sp_loanInstallments: @pjsonfile NVARCHAR(MAX),
--     fields via JSON_VALUE on $.installments[0], one [jsonResult] column,
--     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER.
--   - Caller passes {"installments":[{"installmentId":N,"companyId":N,
--     "loanId":N}]}. installmentId + companyId required (multi-tenancy);
--     loanId optional (automatedPayments also pins the loan).
--   - Not found -> '{}'.
--   - dueDate / paidDate returned as 'YYYY-MM-DD' (the on-time rule compares
--     dates only; paidAt's time component was never used).
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_loanInstallments_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @installmentId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.installments[0].installmentId'));
        DECLARE @companyId     INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.installments[0].companyId'));
        DECLARE @loanId        INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.installments[0].loanId'));

        IF @installmentId IS NULL OR @companyId IS NULL
        BEGIN
            SELECT '{"error":"installmentId and companyId are required"}' AS [jsonResult];
            RETURN;
        END

        SELECT ISNULL(
            (SELECT installmentId, loanId, clientId, lenderId, companyId,
                    installmentNumber,
                    CONVERT(VARCHAR(10), dueDate, 23) AS dueDate,
                    amount, principal, interest, status, attemptCount,
                    CONVERT(VARCHAR(10), paidAt, 23)  AS paidDate
               FROM dbo.loanInstallments
              WHERE installmentId = @installmentId
                AND companyId     = @companyId
                AND (@loanId IS NULL OR loanId = @loanId)
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
            '{}'
        ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

-- #############################################################################
-- [17/67] 2026-09-23_add_ml_oauth_states_sp.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [17/67] 2026-09-23_add_ml_oauth_states_sp.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_mlOAuthStates — MercadoLibre PKCE state -> code_verifier store
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/mercadolibre.py::save_oauth_state / pop_code_verifier wrote
-- and read dbo.mlOauthStates with raw INSERT/SELECT/UPDATE. Backend rule:
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
--   - No companyId: dbo.mlOauthStates is platform-level integration state
--     (one MercadoLibre app), not tenant data — same as today's raw SQL.
--   - FIX 2026-09-30: the live table is dbo.mlOauthStates (renamed from
--     ml_oauth_states; verified against the live schema), not dbo.ml_oauth_states.
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

            INSERT INTO dbo.mlOauthStates (state, code_verifier)
            VALUES (@state, @codeVerifier);

            SELECT (SELECT @state AS state FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult];
        END

        ELSE IF @action = 'pop'
        BEGIN
            -- Atomic claim: only the first caller for an unused state gets a row.
            DECLARE @popped TABLE (code_verifier NVARCHAR(400));

            UPDATE dbo.mlOauthStates
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

-- #############################################################################
-- [18/67] 2026-09-23_add_ml_tokens_sp.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [18/67] 2026-09-23_add_ml_tokens_sp.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_mlTokens — MercadoLibre OAuth token store (upsert / latest)
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/mercadolibre.py::upsert_tokens / get_latest_tokens wrote and
-- read dbo.mlTokens with 5 raw statements (SELECT/UPDATE/INSERT/SELECT and
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
--   - FIX 2026-09-30: the live table is dbo.mlTokens (renamed from
--     ml_tokens; verified against the live schema), not dbo.ml_tokens.
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
            FROM dbo.mlTokens WITH (UPDLOCK, HOLDLOCK)
            ORDER BY id DESC;

            IF @id IS NOT NULL
            BEGIN
                UPDATE dbo.mlTokens
                   SET access_token  = @accessToken,
                       refresh_token = @refreshToken,
                       expires_at    = @expiresAt,
                       updated_at    = SYSUTCDATETIME()
                 WHERE id = @id;
                SET @op = 'updated';
            END
            ELSE
            BEGIN
                INSERT INTO dbo.mlTokens (access_token, refresh_token, expires_at)
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
                   FROM dbo.mlTokens
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

-- #############################################################################
-- [19/67] 2026-09-23_add_notificationDispatchPolicy_one.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [19/67] 2026-09-23_add_notificationDispatchPolicy_one.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_notificationDispatchPolicy_one — channel policy for one eventName
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/notificationDispatch.py::_get_policy read
-- dbo.notificationDispatch_policy with a raw
-- "SELECT channel_list_json, allow_sms_fallback ... WHERE eventName = %s".
-- Backend rule: modules never issue raw SQL — every read goes through an SP.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Same shape as sp_notificationDispatches_one: @pjsonfile VARCHAR(MAX),
--     FOR JSON AUTO, ROOT(...). Caller passes
--     {"notificationDispatchPolicies":[{"eventName":"income_created"}]}.
--   - channel_list_json is returned as the stored string; the module parses
--     it (unchanged behavior: malformed JSON -> no channels).
--   - No companyId: notificationDispatch_policy is global per eventName
--     (PK = eventName), not tenant data.
-- FIX 2026-09-28: the table was recreated as dbo.notificationDispatchPolicy on
--   2026-09-18; reading the old name threw "Invalid object name" and silently
--   killed every dispatch from then on.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatchPolicy_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @eventName NVARCHAR(40);
    SET @eventName = (
        SELECT TOP 1 JSON_VALUE(value, '$.eventName')
        FROM OPENJSON(@pjsonfile, '$.notificationDispatchPolicies')
    );

    SELECT
        [eventName],
        [channel_list_json],
        CAST([allow_sms_fallback] AS BIT) AS allow_sms_fallback
    FROM dbo.notificationDispatchPolicy
    WHERE eventName = @eventName
    FOR JSON AUTO, ROOT('notificationDispatchPolicies');
END
GO

-- #############################################################################
-- [20/67] 2026-09-23_add_notificationDispatches_lookup.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [20/67] 2026-09-23_add_notificationDispatches_lookup.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_notificationDispatches_lookup — idempotency + webhook lookups
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/notificationDispatch.py read dbo.notificationDispatches with
-- two raw SELECTs:
--   - _existing_resolved_dispatch: "already sent/confirmed?" idempotency
--     check before burning a Twilio/Azure call.
--   - update_dispatch_status_connector: find the dispatch a provider
--     callback (Twilio status webhook) refers to, by providerMessageId.
-- sp_notificationDispatches_one only looks up by notificationDispatchId, so
-- neither fit. Backend rule: modules never issue raw SQL.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Same shape as sp_notificationDispatches_one: @pjsonfile VARCHAR(MAX),
--     root key notificationDispatches, ROOT('notificationDispatches').
--   - action 'resolved' (companyId, sourceType, sourceId, eventName):
--       latest dispatch in status sent|confirmed, or [] if none.
--   - action 'byProviderMessageId' (providerMessageId):
--       notificationDispatchId + companyId. No companyId input: the caller is
--       a provider webhook that only knows the provider's message id — the
--       row's own companyId is returned so the follow-up update is scoped.
--   - Dates as ISO-8601 (CONVERT 126); NULL stays null.
--   - Old raw SELECT TOP 1 had no ORDER BY; now newest-first (deterministic).
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatches_lookup] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @action            NVARCHAR(40),
        @companyId         INT,
        @sourceType        NVARCHAR(20),
        @sourceId          INT,
        @eventName         NVARCHAR(40),
        @providerMessageId NVARCHAR(100);

    SELECT TOP 1
        @action            = JSON_VALUE(value, '$.action'),
        @companyId         = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @sourceType        = JSON_VALUE(value, '$.sourceType'),
        @sourceId          = TRY_CONVERT(INT, JSON_VALUE(value, '$.sourceId')),
        @eventName         = JSON_VALUE(value, '$.eventName'),
        @providerMessageId = JSON_VALUE(value, '$.providerMessageId')
    FROM OPENJSON(@pjsonfile, '$.notificationDispatches');

    IF @action = 'resolved'
    BEGIN
        SELECT TOP 1
            notificationDispatchId,
            selectedChannel,
            status,
            providerMessageId,
            CONVERT(VARCHAR(30), sentAt, 126)      AS sentAt,
            CONVERT(VARCHAR(30), confirmedAt, 126) AS confirmedAt
        FROM dbo.notificationDispatches
        WHERE companyId  = @companyId
          AND sourceType = @sourceType
          AND sourceId   = @sourceId
          AND eventName  = @eventName
          AND status IN ('sent', 'confirmed')
        ORDER BY notificationDispatchId DESC
        FOR JSON PATH, ROOT('notificationDispatches'), INCLUDE_NULL_VALUES;
    END
    ELSE IF @action = 'byProviderMessageId'
    BEGIN
        SELECT TOP 1
            notificationDispatchId,
            companyId
        FROM dbo.notificationDispatches
        WHERE providerMessageId = @providerMessageId
        ORDER BY notificationDispatchId DESC
        FOR JSON PATH, ROOT('notificationDispatches');
    END
    ELSE
        SELECT '{"error":"unknown action"}' AS [notificationDispatches];
END
GO

-- #############################################################################
-- [21/67] 2026-09-23_add_pushNotifications_resolveUsers.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [21/67] 2026-09-23_add_pushNotifications_resolveUsers.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_pushNotifications_resolveUsers — map recipient ids -> userId
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: Azure Notification Hub tags devices as user_{userId}, but callers
-- routinely hold a CLIENT id. Three modules resolved clientId -> userId with
-- copy-pasted raw SQL ("SELECT TOP 1 userId FROM users WHERE clientId = %s"):
--   - modules/pushNotifications.py   (plus "SELECT 1 FROM users WHERE userId"
--                                     — 2 round-trips PER recipient)
--   - modules/notificationDispatch.py::_resolve_push_user_id
--   - modules/automatedPayments.py::pay_installment_spei (lender push)
-- Backend rule: modules never issue raw SQL. One set-based SP replaces all
-- of them and resolves a whole recipient list in a single call.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Same flat-payload style as sp_pushNotifications_activeUsers:
--       {"allowUserId": 1, "ids": [2167, 27]}
--     allowUserId = 1 -> an id that already IS a userId is kept as-is
--                        (pushNotifications: callers mix userIds/clientIds).
--     allowUserId = 0 -> every id is a clientId (dispatch, SPEI lender push).
--   - Returns one row per input id, in input order:
--       {"users":[{"id":2167,"userId":27,"resolvedBy":"client"}, ...]}
--     resolvedBy: "user" | "client" | null (no linked account).
--   - clientId match picks the lowest userId (the old TOP 1 had no ORDER BY,
--     so the pick was arbitrary when a client had several app accounts).
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_pushNotifications_resolveUsers
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @allowUserId BIT = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.allowUserId')), 0);

    SELECT
        TRY_CONVERT(INT, j.[value]) AS id,
        COALESCE(u.userId, c.userId) AS userId,
        CASE WHEN u.userId IS NOT NULL THEN 'user'
             WHEN c.userId IS NOT NULL THEN 'client'
        END AS resolvedBy
    FROM OPENJSON(@pjsonfile, '$.ids') j
    OUTER APPLY (
        SELECT u1.userId
        FROM dbo.users u1
        WHERE @allowUserId = 1
          AND u1.userId = TRY_CONVERT(INT, j.[value])
    ) u
    OUTER APPLY (
        SELECT TOP 1 u2.userId
        FROM dbo.users u2
        WHERE u2.clientId = TRY_CONVERT(INT, j.[value])
        ORDER BY u2.userId
    ) c
    ORDER BY TRY_CONVERT(INT, j.[key])
    FOR JSON PATH, ROOT('users'), INCLUDE_NULL_VALUES;
END;
GO

-- #############################################################################
-- [22/67] 2026-09-23_add_reservations.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [22/67] 2026-09-23_add_reservations.sql', 0, 1) WITH NOWAIT;
GO

-- Kiosk reservation booking: customers book Lavado/Secado time slots from the PWA kiosk.
-- POS polls action=5 for today's queue; action=2 confirms, action=3 cancels, action=4 completes.

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'reservations')
CREATE TABLE [dbo].[reservations] (
    reservationId     INT IDENTITY PRIMARY KEY,
    companyId         INT             NOT NULL,
    clientName        NVARCHAR(120)   NOT NULL,
    phone             NVARCHAR(30)    NOT NULL,
    email             NVARCHAR(200)   NULL,
    serviceType       NVARCHAR(40)    NOT NULL,
    serviceDetail     NVARCHAR(120)   NULL,
    reservationDate   DATE            NOT NULL,
    timeSlot          NVARCHAR(10)    NOT NULL,
    notes             NVARCHAR(500)   NULL,
    status            NVARCHAR(20)    NOT NULL DEFAULT 'pending',
    confirmedByUserId INT             NULL,
    confirmedAt       DATETIME2       NULL,
    created_At        DATETIME2       NOT NULL DEFAULT GETUTCDATE(),
    updated_At        DATETIME2       NULL
);
GO

-- Next: run sql/sp_reservations.sql to (re)create dbo.sp_reservations.
-- It is not dropped here: a drop without the create left /reservations
-- returning 500 "Could not find stored procedure" in production.
GO

-- #############################################################################
-- [23/67] 2026-09-23_add_userCompanies_role.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [23/67] 2026-09-23_add_userCompanies_role.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Add dbo.sp_userCompanies_role — a user's active role in one company
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/fundingTransactions.py::_requester_role (the RBAC gate in
-- front of sp_fundingTransactions 'resolve_escalation') read
-- dbo.userCompanies with raw SQL. Backend rule: modules never issue raw SQL.
-- sp_users_one is NOT a substitute: it reads dbo.users (not the per-company
-- role sp_login uses) and returns the password hash.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Action-less read in the sp_loanInstallments convention:
--     @pjsonfile NVARCHAR(MAX), $.userCompanies[0], one [jsonResult] column.
--     Caller passes {"userCompanies":[{"userId":N,"companyId":N}]}.
--   - Returns {"roleName":"admin"} or '{}' when the user has no active
--     membership in that company (caller treats that as "no role" -> 403).
--   - active is VARCHAR(1): compared to '1' (the old raw SQL compared to the
--     int 1, forcing an implicit conversion on every row).
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_userCompanies_role]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @userId    INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.userCompanies[0].userId'));
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.userCompanies[0].companyId'));

        IF @userId IS NULL OR @companyId IS NULL
        BEGIN
            SELECT '{"error":"userId and companyId are required"}' AS [jsonResult];
            RETURN;
        END

        SELECT ISNULL(
            (SELECT TOP 1 roleName
               FROM dbo.userCompanies
              WHERE userId    = @userId
                AND companyId = @companyId
                AND active    = '1'
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            '{}'
        ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

-- #############################################################################
-- [24/67] 2026-09-23_ticket_discount_fields.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [24/67] 2026-09-23_ticket_discount_fields.sql', 0, 1) WITH NOWAIT;
GO

-- ============================================================
-- 2026-09-23: expose discount/promotionCode on tickets, and seed
-- the "2X1" welcome coupon into dbo.promotions so sp_income's
-- existing B2G1 engine actually applies it.
--
-- Root cause this fixes: sp_income already has a full B2G1 promo
-- engine (recomputes total from real incomeDetails/incomeDetailOptions,
-- persists promotionId/promotionCode/discountAmount) -- but it only
-- fires when a matching row exists in dbo.promotions for
-- (companyId, code, isActive=1, active date window). No such row for
-- code '2X1' was ever inserted (dbo.promotions has zero API surface --
-- nothing could have created one through the app), so the frontend's
-- 2x1 coupon always silently no-op'd server-side: the client-computed
-- discounted total got persisted as-is (fine), but promotionCode/
-- discountAmount stayed NULL, so no ticket/receipt could ever show
-- WHY the total was discounted.
--
-- sp_tickets_one also never selected discountAmount/promotionCode from
-- dbo.income into its returned JSON at all, even though the column has
-- existed since the income table was created -- so even a manually-
-- entered promotion row wouldn't have been visible on a fetched ticket
-- before this change.
--
-- Safe to re-run: promotions insert is guarded by existence check,
-- sp_tickets_one uses DROP+CREATE.
-- ============================================================

-- ── Seed the 2X1 welcome coupon so sp_income's B2G1 engine picks it up ──
IF NOT EXISTS (
    SELECT 1 FROM dbo.promotions WHERE companyId = 1 AND code = '2X1'
)
INSERT INTO dbo.promotions (companyId, code, name, promoType, isActive, startAtUtc, endAtUtc)
VALUES (1, '2X1', 'Cupon de bienvenida 2x1', 'B2G1', 1, NULL, NULL);
GO

-- ── sp_tickets_one: add discount + promotionCode to the totals JSON ──
IF OBJECT_ID(N'dbo.sp_tickets_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_tickets_one];
GO

CREATE   PROC [dbo].[sp_tickets_one]
  @pjsonfile NVARCHAR(MAX)
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @incomeId INT =
    TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.tickets[0].income'));

  IF @incomeId IS NULL
  BEGIN
    RAISERROR('Invalid input: $.tickets[0].income is required.', 16, 1);
    RETURN;
  END;

  ------------------------------------------------------------------
  -- Header
  ------------------------------------------------------------------
  DECLARE
    @paymentMethod   NVARCHAR(50),
    @paymentDate     DATETIME,
    @userId          INT,
    @clientId        INT,
    @companyId       INT,
    @incomeTotal     DECIMAL(10,2),
    @cashPaid        DECIMAL(10,2),
    @cashReturn      DECIMAL(10,2),
    @incomeDiscount  DECIMAL(10,2),
    @promotionCode   NVARCHAR(30);

  SELECT
    @paymentMethod   = i.paymentMethod,
    @paymentDate     = DATEADD(HOUR, -7, i.paymentDate),  -- FIX: UTC -> Hermosillo (UTC-7)
    @userId          = i.userId,
    @clientId        = i.clientId,
    @companyId       = i.companyId,
    @incomeTotal     = i.total,
    @cashPaid        = i.cashPaid,
    @cashReturn      = i.cashReturn,
    @incomeDiscount  = i.discountAmount,
    @promotionCode   = i.promotionCode
  FROM dbo.income i
  WHERE i.incomeId = @incomeId;

  IF @paymentMethod IS NULL
  BEGIN
    RAISERROR('incomeId not found.', 16, 1);
    RETURN;
  END;

  ------------------------------------------------------------------
  -- Build product lines (NEW: carry piecesJson)
  ------------------------------------------------------------------
  ;WITH P AS (
    SELECT
      id.incomeDetailId,
      id.productId,
      p.name AS productName,
      id.piecesJson,

      -- Base product price = 0 (service price defined by options)
      CAST(0 AS DECIMAL(10,2)) AS unitPrice,

      CAST(ISNULL(id.quantity, 1) AS INT) AS quantity,

      -- Options total (sum(choice price * option qty))
      CAST(ISNULL((
        SELECT SUM(CAST(c.price AS DECIMAL(10,2)) * ISNULL(ido.quantity, 1))
        FROM dbo.incomeDetailOptions ido
        JOIN dbo.productOptionChoices c
          ON c.productOptionChoiceId = ido.productOptionChoiceId
        WHERE ido.incomeDetailId = id.incomeDetailId
      ), 0) AS DECIMAL(10,2)) AS optionsTotal
    FROM dbo.incomeDetails id
    JOIN dbo.products p
      ON p.productId = id.productId
    WHERE id.incomeId = @incomeId
  )
  SELECT
    incomeDetailId,
    productId,
    productName,
    piecesJson,
    unitPrice,
    quantity,
    optionsTotal,
    CAST((unitPrice * quantity) + optionsTotal AS DECIMAL(10,2)) AS lineSubtotal
  INTO #TicketProducts
  FROM P;

  ------------------------------------------------------------------
  -- Totals
  ------------------------------------------------------------------
  DECLARE
    @subtotal DECIMAL(10,2),
    @iva      DECIMAL(10,2),
    @total    DECIMAL(10,2),
    @discount DECIMAL(10,2);

  SET @subtotal = ISNULL((SELECT SUM(lineSubtotal) FROM #TicketProducts), 0);

  -- Prefer stored income total if present
  SET @total = COALESCE(@incomeTotal, @subtotal);

  -- IVA derived from stored total - subtotal (if included)
  SET @iva = CASE
    WHEN @total >= @subtotal THEN ROUND(@total - @subtotal, 2)
    ELSE 0
  END;

  -- Prefer the persisted discountAmount (source of truth, set by sp_income's
  -- B2G1 promo engine); fall back to subtotal-total for older rows saved
  -- before that column was populated on this ticket's income row.
  SET @discount = CASE
    WHEN @incomeDiscount IS NOT NULL AND @incomeDiscount > 0 THEN @incomeDiscount
    WHEN @total < @subtotal THEN ROUND(@subtotal - @total, 2)
    ELSE 0
  END;

  ------------------------------------------------------------------
  -- Ticket meta from tickets table (optional)
  ------------------------------------------------------------------
  DECLARE
    @ticketId INT,
    @ticketNumber VARCHAR(50),
    @printed BIT,
    @printedDate DATETIME,
    @amountReceived DECIMAL(10,2),
    @change DECIMAL(10,2);

  SELECT TOP (1)
    @ticketId       = t.ticketId,
    @ticketNumber   = t.ticketNumber,
    @printed        = t.printed,
    @printedDate    = t.printedDate,
    @amountReceived = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(t.ticketData, '$.amountReceived')),
    @change         = TRY_CONVERT(DECIMAL(10,2), JSON_VALUE(t.ticketData, '$.change'))
  FROM dbo.tickets t
  WHERE TRY_CONVERT(INT, JSON_VALUE(t.ticketData, '$.incomeId')) = @incomeId
  ORDER BY t.created_At DESC;

  -- If tickets table doesn't have amountReceived/change, fallback to income cash fields
  IF @amountReceived IS NULL
    SET @amountReceived = @cashPaid;

  IF @change IS NULL
    SET @change = @cashReturn;

  IF @amountReceived IS NOT NULL AND @change IS NULL
    SET @change = @amountReceived - @total;

  ------------------------------------------------------------------
  -- Final JSON
  ------------------------------------------------------------------
  SELECT
    @incomeId      AS incomeId,
    @companyId     AS companyId,
    @paymentDate   AS paymentDate,
    @paymentMethod AS paymentMethod,

    JSON_QUERY((
      SELECT
        c.clientId,
        CONCAT(c.first_name, ' ', c.last_name) AS [name],
        c.cellphone,
        c.email
      FROM dbo.clients c
      WHERE c.clientId = @clientId
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS client,

    JSON_QUERY((
      SELECT
        u.userId,
        u.name,
        u.email
      FROM dbo.users u
      WHERE u.userId = @userId
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS [user],

    JSON_QUERY((
      SELECT
        tp.incomeDetailId,
        tp.productId,
        tp.productName AS name,
        tp.unitPrice,
        tp.lineSubtotal AS subtotal,
        tp.quantity,

        -- NEW: pieces object for Servicio Completo (or any product that sends it)
        CASE
          WHEN tp.piecesJson IS NULL THEN NULL
          ELSE JSON_QUERY(tp.piecesJson)
        END AS pieces,

        JSON_QUERY(ISNULL((
          SELECT
            o.productOptionId,
            o.name AS optionName,
            c.productOptionChoiceId,
            c.name AS choiceName,
            CAST(c.price AS DECIMAL(10,2)) AS price,
            ISNULL(ido.quantity, 1) AS quantity
          FROM dbo.incomeDetailOptions ido
          JOIN dbo.productOptions o
            ON o.productOptionId = ido.productOptionId
          JOIN dbo.productOptionChoices c
            ON c.productOptionChoiceId = ido.productOptionChoiceId
          WHERE ido.incomeDetailId = tp.incomeDetailId
          FOR JSON PATH
        ), '[]')) AS options
      FROM #TicketProducts tp
      FOR JSON PATH
    )) AS products,

    JSON_QUERY((
      SELECT
        @subtotal       AS subtotal,
        @iva            AS iva,
        @total          AS total,
        @discount       AS discount,
        @promotionCode  AS promotionCode,
        @amountReceived AS amountReceived,
        @change         AS [change]
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS totals,

    JSON_QUERY((
      SELECT
        @ticketId     AS ticketId,
        @ticketNumber AS ticketNumber,
        @printed      AS printed,
        @printedDate  AS printedDate
      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )) AS ticketMeta

  FOR JSON PATH, ROOT('tickets');

  DROP TABLE IF EXISTS #TicketProducts;
END
GO

-- #############################################################################
-- [25/67] 2026-09-24_reservation_catalogs.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [25/67] 2026-09-24_reservation_catalogs.sql', 0, 1) WITH NOWAIT;
GO

-- Reservation catalogs: the services a customer can book and the business
-- hours, per company, instead of hard-coded values inside sp_reservations.
-- Kiosk / WhatsApp list reservationServices (sp_reservationServices action 0)
-- and send the chosen reservationServiceId to sp_reservations.
--
-- Run order: this file → sql/sp_reservationServices.sql →
-- sql/sp_reservationHours.sql → sql/sp_reservations.sql

-- One row per bookable service, for any kind of business. How long a slot
-- lasts and how many bookings fit in it:
--   durationMinutes / capacity  when set, used as-is;
--   machineType (optional)      otherwise taken from dbo.machines of that
--                               type — longest cycleMinutes, count in service;
--   neither                     60 minutes, 1 booking.
IF OBJECT_ID(N'dbo.reservationServices', N'U') IS NULL
CREATE TABLE [dbo].[reservationServices] (
    reservationServiceId INT IDENTITY(1,1) NOT NULL,
    companyId            INT             NOT NULL,
    name                 NVARCHAR(60)    NOT NULL,
    description          NVARCHAR(250)   NULL,
    durationMinutes      INT             NULL,
    capacity             INT             NULL,
    machineType          NVARCHAR(30)    NULL,
    isActive             BIT             NOT NULL CONSTRAINT DF_reservationServices_isActive DEFAULT (1),
    createdAt            DATETIME2       NOT NULL CONSTRAINT DF_reservationServices_createdAt DEFAULT (GETUTCDATE()),
    updatedAt            DATETIME2       NULL,
    CONSTRAINT PK_reservationServices PRIMARY KEY CLUSTERED (reservationServiceId),
    CONSTRAINT CK_reservationServices_duration CHECK (durationMinutes IS NULL OR durationMinutes >= 5),
    CONSTRAINT CK_reservationServices_capacity CHECK (capacity IS NULL OR capacity >= 0)
);
GO

-- Opening hours per weekday, company local time (Hermosillo for now). dayOfWeek 0 = Monday …
-- 6 = Sunday. No row for a day = closed that day.
IF OBJECT_ID(N'dbo.reservationHours', N'U') IS NULL
CREATE TABLE [dbo].[reservationHours] (
    reservationHourId INT IDENTITY(1,1) NOT NULL,
    companyId         INT     NOT NULL,
    dayOfWeek         TINYINT NOT NULL,
    openTime          TIME(0) NOT NULL,
    closeTime         TIME(0) NOT NULL,
    createdAt         DATETIME2 NOT NULL CONSTRAINT DF_reservationHours_createdAt DEFAULT (GETUTCDATE()),
    updatedAt         DATETIME2 NULL,
    CONSTRAINT PK_reservationHours PRIMARY KEY CLUSTERED (reservationHourId),
    CONSTRAINT UQ_reservationHours_company_day UNIQUE (companyId, dayOfWeek),
    CONSTRAINT CK_reservationHours_day CHECK (dayOfWeek BETWEEN 0 AND 6),
    CONSTRAINT CK_reservationHours_range CHECK (closeTime > openTime)
);
GO

IF COL_LENGTH('dbo.reservations', 'reservationServiceId') IS NULL
    ALTER TABLE [dbo].[reservations] ADD reservationServiceId INT NULL;
GO

-- serviceType now stores the catalog name (up to 60 chars).
IF COL_LENGTH('dbo.reservations', 'serviceType') < 120
    ALTER TABLE [dbo].[reservations] ALTER COLUMN serviceType NVARCHAR(60) NOT NULL;
GO

-- ── Seed: Lavandería GMO (laundry, machine-backed) ─────────────────────────────────────────
-- Set @companyId before running; with NULL this block does nothing.
DECLARE @companyId INT = NULL;

IF @companyId IS NULL
    PRINT 'Seed skipped: set @companyId to the laundry''s companyId and run this block again.';
ELSE
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [dbo].[reservationServices] WHERE companyId = @companyId AND name = N'Lavado')
        INSERT INTO [dbo].[reservationServices] (companyId, name, machineType) VALUES (@companyId, N'Lavado', N'washer');
    IF NOT EXISTS (SELECT 1 FROM [dbo].[reservationServices] WHERE companyId = @companyId AND name = N'Secado')
        INSERT INTO [dbo].[reservationServices] (companyId, name, machineType) VALUES (@companyId, N'Secado', N'dryer');

    -- Mon–Fri 10–22, Sat 10–17, Sun 10–14
    INSERT INTO [dbo].[reservationHours] (companyId, dayOfWeek, openTime, closeTime)
    SELECT @companyId, d.dayOfWeek, d.openTime, d.closeTime
    FROM (VALUES (0, '10:00', '22:00'), (1, '10:00', '22:00'), (2, '10:00', '22:00'),
                 (3, '10:00', '22:00'), (4, '10:00', '22:00'), (5, '10:00', '17:00'),
                 (6, '10:00', '14:00')) d(dayOfWeek, openTime, closeTime)
    WHERE NOT EXISTS (SELECT 1 FROM [dbo].[reservationHours] h
                      WHERE h.companyId = @companyId AND h.dayOfWeek = d.dayOfWeek);

    -- Link reservations made before the catalog existed.
    UPDATE r SET r.reservationServiceId = s.reservationServiceId
    FROM [dbo].[reservations] r
    JOIN [dbo].[reservationServices] s ON s.companyId = r.companyId AND s.name = r.serviceType
    WHERE r.companyId = @companyId AND r.reservationServiceId IS NULL;
END
GO

-- #############################################################################
-- [26/67] 2026-09-28_whatsapp_channels.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [26/67] 2026-09-28_whatsapp_channels.sql', 0, 1) WITH NOWAIT;
GO

-- WhatsApp Cloud API, multi-company: one WhatsApp number per branch.
-- Meta's webhook carries value.metadata.phone_number_id; whatsappChannels
-- maps it to the company/branch that owns the number, so one Meta app and
-- one webhook URL serve every company.
-- whatsappConversations holds the bot's per-chat state (pending booking,
-- staff pause, last booking) so it survives restarts and works with more
-- than one App Service instance/worker.
--
-- Run order: this file → sql/sp_whatsappChannels.sql →
-- sql/sp_whatsappConversations.sql  (POST /whatsapp/cloud/migrate runs all three)

IF OBJECT_ID(N'dbo.whatsappChannels', N'U') IS NULL
CREATE TABLE [dbo].[whatsappChannels] (
    channelId          INT IDENTITY(1,1) NOT NULL,
    phoneNumberId      NVARCHAR(32)  NOT NULL,   -- Meta "Phone number ID"
    wabaId             NVARCHAR(32)  NULL,       -- WhatsApp Business Account ID
    displayPhoneNumber NVARCHAR(20)  NULL,       -- +52 662 468 8224
    companyId          INT           NOT NULL,
    branchId           INT           NULL,       -- dbo.companiesBranch.branchId
    -- Name of the App Service setting holding this number's token. NULL =
    -- WA_ACCESS_TOKEN (system user of our own portfolio). Only numbers
    -- connected from another Meta portfolio need their own.
    accessTokenRef     NVARCHAR(64)  NULL,
    botEnabled         BIT           NOT NULL CONSTRAINT DF_whatsappChannels_botEnabled DEFAULT (1),
    isActive           BIT           NOT NULL CONSTRAINT DF_whatsappChannels_isActive DEFAULT (1),
    createdAt          DATETIME2     NOT NULL CONSTRAINT DF_whatsappChannels_createdAt DEFAULT (GETUTCDATE()),
    updatedAt          DATETIME2     NULL,
    CONSTRAINT PK_whatsappChannels PRIMARY KEY CLUSTERED (channelId),
    CONSTRAINT UQ_whatsappChannels_phoneNumberId UNIQUE (phoneNumberId)
);
GO

IF OBJECT_ID(N'dbo.whatsappConversations', N'U') IS NULL
CREATE TABLE [dbo].[whatsappConversations] (
    conversationId   INT IDENTITY(1,1) NOT NULL,
    channelId        INT            NOT NULL,
    customerPhone    NVARCHAR(20)   NOT NULL,   -- E.164, +52XXXXXXXXXX
    pendingJson      NVARCHAR(MAX)  NULL,       -- proposed CREATE_RESERVATION fields
    pendingExpiresAt DATETIME2      NULL,
    staffPausedUntil DATETIME2      NULL,
    lastBookedJson   NVARCHAR(MAX)  NULL,
    createdAt        DATETIME2      NOT NULL CONSTRAINT DF_whatsappConversations_createdAt DEFAULT (GETUTCDATE()),
    updatedAt        DATETIME2      NULL,
    CONSTRAINT PK_whatsappConversations PRIMARY KEY CLUSTERED (conversationId),
    CONSTRAINT UQ_whatsappConversations_chat UNIQUE (channelId, customerPhone),
    CONSTRAINT FK_whatsappConversations_channel FOREIGN KEY (channelId)
        REFERENCES [dbo].[whatsappChannels] (channelId)
);
GO

-- #############################################################################
-- [27/67] 2026-09-29_income_monthly_any_month.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [27/67] 2026-09-29_income_monthly_any_month.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- dbo.sp_income_monthly — any month, not only the current one
-- =============================================================================
-- Forward-only, additive. NOT YET EXECUTED — run manually against the live DB.
--
-- WHY: /ingresos (IncomesPage) loaded GET /all_income → dbo.sp_income_all,
-- which has NO companyId filter: every company's income rows (770+) went to
-- every company's staff, and its "Total Mensual" mixed companies (it disagreed
-- with /movements: $29,090 / 139 vs $28,880 / 138 for September 2026).
-- /ingresos now reads one company + one month through this SP instead.
--
-- CHANGE: optional "year" and "month" in the payload. Omitted → the current
-- Hermosillo month, exactly as before (Dashboard and /movements unchanged):
--   {"income":[{"companyId": 1}]}                           -- current month
--   {"income":[{"companyId": 1, "year": 2026, "month": 8}]} -- August 2026
-- Month boundaries are Hermosillo local time (UTC-7, no DST) converted back
-- to UTC, same as the original version. Same output shape.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROC [dbo].[sp_income_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT, @year INT, @month INT;

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @year      = TRY_CONVERT(INT, JSON_VALUE(value, '$.year')),
        @month     = TRY_CONVERT(INT, JSON_VALUE(value, '$.month'))
    FROM OPENJSON(@pjsonfile, '$.income');

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    IF @year IS NULL OR @month IS NULL OR @month NOT BETWEEN 1 AND 12 OR @year NOT BETWEEN 2000 AND 2100
    BEGIN
        SET @year  = YEAR(@HermosilloNow);
        SET @month = MONTH(@HermosilloNow);
    END

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(@year, @month, 1) AS DATETIME));
    DECLARE @MonthEndUtc   DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);

    IF EXISTS (
        SELECT 1 FROM [dbo].[income]
        WHERE companyId = @companyId
          AND paymentDate >= @MonthStartUtc
          AND paymentDate < @MonthEndUtc
    )
    BEGIN
        SELECT
            i.incomeId,
            i.orderId,
            i.total,
            i.paymentMethod,
            i.paymentDate,
            i.userId,
            i.clientId,
            i.companyId,
            ISNULL(i.discountAmount,0) AS discountAmount
        FROM [dbo].[income] i
        WHERE i.companyId = @companyId
          AND i.paymentDate >= @MonthStartUtc
          AND i.paymentDate < @MonthEndUtc
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [income]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO

-- #############################################################################
-- [28/67] 2026-09-30_add_employees_ui_feature.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [28/67] 2026-09-30_add_employees_ui_feature.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Grant the 'employees' UI feature (Empleados catalog) via the DB-backed role catalog
-- =============================================================================
-- Forward-only, additive-only migration. EXECUTED against the live DB 2026-09-30
-- (it granted 'employee' too; revoked the same day, see the block at the end).
--
-- WHY: the frontend's hardcoded fallback (src/config/rolePermissions.ts)
-- already lists 'employees' under admin/manager, but GET /roles
-- (sp_roles, see sql/sp_roles.sql) is the actual runtime source of truth --
-- UserContext.tsx's loadRoleCatalog() overwrites the hardcoded ROLE_UI with
-- whatever this endpoint returns, on every app start. The 'employees' feature
-- was added to the frontend after sql/sp_roles.sql's original seed, so it was
-- never added to dbo.uiFeatures or granted to any role there -- admin/manager
-- see everything else but not the Empleados menu item.
--
-- WHAT:
--   1. dbo.uiFeatures: + 'employees' (moduleCode 'pos', same bucket as
--      clients/products/suppliers), only if not already present.
--   2. dbo.roleUiFeatures: grant ('admin','employees'), ('manager','employees'),
--      only for pairs not already granted. NOT the 'employee' role: the
--      module exposes every coworker's email/phone/address/emergency contacts
--      and allows edit/delete (PRD prd_employee.json: Admin + Manager).
-- Idempotent: every insert is WHERE NOT EXISTS, matching sql/sp_roles.sql's
-- own pattern -- never deletes or duplicates a row, safe to re-run.
-- =============================================================================

INSERT INTO [dbo].[uiFeatures] (featureCode, displayName, moduleCode)
SELECT 'employees', 'Employees', 'pos'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[uiFeatures] WHERE featureCode = 'employees');
GO

INSERT INTO [dbo].[roleUiFeatures] (roleId, featureId)
SELECT r.roleId, f.featureId
FROM (VALUES ('admin'), ('manager')) v(roleCode)
JOIN [dbo].[roles]      r ON r.code = v.roleCode
JOIN [dbo].[uiFeatures] f ON f.featureCode = 'employees'
WHERE NOT EXISTS (
    SELECT 1 FROM [dbo].[roleUiFeatures] ruf
    WHERE ruf.roleId = r.roleId AND ruf.featureId = f.featureId
);
GO

-- Revoke the 'employee' grant the first run of this script made (no-op otherwise).
DELETE ruf
FROM [dbo].[roleUiFeatures] ruf
JOIN [dbo].[roles]      r ON r.roleId = ruf.roleId
JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
WHERE r.code = 'employee' AND f.featureCode = 'employees';
GO

-- Verify: should show 'employees' for admin and manager only.
SELECT r.code, f.featureCode
FROM [dbo].[roleUiFeatures] ruf
JOIN [dbo].[roles] r ON r.roleId = ruf.roleId
JOIN [dbo].[uiFeatures] f ON f.featureId = ruf.featureId
WHERE f.featureCode = 'employees'
ORDER BY r.code;
GO

-- #############################################################################
-- [29/67] 2026-09-30_employees_companyId.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [29/67] 2026-09-30_employees_companyId.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Company-scope dbo.employees (PRD: posgmo-factory/tests/prd_employee.json)
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, AFTER
-- 2026-09-30_fix_statuses_table_rename.sql (the SPs below join dbo.status).
--
-- WHY: dbo.employees has no companyId, so /all_employees returned every
-- company's staff and sp_employees let any company edit/delete any employee.
-- The payroll expense picker inherited the same leak (see KNOWN LIMITATION in
-- 2026-09-03_add_expense_payroll.sql).
--
-- SCOPE:
--   - employees.companyId INT NULL + FK_employees_companyId → companies.
--     Existing rows stay NULL (demo seed rows, no reliable company) and stop
--     appearing in any company's list until someone assigns them.
--   - employees.updated_at DATETIME NULL.
--   - Global UNIQUE(email) → UNIQUE(companyId, email). The old constraint has
--     an auto-generated name (UQ__employee__...), so it is looked up by
--     column instead of by name.
--   - sp_employees: every action scoped by companyId; returns the
--     sp_suppliers shape (one row, one column [jsonResult]
--     {status,message,value}); delete refused while payroll expenses or
--     project assignments reference the employee.
--   - sp_employees_all / sp_employees_one: take @pjsonfile with companyId,
--     FOR JSON PATH with ids + display names flat (the old _all used
--     FOR JSON AUTO, which nested names as et[].d[].s[] and dropped the ids).
-- Idempotent: guarded ALTERs + CREATE OR ALTER, safe to re-run.
-- Rollback: 2026-09-30_employees_companyId_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.employees') AND name = 'companyId')
    ALTER TABLE [dbo].[employees] ADD companyId INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_employees_companyId')
    ALTER TABLE [dbo].[employees]
        ADD CONSTRAINT FK_employees_companyId FOREIGN KEY (companyId)
        REFERENCES [dbo].[companies] (companyId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.employees') AND name = 'updated_at')
    ALTER TABLE [dbo].[employees] ADD updated_at DATETIME NULL;
GO

-- Drop the single-column UNIQUE(email), whatever its generated name is.
DECLARE @uq SYSNAME, @sql NVARCHAR(400);
SELECT @uq = kc.name
FROM sys.key_constraints kc
JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE kc.parent_object_id = OBJECT_ID('dbo.employees')
  AND kc.type = 'UQ'
GROUP BY kc.name
HAVING COUNT(*) = 1 AND MAX(c.name) = 'email';

IF @uq IS NOT NULL
BEGIN
    SET @sql = N'ALTER TABLE [dbo].[employees] DROP CONSTRAINT ' + QUOTENAME(@uq);
    EXEC sp_executesql @sql;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_employees_companyId_email')
    ALTER TABLE [dbo].[employees]
        ADD CONSTRAINT UQ_employees_companyId_email UNIQUE (companyId, email);
GO

-- =============================================================================
-- sp_employees — CRUD (action 1 INSERT / 2 UPDATE / 3 DELETE)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_employees]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
      "employees": [{
        "companyId": 1008, "employeeId": 0,
        "firstName": "Ana", "lastName": "López", "email": "ana@example.com",
        "phoneNumber": "6621234567", "address": "", "position": "Cajera",
        "employmentTypeId": 1, "departmentId": 3, "statusId": 1,
        "hireDate": "2026-09-01", "endDate": null,
        "emergencyContactName": "", "emergencyContactRelationship": "",
        "emergencyContactPhone": "", "notes": "",
        "action": 1
      }]
    }'
    */

    DECLARE @Outputmessage NVARCHAR(MAX);
    DECLARE @Action INT, @companyId INT, @employeeId INT, @email NVARCHAR(100);

    DECLARE @payload TABLE (
        action INT,
        employeeId INT,
        companyId INT,
        firstName NVARCHAR(50),
        lastName NVARCHAR(50),
        email NVARCHAR(100),
        phoneNumber NVARCHAR(20),
        address NVARCHAR(255),
        employmentTypeId INT,
        position NVARCHAR(100),
        departmentId INT,
        statusId INT,
        hireDate DATE,
        endDate DATE,
        emergencyContactName NVARCHAR(100),
        emergencyContactRelationship NVARCHAR(50),
        emergencyContactPhone NVARCHAR(20),
        notes NVARCHAR(MAX)
    );

    INSERT INTO @payload
    SELECT TOP 1
        TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
        TRY_CAST(JSON_VALUE(value, '$.employeeId') AS INT),
        TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.firstName'))), ''),
        NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.lastName'))), ''),
        NULLIF(LOWER(LTRIM(RTRIM(JSON_VALUE(value, '$.email')))), ''),
        NULLIF(JSON_VALUE(value, '$.phoneNumber'), ''),
        NULLIF(JSON_VALUE(value, '$.address'), ''),
        TRY_CAST(JSON_VALUE(value, '$.employmentTypeId') AS INT),
        NULLIF(JSON_VALUE(value, '$.position'), ''),
        TRY_CAST(JSON_VALUE(value, '$.departmentId') AS INT),
        TRY_CAST(JSON_VALUE(value, '$.statusId') AS INT),
        TRY_CAST(NULLIF(JSON_VALUE(value, '$.hireDate'), '') AS DATE),
        TRY_CAST(NULLIF(JSON_VALUE(value, '$.endDate'), '') AS DATE),
        NULLIF(JSON_VALUE(value, '$.emergencyContactName'), ''),
        NULLIF(JSON_VALUE(value, '$.emergencyContactRelationship'), ''),
        NULLIF(JSON_VALUE(value, '$.emergencyContactPhone'), ''),
        NULLIF(JSON_VALUE(value, '$.notes'), '')
    FROM OPENJSON(@pjsonfile, '$.employees');

    SELECT @Action = action, @companyId = companyId, @employeeId = employeeId, @email = email
    FROM @payload;

    IF @companyId IS NULL
    BEGIN
        SET @Outputmessage = '{"status": "error", "message": "companyId is required."}';
        GOTO Finish;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Action IN (1, 2)
        BEGIN
            IF EXISTS (SELECT 1 FROM @payload
                       WHERE firstName IS NULL OR lastName IS NULL OR email IS NULL
                          OR employmentTypeId IS NULL OR departmentId IS NULL OR statusId IS NULL)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "firstName, lastName, email, employmentTypeId, departmentId and statusId are required."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            IF EXISTS (SELECT 1 FROM [dbo].[employees]
                       WHERE companyId = @companyId AND email = @email
                         AND employeeId <> ISNULL(CASE WHEN @Action = 2 THEN @employeeId END, 0))
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another employee with this email already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END
        END

        IF @Action IN (2, 3)
           AND NOT EXISTS (SELECT 1 FROM [dbo].[employees]
                           WHERE employeeId = @employeeId AND companyId = @companyId)
        BEGIN
            SET @Outputmessage = '{"status": "error", "message": "Employee not found."}';
            ROLLBACK TRANSACTION;
            GOTO Finish;
        END

        IF @Action = 1 -- INSERT
        BEGIN
            INSERT INTO [dbo].[employees] (
                companyId, firstName, lastName, email, phoneNumber, address,
                employmentTypeId, position, departmentId, statusId, hireDate, endDate,
                emergencyContactName, emergencyContactRelationship, emergencyContactPhone,
                notes, createdAt
            )
            SELECT
                companyId, firstName, lastName, email, phoneNumber, address,
                employmentTypeId, position, departmentId, statusId, hireDate, endDate,
                emergencyContactName, emergencyContactRelationship, emergencyContactPhone,
                notes, GETDATE()
            FROM @payload;

            SET @employeeId = SCOPE_IDENTITY();
            SET @Outputmessage = '{"status": "success", "message": "Employee inserted successfully."}';
        END
        ELSE IF @Action = 2 -- UPDATE
        BEGIN
            UPDATE e
            SET e.firstName = p.firstName,
                e.lastName = p.lastName,
                e.email = p.email,
                e.phoneNumber = p.phoneNumber,
                e.address = p.address,
                e.employmentTypeId = p.employmentTypeId,
                e.position = p.position,
                e.departmentId = p.departmentId,
                e.statusId = p.statusId,
                e.hireDate = p.hireDate,
                e.endDate = p.endDate,
                e.emergencyContactName = p.emergencyContactName,
                e.emergencyContactRelationship = p.emergencyContactRelationship,
                e.emergencyContactPhone = p.emergencyContactPhone,
                e.notes = p.notes,
                e.updated_at = GETDATE()
            FROM [dbo].[employees] e
            JOIN @payload p ON e.employeeId = p.employeeId AND e.companyId = p.companyId;

            SET @Outputmessage = '{"status": "success", "message": "Employee updated successfully."}';
        END
        ELSE IF @Action = 3 -- DELETE
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[expenses] WHERE employeeId = @employeeId)
               OR EXISTS (SELECT 1 FROM [dbo].[employeeProjectAssignments] WHERE employeeId = @employeeId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Employee has payroll or project history; set status Inactive instead of deleting."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            DELETE FROM [dbo].[employees]
            WHERE employeeId = @employeeId AND companyId = @companyId;

            SET @Outputmessage = '{"status": "success", "message": "Employee deleted successfully."}';
        END
        ELSE
        BEGIN
            SET @Outputmessage = '{"status": "error", "message": "Invalid action specified."}';
            ROLLBACK TRANSACTION;
            GOTO Finish;
        END

        COMMIT TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.value', CAST(@employeeId AS NVARCHAR(20)));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE();
        SET @Outputmessage = (
            SELECT 'error' AS [status], 'Internal SP Error: ' + @ErrMessage AS [message]
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
    END CATCH

Finish:
    SELECT @Outputmessage AS [jsonResult];
END;
GO

-- =============================================================================
-- sp_employees_all — one company's employees, ids + display names
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_employees_all]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- DECLARE @pjsonfile VARCHAR(MAX) = '{"employees": [{"companyId": 1008}]}'

    DECLARE @companyId INT = (
        SELECT TOP 1 TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.employees')
    );

    -- No companyId → empty list, never "every company" (sp_suppliers_all's
    -- OR @companyId IS NULL fallback is exactly the leak this fixes).
    SELECT
        e.employeeId,
        e.companyId,
        e.firstName,
        e.lastName,
        e.email,
        ISNULL(e.phoneNumber, '') AS phoneNumber,
        ISNULL(e.address, '') AS address,
        e.employmentTypeId,
        ISNULL(et.employmentType, '') AS employmentType,
        ISNULL(e.position, '') AS position,
        e.departmentId,
        ISNULL(d.departmentName, '') AS departmentName,
        e.statusId,
        ISNULL(s.status, '') AS status,
        ISNULL(CONVERT(VARCHAR(10), e.hireDate, 23), '') AS hireDate,
        ISNULL(CONVERT(VARCHAR(10), e.endDate, 23), '') AS endDate,
        ISNULL(e.emergencyContactName, '') AS emergencyContactName,
        ISNULL(e.emergencyContactRelationship, '') AS emergencyContactRelationship,
        ISNULL(e.emergencyContactPhone, '') AS emergencyContactPhone,
        ISNULL(e.notes, '') AS notes,
        CONVERT(VARCHAR(30), e.createdAt, 126) AS createdAt,
        ISNULL(CONVERT(VARCHAR(30), e.updated_at, 126), '') AS updated_at
    FROM [dbo].[employees] e
    LEFT JOIN [dbo].[employmentTypes] et ON et.employmentTypeId = e.employmentTypeId
    LEFT JOIN [dbo].[departments] d      ON d.departmentId = e.departmentId
    LEFT JOIN [dbo].[status] s           ON s.statusId = e.statusId
    WHERE e.companyId = @companyId
    ORDER BY e.firstName, e.lastName
    FOR JSON PATH, ROOT('employees');
END;
GO

-- =============================================================================
-- sp_employees_one — one employee of one company
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_employees_one]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- DECLARE @pjsonfile VARCHAR(MAX) = '{"employees": [{"companyId": 1008, "employeeId": 1}]}'

    DECLARE @companyId INT, @employeeId INT;
    SELECT TOP 1
        @companyId  = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        @employeeId = TRY_CAST(JSON_VALUE(value, '$.employeeId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.employees');

    SELECT
        e.employeeId,
        e.companyId,
        e.firstName,
        e.lastName,
        e.email,
        ISNULL(e.phoneNumber, '') AS phoneNumber,
        ISNULL(e.address, '') AS address,
        e.employmentTypeId,
        ISNULL(et.employmentType, '') AS employmentType,
        ISNULL(e.position, '') AS position,
        e.departmentId,
        ISNULL(d.departmentName, '') AS departmentName,
        e.statusId,
        ISNULL(s.status, '') AS status,
        ISNULL(CONVERT(VARCHAR(10), e.hireDate, 23), '') AS hireDate,
        ISNULL(CONVERT(VARCHAR(10), e.endDate, 23), '') AS endDate,
        ISNULL(e.emergencyContactName, '') AS emergencyContactName,
        ISNULL(e.emergencyContactRelationship, '') AS emergencyContactRelationship,
        ISNULL(e.emergencyContactPhone, '') AS emergencyContactPhone,
        ISNULL(e.notes, '') AS notes,
        CONVERT(VARCHAR(30), e.createdAt, 126) AS createdAt,
        ISNULL(CONVERT(VARCHAR(30), e.updated_at, 126), '') AS updated_at
    FROM [dbo].[employees] e
    LEFT JOIN [dbo].[employmentTypes] et ON et.employmentTypeId = e.employmentTypeId
    LEFT JOIN [dbo].[departments] d      ON d.departmentId = e.departmentId
    LEFT JOIN [dbo].[status] s           ON s.statusId = e.statusId
    WHERE e.employeeId = @employeeId AND e.companyId = @companyId
    FOR JSON PATH, ROOT('employees');
END;
GO

-- #############################################################################
-- [30/67] 2026-09-30_expense_all_return_new_columns.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [30/67] 2026-09-30_expense_all_return_new_columns.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- dbo.sp_expense_all — return expenseType, employeeId, notes, receiptUrl
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database --
-- run manually against smartloansbackend's live DB.
--
-- WHY: 2026-09-02_add_expense_type_notes_receipturl.sql and
-- 2026-09-03_add_expense_payroll.sql both added columns to dbo.expenses
-- (expenseType, notes, receiptUrl, employeeId) but explicitly left
-- sp_expense_all's SELECT list unchanged (see that file's own note: "its
-- current definition wasn't available when either migration was written").
-- The columns exist and are populated (e.g. a payroll expense row has
-- expenseType='payroll', employeeId=1002), but GET /all_expense never
-- returned them -- the frontend's Egresos list always fell back to
-- expenseType='inventory' and a blank '-- ' company name for every payroll
-- row, since employeeId was never in the payload to resolve.
--
-- WHAT: adds expenseType, employeeId, notes, receiptUrl to the existing
-- SELECT list. No table changes -- those columns already exist live.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

CREATE OR ALTER PROC [dbo].[sp_expense_all]
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM [dbo].[expenses])
    BEGIN
        SELECT
            e.expenseId,
            e.orderId,
            e.total,
            e.paymentMethod,
            e.paymentDate,
            e.userId,
            e.supplierId,
            e.companyId,
            e.expenseType,
            e.employeeId,
            e.notes,
            e.receiptUrl
        FROM [dbo].[expenses] e
        FOR JSON AUTO, ROOT('expenses');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [expenses]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO

-- #############################################################################
-- [31/67] 2026-09-30_expense_monthly.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [31/67] 2026-09-30_expense_monthly.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- dbo.sp_expense_monthly — one company, one month (+ 12-month totals)
-- =============================================================================
-- Forward-only, additive. NOT YET EXECUTED — run manually against the live DB,
-- AFTER 2026-09-30_expense_all_return_new_columns.sql (same column list;
-- expenseType/employeeId/notes/receiptUrl must exist on dbo.expenses).
--
-- WHY: /egresos and the /dashboard "Egresos" KPIs loaded GET /all_expense →
-- sp_expense_all, which has NO companyId filter: every company's expense
-- history went to every company's staff, and the dashboard's daily/monthly
-- expense KPIs summed all companies. Same leak /ingresos had (fixed by
-- sp_income_monthly, 2026-09-29_income_monthly_any_month.sql).
--
-- PAYLOAD: optional year/month; omitted or invalid → current Hermosillo month.
--   {"expenses":[{"companyId": 1}]}                           -- current month
--   {"expenses":[{"companyId": 1, "year": 2026, "month": 8}]} -- August 2026
-- Month boundaries are Hermosillo local time (UTC-7, no DST) converted to UTC,
-- same as sp_income_monthly. DATEFROMPARTS is CAST to DATETIME before the
-- DATEADD(HOUR) — see 2026-09-30_fix_income_monthly_dateadd.sql.
--
-- RETURNS one JSON document:
--   { "expenses":      [ ...rows of the month, newest first... ],
--     "monthlyTotals": [ {year, month, total, count} for the 12 months ending
--                        at the requested month, months with rows only ] }
-- An empty month returns "expenses": [] (never NULL). JSON_QUERY keeps the
-- ISNULL'd subqueries as nested JSON instead of escaped strings.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROC [dbo].[sp_expense_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT, @year INT, @month INT;

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @year      = TRY_CONVERT(INT, JSON_VALUE(value, '$.year')),
        @month     = TRY_CONVERT(INT, JSON_VALUE(value, '$.month'))
    FROM OPENJSON(@pjsonfile, '$.expenses');

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    IF @year IS NULL OR @month IS NULL OR @month NOT BETWEEN 1 AND 12 OR @year NOT BETWEEN 2000 AND 2100
    BEGIN
        SET @year  = YEAR(@HermosilloNow);
        SET @month = MONTH(@HermosilloNow);
    END

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(@year, @month, 1) AS DATETIME));
    DECLARE @MonthEndUtc   DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);
    DECLARE @TrendStartUtc DATETIME = DATEADD(MONTH, -11, @MonthStartUtc);

    SELECT
        JSON_QUERY(ISNULL((
            SELECT
                e.expenseId,
                e.orderId,
                e.total,
                e.paymentMethod,
                e.paymentDate,
                e.userId,
                e.supplierId,
                e.companyId,
                e.expenseType,
                e.employeeId,
                e.notes,
                e.receiptUrl
            FROM [dbo].[expenses] e
            WHERE e.companyId = @companyId
              AND e.paymentDate >= @MonthStartUtc
              AND e.paymentDate <  @MonthEndUtc
            ORDER BY e.paymentDate DESC
            FOR JSON PATH
        ), '[]')) AS [expenses],
        JSON_QUERY(ISNULL((
            SELECT
                YEAR(h.localDate)  AS [year],
                MONTH(h.localDate) AS [month],
                SUM(h.total)       AS [total],
                COUNT(*)           AS [count]
            FROM (
                SELECT DATEADD(HOUR, -7, e.paymentDate) AS localDate, e.total
                FROM [dbo].[expenses] e
                WHERE e.companyId = @companyId
                  AND e.paymentDate >= @TrendStartUtc
                  AND e.paymentDate <  @MonthEndUtc
            ) h
            GROUP BY YEAR(h.localDate), MONTH(h.localDate)
            ORDER BY [year], [month]
            FOR JSON PATH
        ), '[]')) AS [monthlyTotals]
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO

-- #############################################################################
-- [32/67] 2026-09-30_fix_expense_paymentdate_midnight.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [32/67] 2026-09-30_fix_expense_paymentdate_midnight.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Fix: expenses entered through the Egresos form show one day early
-- =============================================================================
-- Forward-only data fix. NOT YET EXECUTED — run manually against the live DB.
--
-- WHY: ExpenseForm sent `new Date('2026-09-29').toISOString()` — UTC midnight
-- of the picked Hermosillo day. paymentDate is read as UTC everywhere
-- (sp_expense_monthly, the frontend's toHermosilloDate), so 2026-09-29 00:00Z
-- = Sept 28 17:00 in Hermosillo (UTC-7): every form expense displayed a day
-- early, and one dated the 1st was counted in the previous month.
-- The form now sends that day's Hermosillo noon (`YYYY-MM-DDT19:00:00Z`).
--
-- WHICH ROWS: paymentDate exactly at 00:00:00.000. Only the form produced that
-- (CartPage and the backend use real timestamps); the stored DATE part IS the
-- day the user picked, so it is kept and moved to 19:00 UTC (noon Hermosillo).
-- journalEntries need no change: the accounting auto-post took the first 10
-- chars of the request ('YYYY-MM-DD'), which was already the picked day.
--
-- Idempotent: fixed rows are no longer at midnight, a re-run touches nothing.
-- =============================================================================

-- 1) Preview: rows that will change, with their new value.
SELECT expenseId, companyId, expenseType, total,
       paymentDate                                                       AS oldPaymentDate,
       DATEADD(HOUR, 19, CAST(CAST(paymentDate AS DATE) AS DATETIME))    AS newPaymentDate
FROM dbo.expenses
WHERE CAST(paymentDate AS TIME) = '00:00:00'
ORDER BY paymentDate;
GO

-- 2) Fix.
BEGIN TRANSACTION;

UPDATE dbo.expenses
SET paymentDate = DATEADD(HOUR, 19, CAST(CAST(paymentDate AS DATE) AS DATETIME))
WHERE CAST(paymentDate AS TIME) = '00:00:00';

SELECT @@ROWCOUNT AS rowsFixed;   -- should equal the preview's row count

COMMIT TRANSACTION;
GO

-- 3) Verify: 0 rows left at midnight.
SELECT COUNT(*) AS stillMidnight
FROM dbo.expenses
WHERE CAST(paymentDate AS TIME) = '00:00:00';
GO

-- #############################################################################
-- [33/67] 2026-09-30_fix_income_monthly_dateadd.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [33/67] 2026-09-30_fix_income_monthly_dateadd.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Fix sp_income_monthly: DATEADD(HOUR, ...) on a DATE value
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: POST /monthly_income (the /dashboard income load) returns 500 since
-- 2026-09-30_income_terminal_commission.sql ran:
--   "The datepart hour is not supported by date function dateadd for data
--    type date." (error 9810, verified in production 2026-09-30)
-- DATEFROMPARTS() returns DATE, and DATEADD(HOUR, 7, <date>) is illegal.
-- The line came from 2026-09-29_income_monthly_any_month.sql (never run in
-- prod on its own) and was carried into the commission migration.
--
-- FIX: CAST(DATEFROMPARTS(...) AS DATETIME) before adding the 7 hours
-- (Hermosillo UTC-7 month start -> UTC). Nothing else changes: same columns,
-- including commissionTerminalId / commissionRatePct / commissionAmount.
-- Both earlier files are patched the same way so a replay cannot bring the
-- bug back.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_income_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT, @year INT, @month INT;

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @year      = TRY_CONVERT(INT, JSON_VALUE(value, '$.year')),
        @month     = TRY_CONVERT(INT, JSON_VALUE(value, '$.month'))
    FROM OPENJSON(@pjsonfile, '$.income');

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    IF @year IS NULL OR @month IS NULL OR @month NOT BETWEEN 1 AND 12 OR @year NOT BETWEEN 2000 AND 2100
    BEGIN
        SET @year  = YEAR(@HermosilloNow);
        SET @month = MONTH(@HermosilloNow);
    END

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(@year, @month, 1) AS DATETIME));
    DECLARE @MonthEndUtc   DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);

    IF EXISTS (
        SELECT 1 FROM [dbo].[income]
        WHERE companyId = @companyId
          AND paymentDate >= @MonthStartUtc
          AND paymentDate < @MonthEndUtc
    )
    BEGIN
        SELECT
            i.incomeId,
            i.orderId,
            i.total,
            i.paymentMethod,
            i.paymentDate,
            i.userId,
            i.clientId,
            i.companyId,
            ISNULL(i.discountAmount,0) AS discountAmount,
            i.commissionTerminalId,
            i.commissionRatePct,
            ISNULL(i.commissionAmount,0) AS commissionAmount
        FROM [dbo].[income] i
        WHERE i.companyId = @companyId
          AND i.paymentDate >= @MonthStartUtc
          AND i.paymentDate < @MonthEndUtc
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [income]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO

-- #############################################################################
-- [34/67] 2026-09-30_fix_statuses_table_rename.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [34/67] 2026-09-30_fix_statuses_table_rename.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Fix: dbo.statuses was renamed to dbo.status in the live DB
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: GET /all_employees and GET /all_statuses return 500 in production:
--   "Invalid object name 'dbo.statuses'" (verified 2026-09-30). The live DB
-- has dbo.status (statusId, status, createdAt — same columns) and no
-- dbo.statuses; no migration in this repo did that rename, so these four
-- SPs were never updated. SQL Server resolves table names at run time
-- (deferred name resolution), so nothing failed until the SP was called.
--
-- SCOPE: the four SPs that referenced dbo.statuses, table name only.
--   - sp_employees_all   (INNER JOIN — every employee row needs a status)
--   - sp_statuses / sp_statuses_all / sp_statuses_one
--   Bodies are otherwise identical to sql/migration_history/snapshot_2026-08-15/02_programmability.sql;
--   sp_statuses_all/_one also drop the hardcoded 3-part
--   [montanogilberto_smartloans].[dbo] prefix.
--   JSON root keys stay 'statuses' — the frontend reads that key.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_employees_all]
AS
SET NOCOUNT ON

BEGIN
SELECT 
     e.[employeeId]
    ,e.[firstName]
    ,e.[lastName]
    ,e.[email]
    ,e.[phoneNumber]
    ,e.[address]
    ,et.[employmentType]
    ,e.[position]
    ,d.[departmentName]
    ,s.[status]
    ,e.[hireDate]
    ,e.[endDate]
    ,e.[emergencyContactName]
    ,e.[emergencyContactRelationship]
    ,e.[emergencyContactPhone]
    ,e.[notes]
    ,e.[createdAt]
  FROM 
    [dbo].[employees] e
    INNER JOIN [dbo].[employmentTypes] et ON et.[employmentTypeId] = e.[employmentTypeId]
    INNER JOIN [dbo].[departments] d ON d.[departmentId] = e.[departmentId]
    INNER JOIN [dbo].[status] s ON s.[statusId] = e.[statusId]
    FOR JSON AUTO, ROOT('employees');
END
GO

CREATE OR ALTER PROC [dbo].[sp_statuses] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "statuses": [
        {
            "statusId": 1,
            "status": "active",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
*/
    
    DECLARE @Outputmessage NVARCHAR(MAX) = '
    {
      "result": [
      {
         "value": "",
         "msg": "",
         "error": ""
       }
      ]
    }',
    @Error NVARCHAR(500) = '',
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.statuses'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the statuses
            INSERT INTO [dbo].[status] 
                ([status], [createdAt])
            SELECT
                JSON_VALUE(value, '$.status'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.statuses');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the statuses
            UPDATE s
            SET 
                s.[status] = JSON_VALUE(j.value, '$.status')
            FROM 
                [dbo].[status] s
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.statuses') j
                ON s.[statusId] = JSON_VALUE(j.value, '$.statusId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the statuses
            DELETE FROM [dbo].[status]
            WHERE [statusId] IN (SELECT JSON_VALUE(value, '$.statusId') FROM OPENJSON(@pjsonfile, '$.statuses'));

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

CREATE OR ALTER PROC [dbo].[sp_statuses_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [statusId],
        [status],
        [createdAt]
    FROM [dbo].[status]
    FOR JSON AUTO, ROOT('statuses');
END
GO

CREATE OR ALTER PROC [dbo].[sp_statuses_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "statuses": [
        {
        "statusId": "1"
        }
     ]   
    }'
    */

    DECLARE @statusId INT;

    SET @statusId = CAST((SELECT JSON_VALUE(value, '$.statusId') FROM OPENJSON(@pjsonfile, '$.statuses')) AS INT);

    SELECT 
        [statusId]
        ,[status]
        ,[createdAt]
    FROM 
        [dbo].[status]
    WHERE
        statusId = @statusId
    FOR JSON AUTO, ROOT('statuses');

END
GO

-- #############################################################################
-- [35/67] 2026-09-30_income_terminal_commission.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [35/67] 2026-09-30_income_terminal_commission.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Store the card-terminal commission on every income row
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, top to bottom.
--
-- WHY: card sales are charged a terminal commission (Mercado Pago, 4.2%,
-- dbo.commissionTerminals row 1) that was never recorded anywhere, so every
-- income figure on /dashboard overstated what actually reached the bank.
-- Storing it per sale — rate snapshot + amount — keeps history exact: a
-- future rate change applies to new sales only and never rewrites the past.
--
-- WHAT:
--   1. dbo.income: + commissionRatePct DECIMAL(6,3) NULL
--                  + commissionAmount  DECIMAL(10,2) NULL
--      NULL = no commission applies (cash / transfer). Net = total - ISNULL(commissionAmount, 0).
--   2. dbo.sp_income_applyCommission — stamps one sale ({"income":[{"incomeId":N}]})
--      ({"income":[{"incomeId":N,"commissionTerminalId":N?}]}) or backfills
--      every unstamped card sale ({"income":[{"backfill":1}]}).
--      Called by modules/income.py right after sp_income inserts a sale
--      (same best-effort hook pattern as the journal entry / reward points),
--      so sp_income itself — the sale path with the B2G1 promo engine — is
--      not touched.
--   3. Backfill: every existing card sale, at the current catalog rate (4.2%,
--      per the owner 2026-09-30: "apply it to all income paid with Tarjeta").
--   4. dbo.sp_income_monthly: also returns commissionTerminalId,
--      commissionRatePct, commissionAmount (body otherwise identical to
--      2026-09-29_income_monthly_any_month.sql).
--
-- RULES (sp_income_applyCommission):
--   - Card sale = paymentMethod IN ('tarjeta', 'terminal'). The POS cart
--     sends 'tarjeta'; 'terminal' is accepted for future/other clients.
--   - Terminal = income.commissionTerminalId if set, else the active terminal
--     the POS sent with the sale (hook passes it; sp_income drops it), else
--     the active catalog terminal whose paymentMethod = 'tarjeta' (lowest id). The chosen id is
--     written back, so every stamped row says which terminal charged it.
--   - commissionAmount = ROUND(total * rate / 100, 2) + ISNULL(fixedFeeAmount, 0).
--     income.total is the amount actually charged (sp_income already applied
--     any promo discount to it), which is what the terminal takes its cut of.
--   - Idempotent: only rows with commissionAmount IS NULL are touched, so a
--     retried hook or a re-run backfill never double-charges or re-prices.
-- Idempotent as a whole: column adds are guarded; SPs use CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── 1. Columns ────────────────────────────────────────────────────────────
IF COL_LENGTH('dbo.income', 'commissionRatePct') IS NULL
    ALTER TABLE [dbo].[income] ADD [commissionRatePct] DECIMAL(6,3) NULL;
GO
IF COL_LENGTH('dbo.income', 'commissionAmount') IS NULL
    ALTER TABLE [dbo].[income] ADD [commissionAmount] DECIMAL(10,2) NULL;
GO

-- ── 2. Stamp SP ───────────────────────────────────────────────────────────
CREATE OR ALTER PROCEDURE [dbo].[sp_income_applyCommission]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.income[0].incomeId'));
        DECLARE @backfill BIT = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.income[0].backfill')), 0);
        -- Terminal the POS says charged this sale (sp_income does not persist
        -- it, so the backend passes it through here). Ignored for backfill.
        DECLARE @requestedTerminalId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.income[0].commissionTerminalId'));

        IF @incomeId IS NULL AND @backfill = 0
        BEGIN
            SELECT '{"error":"incomeId (or backfill: 1) is required"}' AS [jsonResult];
            RETURN;
        END

        DECLARE @defaultTerminalId INT = (
            SELECT TOP 1 commissionTerminalId
            FROM dbo.commissionTerminals
            WHERE isActive = 1 AND LOWER(paymentMethod) = 'tarjeta'
            ORDER BY commissionTerminalId
        );
        IF @backfill = 0 AND @requestedTerminalId IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.commissionTerminals
                        WHERE commissionTerminalId = @requestedTerminalId AND isActive = 1)
            SET @defaultTerminalId = @requestedTerminalId;

        UPDATE i
           SET i.commissionTerminalId = t.commissionTerminalId,
               i.commissionRatePct    = t.commissionRatePct,
               i.commissionAmount     = ROUND(i.total * t.commissionRatePct / 100.0, 2)
                                        + ISNULL(t.fixedFeeAmount, 0)
          FROM dbo.income i
          JOIN dbo.commissionTerminals t
            ON t.commissionTerminalId = ISNULL(i.commissionTerminalId, @defaultTerminalId)
         WHERE LOWER(LTRIM(RTRIM(i.paymentMethod))) IN ('tarjeta', 'terminal')
           AND i.commissionAmount IS NULL
           AND i.total IS NOT NULL
           AND (@backfill = 1 OR i.incomeId = @incomeId);

        DECLARE @stamped INT = @@ROWCOUNT;

        IF @backfill = 1
            SELECT (SELECT @stamped AS stamped FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult];
        ELSE
            SELECT ISNULL(
                (SELECT incomeId, commissionTerminalId, commissionRatePct, commissionAmount
                   FROM dbo.income
                  WHERE incomeId = @incomeId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
                '{}'
            ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

-- ── 3. Backfill every existing card sale ─────────────────────────────────
EXEC [dbo].[sp_income_applyCommission] @pjsonfile = N'{"income":[{"backfill":1}]}';
GO

-- Check: card sales left unstamped (expect 0 rows; a row here means no
-- active 'tarjeta' terminal exists in dbo.commissionTerminals).
SELECT incomeId, companyId, paymentMethod, total, commissionTerminalId
  FROM dbo.income
 WHERE LOWER(LTRIM(RTRIM(paymentMethod))) IN ('tarjeta', 'terminal')
   AND commissionAmount IS NULL;
GO

-- ── 4. sp_income_monthly returns the commission ───────────────────────────
CREATE OR ALTER PROC [dbo].[sp_income_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT, @year INT, @month INT;

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @year      = TRY_CONVERT(INT, JSON_VALUE(value, '$.year')),
        @month     = TRY_CONVERT(INT, JSON_VALUE(value, '$.month'))
    FROM OPENJSON(@pjsonfile, '$.income');

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    IF @year IS NULL OR @month IS NULL OR @month NOT BETWEEN 1 AND 12 OR @year NOT BETWEEN 2000 AND 2100
    BEGIN
        SET @year  = YEAR(@HermosilloNow);
        SET @month = MONTH(@HermosilloNow);
    END

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(@year, @month, 1) AS DATETIME));
    DECLARE @MonthEndUtc   DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);

    IF EXISTS (
        SELECT 1 FROM [dbo].[income]
        WHERE companyId = @companyId
          AND paymentDate >= @MonthStartUtc
          AND paymentDate < @MonthEndUtc
    )
    BEGIN
        SELECT
            i.incomeId,
            i.orderId,
            i.total,
            i.paymentMethod,
            i.paymentDate,
            i.userId,
            i.clientId,
            i.companyId,
            ISNULL(i.discountAmount,0) AS discountAmount,
            i.commissionTerminalId,
            i.commissionRatePct,
            ISNULL(i.commissionAmount,0) AS commissionAmount
        FROM [dbo].[income] i
        WHERE i.companyId = @companyId
          AND i.paymentDate >= @MonthStartUtc
          AND i.paymentDate < @MonthEndUtc
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [income]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO

-- #############################################################################
-- [36/67] 2026-09-30_mercadopago_rate_4_2.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [36/67] 2026-09-30_mercadopago_rate_4_2.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Set the Mercado Pago terminal commission to 4.2%
-- =============================================================================
-- Forward-only data migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: dbo.commissionTerminals row 1 (provider 'mercadopago') still holds the
-- originally seeded 3.6% (verified 2026-09-30 via GET /all_commissionTerminals).
-- The negotiated rate is 4.2% (confirmed by the owner 2026-09-30). The data
-- fix for this lived at the end of sql/sp_commissionTerminals.sql, but that
-- file was never re-run in full (see 2026-09-30_redeploy_commissionTerminals_sps.sql
-- for why), so the fix never landed.
--
-- SCOPE: one catalog row. No backend code or SP computes commissions from
-- this value today (only the commissionTerminals CRUD reads it), so past
-- income rows are not recalculated.
-- Idempotent: targets the row by id + provider; re-running is a no-op
-- beyond refreshing updatedAt, and it only fires while the rate differs.
-- =============================================================================

UPDATE [dbo].[commissionTerminals]
   SET commissionRatePct = 4.200,
       updatedAt         = GETDATE()
 WHERE commissionTerminalId = 1
   AND provider            = 'mercadopago'
   AND commissionRatePct  <> 4.200;

SELECT commissionTerminalId, provider, commissionRatePct, updatedAt
  FROM [dbo].[commissionTerminals]
 WHERE commissionTerminalId = 1;
GO

-- #############################################################################
-- [37/67] 2026-09-30_redeploy_commissionTerminals_sps.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [37/67] 2026-09-30_redeploy_commissionTerminals_sps.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Redeploy sp_commissionTerminals / _all / _one against dbo.commissionTerminals
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: dbo.commission_terminals was renamed to dbo.commissionTerminals on
-- 2026-09-18. sql/sp_commissionTerminals.sql was updated for the rename but
-- never re-run, so the live SPs still read the old name and every
-- /commissionTerminals, /all_commissionTerminals, /one_commissionTerminals
-- call fails with "Invalid object name" (found 2026-09-30 via
-- sys.sql_expression_dependencies).
--
-- SCOPE: the three SP definitions only, copied verbatim from
-- sql/sp_commissionTerminals.sql. Deliberately NOT re-running that whole
-- file: its tail holds one-off data fixes (reset Mercado Pago to 4.2%,
-- backfill income.commissionTerminalId) that must not be replayed — the
-- rate reset would overwrite any change made since.
-- Idempotent: DROP-if-exists + CREATE, safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_commissionTerminals', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals;
GO

CREATE PROCEDURE [dbo].[sp_commissionTerminals]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action               INT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].action')
        DECLARE @commissionTerminalId INT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionTerminalId')
        DECLARE @provider             VARCHAR(40)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].provider')
        DECLARE @terminalName         VARCHAR(80)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].terminalName')
        DECLARE @paymentMethod        VARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].paymentMethod')
        DECLARE @country              CHAR(2)       = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].country')
        DECLARE @commissionRatePct    DECIMAL(6,3)  = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionRatePct')
        DECLARE @fixedFeeAmount       DECIMAL(10,2) = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].fixedFeeAmount')
        DECLARE @currency             CHAR(3)       = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].currency')
        DECLARE @isActive             BIT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].isActive')
        DECLARE @validTo              DATETIME      = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].validTo')

        IF @action = 1 -- CREATE
        BEGIN
            IF @provider IS NULL OR @terminalName IS NULL OR @commissionRatePct IS NULL
                RAISERROR('provider, terminalName y commissionRatePct son requeridos.', 16, 1);

            INSERT INTO [dbo].[commissionTerminals]
                (provider, terminalName, paymentMethod, country, commissionRatePct, fixedFeeAmount, currency, isActive)
            VALUES
                (@provider, @terminalName, @paymentMethod, @country, @commissionRatePct, @fixedFeeAmount, @currency, ISNULL(@isActive, 1))

            SELECT (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                           commissionRatePct, fixedFeeAmount, currency, isActive,
                           CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                           CONVERT(NVARCHAR, createdAt, 127) AS createdAt
                    FROM [dbo].[commissionTerminals]
                    WHERE commissionTerminalId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE
        BEGIN
            IF @commissionTerminalId IS NULL
                RAISERROR('commissionTerminalId es requerido.', 16, 1);

            UPDATE [dbo].[commissionTerminals]
            SET provider           = ISNULL(@provider, provider),
                terminalName       = ISNULL(@terminalName, terminalName),
                paymentMethod      = ISNULL(@paymentMethod, paymentMethod),
                country            = ISNULL(@country, country),
                commissionRatePct  = ISNULL(@commissionRatePct, commissionRatePct),
                fixedFeeAmount     = ISNULL(@fixedFeeAmount, fixedFeeAmount),
                currency           = ISNULL(@currency, currency),
                isActive           = ISNULL(@isActive, isActive),
                validTo            = ISNULL(@validTo, validTo),
                updatedAt          = GETDATE()
            WHERE commissionTerminalId = @commissionTerminalId

            SELECT (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                           commissionRatePct, fixedFeeAmount, currency, isActive
                    FROM [dbo].[commissionTerminals]
                    WHERE commissionTerminalId = @commissionTerminalId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- DEACTIVATE (nunca DELETE — puede tener income ya referenciándola)
        BEGIN
            IF @commissionTerminalId IS NULL
                RAISERROR('commissionTerminalId es requerido.', 16, 1);

            UPDATE [dbo].[commissionTerminals]
            SET isActive = 0, updatedAt = GETDATE()
            WHERE commissionTerminalId = @commissionTerminalId

            SELECT '{"message":"deactivated","commissionTerminalId":' + CAST(@commissionTerminalId AS NVARCHAR(20)) + '}' AS [jsonResult]
        END

        ELSE
            SELECT '{"error":"Invalid action"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_commissionTerminals_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals_all;
GO
CREATE PROCEDURE [dbo].[sp_commissionTerminals_all]
AS
BEGIN
    SET NOCOUNT ON;

    -- Devuelve TODAS las terminales (activas e inactivas); el frontend
    -- decide si oculta las inactivas, igual que chartOfAccounts.
    SELECT ISNULL(
        (SELECT commissionTerminalId, provider, terminalName, paymentMethod, country,
                commissionRatePct, fixedFeeAmount, currency, isActive,
                CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                CONVERT(NVARCHAR, validTo, 127)   AS validTo,
                CONVERT(NVARCHAR, createdAt, 127) AS createdAt
         FROM [dbo].[commissionTerminals]
         ORDER BY provider, terminalName
         FOR JSON PATH, ROOT('commissionTerminals')),
        '{"commissionTerminals":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_commissionTerminals_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals_one;
GO
CREATE PROCEDURE [dbo].[sp_commissionTerminals_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @commissionTerminalId INT = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionTerminalId')

    SELECT ISNULL(
        (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                commissionRatePct, fixedFeeAmount, currency, isActive,
                CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                CONVERT(NVARCHAR, createdAt, 127) AS createdAt
         FROM [dbo].[commissionTerminals]
         WHERE commissionTerminalId = @commissionTerminalId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO

-- #############################################################################
-- [38/67] 2026-09-30_redeploy_sp_suppliers_quoted_identifier.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [38/67] 2026-09-30_redeploy_sp_suppliers_quoted_identifier.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Fix: POST /suppliers returns 500 on every call (create/update/delete)
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED — run manually against the live DB.
--
-- WHY: verified 2026-09-30, even a no-op call (action=9) fails with
--   (1934) "INSERT failed because the following SET options have incorrect
--   settings: 'QUOTED_IDENTIFIER'".
-- A procedure keeps the QUOTED_IDENTIFIER/ANSI_NULLS values that were active
-- when it was CREATEd, not the caller's. sp_suppliers was created with
-- QUOTED_IDENTIFIER OFF, which SQL Server rejects for the JSON functions
-- (JSON_VALUE/OPENJSON) and for DML against tables with filtered indexes.
-- sp_suppliers_all/_one are unaffected (GET-style reads work).
--
-- WHAT: re-creates sp_suppliers with both options ON. Body is byte-for-byte
-- the one in sql/migration_history/snapshot_2026-08-15/02_programmability.sql — no logic change.
-- Check afterwards:
--   SELECT uses_quoted_identifier, uses_ansi_nulls
--   FROM sys.sql_modules WHERE object_id = OBJECT_ID('dbo.sp_suppliers');  -- 1, 1
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_suppliers]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage VARCHAR(MAX);
    DECLARE @Action INT;

    -- Temporary table to hold the parsed JSON data
    DECLARE @payload TABLE (
        action INT,
        supplierId INT,
        companyId INT,
        supplierName NVARCHAR(200),
        contactName NVARCHAR(100),
        phone NVARCHAR(20),
        email NVARCHAR(100),
        address NVARCHAR(MAX),
        active NVARCHAR(1)
    );

    -- Ajustado el path a '$.suppliers' o '$' según envíes el objeto desde FastAPI
    INSERT INTO @payload (action, supplierId, companyId, supplierName, contactName, phone, email, address, active)
    SELECT
        JSON_VALUE(value, '$.action'),
        JSON_VALUE(value, '$.supplierId'),
        JSON_VALUE(value, '$.companyId'),
        JSON_VALUE(value, '$.supplierName'),
        JSON_VALUE(value, '$.contactName'),
        JSON_VALUE(value, '$.phone'),
        JSON_VALUE(value, '$.email'),
        JSON_VALUE(value, '$.address'),
        JSON_VALUE(value, '$.active')
    FROM OPENJSON(@pjsonfile, '$.suppliers');

    -- Fallback si el JSON no viene envuelto en un nodo 'suppliers'
    IF NOT EXISTS (SELECT 1 FROM @payload)
    BEGIN
        INSERT INTO @payload (action, supplierId, companyId, supplierName, contactName, phone, email, address, active)
        SELECT
            JSON_VALUE(@pjsonfile, '$.action'),
            JSON_VALUE(@pjsonfile, '$.supplierId'),
            JSON_VALUE(@pjsonfile, '$.companyId'),
            JSON_VALUE(@pjsonfile, '$.supplierName'),
            JSON_VALUE(@pjsonfile, '$.contactName'),
            JSON_VALUE(@pjsonfile, '$.phone'),
            JSON_VALUE(@pjsonfile, '$.email'),
            JSON_VALUE(@pjsonfile, '$.address'),
            JSON_VALUE(@pjsonfile, '$.active');
    END

    SELECT @Action = action FROM @payload;

    -- GUARDRAIL: Estructura de control transaccional requerida por la arquitectura
    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Action = 1 -- INSERT
        BEGIN
            -- Validate for duplicate supplier name within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.supplierName = p.supplierName)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this name already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate email within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.email = p.email WHERE p.email IS NOT NULL AND p.email != '')
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this email already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate phone within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.phone = p.phone WHERE p.phone IS NOT NULL AND p.phone != '')
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this phone number already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            INSERT INTO [dbo].[Suppliers] (
                companyId, supplierName, contactName, phone, email, address, active, created_At
            )
            SELECT
                companyId, supplierName, contactName, phone, email, address, active, GETDATE()
            FROM @payload;

            SET @Outputmessage = '{"status": "success", "message": "Supplier inserted successfully."}';
        END
        ELSE IF @Action = 2 -- UPDATE
        BEGIN
            -- Validate if the supplier exists
            IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.supplierId = p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier not found."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate supplier name excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.supplierName = p.supplierName WHERE s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this name already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate email excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.email = p.email WHERE p.email IS NOT NULL AND p.email != '' AND s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this email already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate phone excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.phone = p.phone WHERE p.phone IS NOT NULL AND p.phone != '' AND s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this phone number already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            UPDATE s
            SET
                s.companyId = p.companyId,
                s.supplierName = p.supplierName,
                s.contactName = p.contactName,
                s.phone = p.phone,
                s.email = p.email,
                s.address = p.address,
                s.active = p.active,
                s.updated_at = GETDATE()
            FROM [dbo].[Suppliers] s
            JOIN @payload p ON s.supplierId = p.supplierId;

            SET @Outputmessage = '{"status": "success", "message": "Supplier updated successfully."}';
        END
        ELSE IF @Action = 3 -- DELETE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.supplierId = p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier not found."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            DELETE s
            FROM [dbo].[Suppliers] s
            JOIN @payload p ON s.supplierId = p.supplierId;

            SET @Outputmessage = '{"status": "success", "message": "Supplier deleted successfully."}';
        END
        ELSE
        BEGIN
            SET @Outputmessage = '{"status": "error", "message": "Invalid action specified."}';
            ROLLBACK TRANSACTION;
            GOTO Finish;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE();
        SET @Outputmessage = (
            SELECT 
                'error' AS [status], 
                'Internal SP Error: ' + @ErrMessage AS [message] 
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
    END CATCH

Finish:
    -- Retorna exactamente una fila con una columna '[jsonResult]', ideal para tu backend en FastAPI (json_result[0][0])
    SELECT @Outputmessage AS [jsonResult];
END;
GO

-- #############################################################################
-- [39/67] 2026-10-01_fix_trialBalance_aggregation.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [39/67] 2026-10-01_fix_trialBalance_aggregation.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Fix sp_journalEntries_trialBalance: per-account totals counted VOID entries
-- and entries after toDate
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 1 (§7.6).
-- Test:    sql/tests/2026-10-01_trialBalance_cutoff_test.sql (run it BEFORE this
--          script to see the bug — FAIL rows — and AFTER it to see all PASS).
--
-- WHY: the previous body filtered status/date in the ON clause of a LEFT JOIN:
--     LEFT JOIN journalEntryLines l ON l.accountId = a.accountId
--     LEFT JOIN journalEntries   e ON e.entryId = l.journalEntryId
--                                 AND e.status = 'POSTED' AND e.entryDate <= @toDate
--     ... SUM(l.debit), SUM(l.credit)
-- A VOID or post-cutoff entry only nulls `e`; its lines `l` are still summed,
-- so per-account debit/credit included them while the grand totals (computed
-- separately with a WHERE) did not. Balance General must be built on a correct
-- aggregation, so this is fixed first.
--
-- FIX: aggregate lines in a derived table that INNER JOINs only the company's
-- POSTED entries up to @toDate, then LEFT JOIN accounts to it. Same parameters,
-- same output shape (accountsJson / totalDebit / totalCredit / balanced), so
-- modules/journalEntries.py and the frontend need no change.
-- Behavior change (intended): rows that only had VOID/future activity no longer
-- appear; per-account sums now always add up to the grand totals.
--
-- Idempotent: CREATE OR ALTER. sql/sp_journalEntries.sql carries the same body
-- so a replay of the base script cannot bring the bug back.
-- Rollback:  re-run the previous body from git history of sql/sp_journalEntries.sql
--            (not recommended — it is the buggy one).
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_trialBalance]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId')
    DECLARE @toDate    DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].toDate'))

    -- Lines of this company's POSTED entries up to the cutoff — the only lines
    -- any accounting report may count.
    DECLARE @accountsJson NVARCHAR(MAX) = (
        SELECT a.accountId, a.code AS accountCode, a.name AS accountName, a.accountType,
               a.normalBalance,
               m.debitTotal,
               m.creditTotal
        FROM [dbo].[chartOfAccounts] a
        JOIN (
            SELECT l.accountId,
                   SUM(l.debit)  AS debitTotal,
                   SUM(l.credit) AS creditTotal
            FROM [dbo].[journalEntryLines] l
            JOIN [dbo].[journalEntries] e ON e.entryId = l.journalEntryId
            WHERE e.companyId = @companyId
              AND e.status = 'POSTED'
              AND (@toDate IS NULL OR e.entryDate <= @toDate)
            GROUP BY l.accountId
        ) m ON m.accountId = a.accountId
        WHERE a.companyId = @companyId
          AND a.isPostable = 1
          AND (m.debitTotal <> 0 OR m.creditTotal <> 0)
        ORDER BY a.code
        FOR JSON PATH
    );

    DECLARE @totalDebit DECIMAL(14,2), @totalCredit DECIMAL(14,2);
    SELECT @totalDebit = ISNULL(SUM(l.debit), 0), @totalCredit = ISNULL(SUM(l.credit), 0)
    FROM [dbo].[journalEntryLines] l
    JOIN [dbo].[journalEntries] e ON e.entryId = l.journalEntryId
    WHERE e.companyId = @companyId AND e.status = 'POSTED'
      AND (@toDate IS NULL OR e.entryDate <= @toDate);

    SELECT
        ISNULL(@accountsJson, '[]') AS accountsJson,
        @totalDebit AS totalDebit,
        @totalCredit AS totalCredit,
        CASE WHEN ROUND(@totalDebit, 2) = ROUND(@totalCredit, 2) THEN 1 ELSE 0 END AS balanced
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
END
GO

-- Verify the deployed body is the fixed one (expect 1).
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries_trialBalance'))
                 LIKE '%GROUP BY l.accountId%' THEN 1 ELSE 0 END AS trialBalanceFixedDeployed;
GO

-- #############################################################################
-- [40/67] 2026-10-01b_journal_accountTotals_fn.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [40/67] 2026-10-01b_journal_accountTotals_fn.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 1b — one accounting aggregation for every report:
--   dbo.fn_journalEntries_accountTotals(@companyId, @toDate)
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB, AFTER
-- 2026-10-01_fix_trialBalance_aggregation.sql (already run: fixed body live).
-- Roadmap: POSVending/docs/accounting-module.md, Step 1.
-- Test:    sql/tests/2026-10-01_trialBalance_cutoff_test.sql
--
-- WHY: the Step 1 test could not capture sp_journalEntries_trialBalance's
-- output — SQL Server rejects INSERT…EXEC of a procedure that uses FOR JSON
-- ("The FOR JSON clause is not allowed in a INSERT statement"). Moving the
-- per-account aggregation into an inline table-valued function:
--   - makes it testable from plain T-SQL (SELECT … FROM the function);
--   - gives Balance General (Step 8) and Estado de Resultados (Step 11) the
--     SAME aggregation instead of a copy — one place to get cutoff/VOID right.
-- sp_journalEntries_trialBalance becomes a thin JSON wrapper over it; its
-- parameters and output shape do not change.
--
-- RULES (the only lines any accounting report may count):
--   journalEntries.companyId = @companyId AND status = 'POSTED'
--   AND (@toDate IS NULL OR entryDate <= @toDate)
--   accounts: same company, isPostable = 1, with non-zero activity.
--   balance = debit − credit (normalBalance 'D') | credit − debit ('C').
--
-- Idempotent: function and procedure use CREATE OR ALTER (SQL 2016 SP1+,
-- already used by earlier migrations). No table or data changes.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[fn_journalEntries_accountTotals]
(
    @companyId INT,
    @toDate    DATE   -- NULL = no cutoff
)
RETURNS TABLE
AS
RETURN
(
    SELECT a.accountId,
           a.code,
           a.name,
           a.accountType,
           a.normalBalance,
           a.parentAccountId,
           m.debitTotal,
           m.creditTotal,
           CASE WHEN a.normalBalance = 'D' THEN m.debitTotal - m.creditTotal
                ELSE m.creditTotal - m.debitTotal END AS balance
    FROM [dbo].[chartOfAccounts] a
    JOIN (
        SELECT l.accountId,
               SUM(l.debit)  AS debitTotal,
               SUM(l.credit) AS creditTotal
        FROM [dbo].[journalEntryLines] l
        JOIN [dbo].[journalEntries] e ON e.entryId = l.journalEntryId
        WHERE e.companyId = @companyId
          AND e.status = 'POSTED'
          AND (@toDate IS NULL OR e.entryDate <= @toDate)
        GROUP BY l.accountId
    ) m ON m.accountId = a.accountId
    WHERE a.companyId = @companyId
      AND a.isPostable = 1
      AND (m.debitTotal <> 0 OR m.creditTotal <> 0)
);
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_trialBalance]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId')
    DECLARE @toDate    DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].toDate'))

    DECLARE @accountsJson NVARCHAR(MAX) = (
        SELECT t.accountId, t.code AS accountCode, t.name AS accountName, t.accountType,
               t.normalBalance, t.debitTotal, t.creditTotal
        FROM [dbo].[fn_journalEntries_accountTotals](@companyId, @toDate) t
        ORDER BY t.code
        FOR JSON PATH
    );

    DECLARE @totalDebit DECIMAL(14,2), @totalCredit DECIMAL(14,2);
    SELECT @totalDebit = ISNULL(SUM(l.debit), 0), @totalCredit = ISNULL(SUM(l.credit), 0)
    FROM [dbo].[journalEntryLines] l
    JOIN [dbo].[journalEntries] e ON e.entryId = l.journalEntryId
    WHERE e.companyId = @companyId AND e.status = 'POSTED'
      AND (@toDate IS NULL OR e.entryDate <= @toDate);

    SELECT
        ISNULL(@accountsJson, '[]') AS accountsJson,
        @totalDebit AS totalDebit,
        @totalCredit AS totalCredit,
        CASE WHEN ROUND(@totalDebit, 2) = ROUND(@totalCredit, 2) THEN 1 ELSE 0 END AS balanced
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
END
GO

-- Verify (expect 1, 1).
SELECT
    CASE WHEN OBJECT_ID('dbo.fn_journalEntries_accountTotals', 'IF') IS NOT NULL THEN 1 ELSE 0 END AS accountTotalsFnDeployed,
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries_trialBalance'))
              LIKE '%fn_journalEntries_accountTotals%' THEN 1 ELSE 0 END AS trialBalanceUsesFn;
GO

-- #############################################################################
-- [41/67] 2026-10-01c_chartOfAccounts_ensure_base.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [41/67] 2026-10-01c_chartOfAccounts_ensure_base.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 2 — extend the base chart of accounts for the Balance General
-- =============================================================================
-- Forward-only, additive. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 2 (§7.2).
-- Test:    sql/tests/2026-10-01c_chartOfAccounts_ensure_base_test.sql
--
-- NEW ACCOUNTS (owner decisions 2026-10-01: inventory expensed → no 1115;
-- IVA not tracked → no 1118/2118; payroll accrual undecided → no 2110 yet):
--   1101 Caja                                ASSET   D  (cash, separate from 1105 Bancos)
--   3205 Resultados de ejercicios anteriores EQUITY  C  (prior years, after closing)
--   3210 Resultado del ejercicio             EQUITY  C  (target of a future closing entry)
-- Code convention for current/non-current (no schema change):
--   11xx circulante · 12xx no circulante · 21xx corto plazo · 22xx largo plazo.
--
-- CHANGE: sp_chartOfAccounts_seed goes from "do nothing if the company has ANY
-- account" to "insert whichever BASE account code the company is missing":
--   - never updates or deletes an existing account (ids, names, isActive kept);
--   - custom accounts a company added are untouched;
--   - classes first, then leaves (parent resolved by the class code);
--   - idempotent: a second run inserts nothing.
-- Then runs it for every company (dbo.companies) and for any companyId that
-- already has a chart, so existing companies get the 3 new accounts and any
-- company created after the 2026-09-03 backfill gets its full catalog.
--
-- Output: BEFORE and AFTER per-company summaries + a validation result set
-- (expect issues = 0 rows).
-- Idempotent: CREATE OR ALTER + insert-if-missing. sql/sp_chartOfAccounts.sql
-- carries the same seed body.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── BEFORE ───────────────────────────────────────────────────────────────────
SELECT 'BEFORE' AS phase,
       COUNT(DISTINCT companyId) AS companiesWithChart,
       COUNT(*) AS accounts,
       SUM(CASE WHEN code = '1101' THEN 1 ELSE 0 END) AS has1101,
       SUM(CASE WHEN code = '3205' THEN 1 ELSE 0 END) AS has3205,
       SUM(CASE WHEN code = '3210' THEN 1 ELSE 0 END) AS has3210
FROM dbo.chartOfAccounts;

SELECT 'BEFORE: companies without any account' AS phase, COUNT(*) AS companies
FROM dbo.companies c
WHERE NOT EXISTS (SELECT 1 FROM dbo.chartOfAccounts a WHERE a.companyId = c.companyId);
GO

-- ── Seed = ensure base catalog ───────────────────────────────────────────────
CREATE OR ALTER PROCEDURE [dbo].[sp_chartOfAccounts_seed]
    @companyId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF @companyId IS NULL RETURN;

    DECLARE @base TABLE (
        code NVARCHAR(20), name NVARCHAR(150), accountType NVARCHAR(20),
        normalBalance NVARCHAR(1), parentCode NVARCHAR(20) NULL, isPostable BIT, level INT
    );
    INSERT INTO @base (code, name, accountType, normalBalance, parentCode, isPostable, level) VALUES
        ('1',    'ACTIVO',                              'ASSET',     'D', NULL, 0, 1),
        ('2',    'PASIVO',                              'LIABILITY', 'C', NULL, 0, 1),
        ('3',    'CAPITAL',                             'EQUITY',    'C', NULL, 0, 1),
        ('4',    'INGRESOS',                            'INCOME',    'C', NULL, 0, 1),
        ('5',    'GASTOS',                              'EXPENSE',   'D', NULL, 0, 1),
        ('1101', 'Caja',                                'ASSET',     'D', '1',  1, 2),
        ('1105', 'Bancos',                              'ASSET',     'D', '1',  1, 2),
        ('2105', 'Cuentas por pagar',                   'LIABILITY', 'C', '2',  1, 2),
        ('3105', 'Capital social',                      'EQUITY',    'C', '3',  1, 2),
        ('3205', 'Resultados de ejercicios anteriores', 'EQUITY',    'C', '3',  1, 2),
        ('3210', 'Resultado del ejercicio',             'EQUITY',    'C', '3',  1, 2),
        ('4105', 'Ingresos por ventas',                 'INCOME',    'C', '4',  1, 2),
        ('4110', 'Intereses ganados',                   'INCOME',    'C', '4',  1, 2),
        ('4115', 'Comisiones cobradas',                 'INCOME',    'C', '4',  1, 2),
        ('4199', 'Otros ingresos',                      'INCOME',    'C', '4',  1, 2),
        ('5105', 'Gastos de operación',                 'EXPENSE',   'D', '5',  1, 2),
        ('5110', 'Nómina',                              'EXPENSE',   'D', '5',  1, 2),
        ('5115', 'Servicios',                           'EXPENSE',   'D', '5',  1, 2),
        ('5120', 'Comisiones bancarias',                'EXPENSE',   'D', '5',  1, 2),
        ('5199', 'Otros gastos',                        'EXPENSE',   'D', '5',  1, 2);

    -- Classes (level 1) the company is missing.
    INSERT INTO [dbo].[chartOfAccounts] (companyId, code, name, accountType, normalBalance, isPostable, level)
    SELECT @companyId, b.code, b.name, b.accountType, b.normalBalance, b.isPostable, b.level
    FROM @base b
    WHERE b.parentCode IS NULL
      AND NOT EXISTS (SELECT 1 FROM [dbo].[chartOfAccounts] a
                      WHERE a.companyId = @companyId AND a.code = b.code);

    -- Leaves the company is missing, under its class.
    INSERT INTO [dbo].[chartOfAccounts] (companyId, code, name, accountType, normalBalance, parentAccountId, isPostable, level)
    SELECT @companyId, b.code, b.name, b.accountType, b.normalBalance, p.accountId, b.isPostable, b.level
    FROM @base b
    JOIN [dbo].[chartOfAccounts] p ON p.companyId = @companyId AND p.code = b.parentCode
    WHERE b.parentCode IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM [dbo].[chartOfAccounts] a
                      WHERE a.companyId = @companyId AND a.code = b.code);
END
GO

-- ── Apply to every company ───────────────────────────────────────────────────
DECLARE @cid INT;
DECLARE comp CURSOR LOCAL FAST_FORWARD FOR
    SELECT companyId FROM dbo.companies
    UNION
    SELECT DISTINCT companyId FROM dbo.chartOfAccounts WHERE companyId > 0;
OPEN comp;
FETCH NEXT FROM comp INTO @cid;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @cid;
    FETCH NEXT FROM comp INTO @cid;
END
CLOSE comp; DEALLOCATE comp;
GO

-- ── AFTER ────────────────────────────────────────────────────────────────────
SELECT 'AFTER' AS phase,
       COUNT(DISTINCT companyId) AS companiesWithChart,
       COUNT(*) AS accounts,
       SUM(CASE WHEN code = '1101' THEN 1 ELSE 0 END) AS has1101,
       SUM(CASE WHEN code = '3205' THEN 1 ELSE 0 END) AS has3205,
       SUM(CASE WHEN code = '3210' THEN 1 ELSE 0 END) AS has3210
FROM dbo.chartOfAccounts;

-- ── VALIDATION (expect 0 rows) ───────────────────────────────────────────────
;WITH base AS (
    SELECT * FROM (VALUES
        ('1','ASSET','D',0),('2','LIABILITY','C',0),('3','EQUITY','C',0),('4','INCOME','C',0),('5','EXPENSE','D',0),
        ('1101','ASSET','D',1),('1105','ASSET','D',1),('2105','LIABILITY','C',1),('3105','EQUITY','C',1),
        ('3205','EQUITY','C',1),('3210','EQUITY','C',1),('4105','INCOME','C',1),('4110','INCOME','C',1),
        ('4115','INCOME','C',1),('4199','INCOME','C',1),('5105','EXPENSE','D',1),('5110','EXPENSE','D',1),
        ('5115','EXPENSE','D',1),('5120','EXPENSE','D',1),('5199','EXPENSE','D',1)
    ) v(code, accountType, normalBalance, isPostable)
),
companiesToCheck AS (
    SELECT companyId FROM dbo.companies
    UNION SELECT DISTINCT companyId FROM dbo.chartOfAccounts WHERE companyId > 0
)
SELECT c.companyId, b.code, 'missing base account' AS issue
FROM companiesToCheck c CROSS JOIN base b
WHERE NOT EXISTS (SELECT 1 FROM dbo.chartOfAccounts a WHERE a.companyId = c.companyId AND a.code = b.code)
UNION ALL
SELECT a.companyId, a.code, 'wrong type/naturaleza/postable'
FROM dbo.chartOfAccounts a JOIN base b ON b.code = a.code
WHERE a.companyId > 0
  AND (a.accountType <> b.accountType OR a.normalBalance <> b.normalBalance OR a.isPostable <> b.isPostable)
UNION ALL
SELECT a.companyId, a.code, 'leaf parent is not its class'
FROM dbo.chartOfAccounts a
JOIN base b ON b.code = a.code AND b.isPostable = 1
LEFT JOIN dbo.chartOfAccounts p ON p.accountId = a.parentAccountId
WHERE a.companyId > 0
  AND (p.accountId IS NULL OR p.companyId <> a.companyId OR p.code <> LEFT(a.code, 1))
UNION ALL
SELECT companyId, code, 'duplicate code'
FROM dbo.chartOfAccounts
WHERE companyId > 0
GROUP BY companyId, code
HAVING COUNT(*) > 1
ORDER BY 1, 2;
GO

-- #############################################################################
-- [42/67] 2026-10-01d_journalEntries_duplicate_guard.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [42/67] 2026-10-01d_journalEntries_duplicate_guard.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 3 — sp_journalEntries: reject a second POSTED entry for the same movement
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 3 (§7.3).
-- Test:    sql/tests/2026-10-01d_journalEntries_duplicate_guard_test.sql
-- Python:  modules/journalEntries.py posting map (cash → 1101 Caja, card/transfer
--          → 1105 Bancos; expense by type) — unit test tests/test_journal_posting_map.py.
--
-- WHY: the auto-post hooks are best-effort and the Step 4/7 backfills will
-- re-run over history; without a guard the same income/expense could be booked
-- twice. The guard lives in the SP (atomic, under UPDLOCK/HOLDLOCK) rather than
-- in Python, and rather than a filtered unique index (which would make every
-- writer of journalEntries depend on its QUOTED_IDENTIFIER setting — the
-- sp_suppliers 1934 trap).
--
-- RULE: for referenceType IN ('income','expense','income_commission') with a
-- referenceId, at most one POSTED entry per companyId. VOID entries are ignored
-- (a voided movement may be re-posted). Manual/adjustment/opening_balance
-- entries are not affected.
--
-- SAFETY: the body below is sql/sp_journalEntries.sql's body + the guard. The
-- script first checks the LIVE definition still has the repo's markers; if not
-- (someone changed it outside the repo) it stops before altering anything.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── Pre-checks ───────────────────────────────────────────────────────────────
DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries'));
SELECT
    CASE WHEN @def LIKE '%Asiento no balanceado%' THEN 1 ELSE 0 END AS hasBalanceCheck,
    CASE WHEN @def LIKE '%UPDLOCK, HOLDLOCK%'     THEN 1 ELSE 0 END AS hasFolioLock,
    CASE WHEN @def LIKE '%POSTED -> VOID%'        THEN 1 ELSE 0 END AS hasVoidRule,
    CASE WHEN @def LIKE '%duplicado rechazado%'   THEN 1 ELSE 0 END AS alreadyHasGuard;

-- Existing duplicates in live data (expect 0 rows; the guard does not repair them).
SELECT companyId, referenceType, referenceId, COUNT(*) AS postedEntries
FROM dbo.journalEntries
WHERE status = 'POSTED' AND referenceId IS NOT NULL
  AND referenceType IN ('income', 'expense', 'income_commission')
GROUP BY companyId, referenceType, referenceId
HAVING COUNT(*) > 1;

IF @def IS NULL
   OR @def NOT LIKE '%Asiento no balanceado%'
   OR @def NOT LIKE '%UPDLOCK, HOLDLOCK%'
   OR @def NOT LIKE '%POSTED -> VOID%'
BEGIN
    RAISERROR('Live sp_journalEntries does not match the repo version — NOT altering. Compare OBJECT_DEFINITION with sql/sp_journalEntries.sql first.', 16, 1);
    SET NOEXEC ON;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- Sample payload (action=1 — post)
    DECLARE @pjsonfile NVARCHAR(MAX) = '
    {
      "journalEntries": [
        {
          "action": 1,
          "companyId": 1008,
          "entryDate": "2026-09-02",
          "description": "Venta #10234",
          "referenceType": "income",
          "referenceId": 10234,
          "createdByUserId": null,
          "lines": [
            { "accountId": 5,  "debit": 4500.00, "credit": 0,       "lineDescription": "Cobro en banco" },
            { "accountId": 12, "debit": 0,        "credit": 4500.00,"lineDescription": "Venta de producto" }
          ]
        }
      ]
    }';

    -- Sample payload (action=2 — void)
    DECLARE @pjsonfile NVARCHAR(MAX) = '
    {"journalEntries":[{"action":2,"entryId":123,"companyId":1008,"status":"VOID"}]}';
    */

    DECLARE @Error NVARCHAR(500) = N'';

    BEGIN TRY
        DECLARE @action    INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].action'));
        IF @action IS NULL RAISERROR('Invalid or missing action.', 16, 1);

        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId'));
        IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.companies WHERE companyId = @companyId)
            RAISERROR('companyId es requerido y debe existir.', 16, 1);

        IF @action = 1
        BEGIN
            --------------------------------------------------------------
            -- Header
            --------------------------------------------------------------
            DECLARE
                @entryDate       DATE          = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].entryDate')),
                @description     NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].description'),
                @referenceType   NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceType'),
                @referenceId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceId')),
                @createdByUserId INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].createdByUserId'));

            IF @entryDate IS NULL OR @description IS NULL
                RAISERROR('entryDate y description son requeridos.', 16, 1);

            --------------------------------------------------------------
            -- Lines
            --------------------------------------------------------------
            DECLARE @Lines TABLE (
                idx             INT IDENTITY(1,1) PRIMARY KEY,
                accountId       INT           NOT NULL,
                debit           DECIMAL(12,2) NOT NULL,
                credit          DECIMAL(12,2) NOT NULL,
                lineDescription NVARCHAR(255) NULL
            );

            INSERT INTO @Lines (accountId, debit, credit, lineDescription)
            SELECT
                TRY_CONVERT(INT, JSON_VALUE(L.value, '$.accountId')),
                ISNULL(TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(L.value, '$.debit')), 0),
                ISNULL(TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(L.value, '$.credit')), 0),
                JSON_VALUE(L.value, '$.lineDescription')
            FROM OPENJSON(JSON_QUERY(@pjsonfile, '$.journalEntries[0].lines')) L;

            IF (SELECT COUNT(*) FROM @Lines) < 2
                RAISERROR('Un asiento contable necesita al menos 2 líneas (Debe y Haber).', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE accountId IS NULL)
                RAISERROR('Todas las líneas requieren accountId.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE debit > 0 AND credit > 0)
                RAISERROR('Una línea no puede tener Debe y Haber al mismo tiempo.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE debit = 0 AND credit = 0)
                RAISERROR('Cada línea debe tener un monto en Debe o en Haber.', 16, 1);

            IF EXISTS (
                SELECT 1 FROM @Lines Ln
                LEFT JOIN [dbo].[chartOfAccounts] A
                    ON A.accountId = Ln.accountId AND A.companyId = @companyId
                       AND A.isPostable = 1 AND A.isActive = 1
                WHERE A.accountId IS NULL
            )
                RAISERROR('Una o más accountId no son cuentas postulables activas de esta empresa.', 16, 1);

            DECLARE @sumDebit  DECIMAL(12,2) = (SELECT SUM(debit)  FROM @Lines);
            DECLARE @sumCredit DECIMAL(12,2) = (SELECT SUM(credit) FROM @Lines);

            IF ROUND(@sumDebit, 2) <> ROUND(@sumCredit, 2)
            BEGIN
                -- RAISERROR's %s placeholder only accepts (n)varchar args, never a
                -- DECIMAL directly — cast first or SQL Server rejects the RAISERROR itself.
                DECLARE @sumDebitStr  NVARCHAR(30) = CONVERT(NVARCHAR(30), @sumDebit);
                DECLARE @sumCreditStr NVARCHAR(30) = CONVERT(NVARCHAR(30), @sumCredit);
                RAISERROR('Asiento no balanceado: Debe (%s) <> Haber (%s).', 16, 1, @sumDebitStr, @sumCreditStr);
            END

            BEGIN TRAN;

            -- One POSTED entry per movement (Step 3, 2026-10-01): a retried
            -- auto-post hook or a backfill must never book the same income,
            -- expense or commission twice. VOID entries don't count, so a
            -- voided movement can be re-posted. The lock keeps two concurrent
            -- posts of the same reference from both passing the check.
            IF @referenceId IS NOT NULL
               AND @referenceType IN ('income', 'expense', 'income_commission')
               AND EXISTS (SELECT 1 FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                           WHERE companyId = @companyId AND referenceType = @referenceType
                             AND referenceId = @referenceId AND status = 'POSTED')
            BEGIN
                DECLARE @refStr NVARCHAR(60) = @referenceType + N' #' + CONVERT(NVARCHAR(20), @referenceId);
                RAISERROR('Ya existe un asiento POSTED para %s (duplicado rechazado).', 16, 1, @refStr);
            END

            -- Folio consecutivo por empresa; UPDLOCK+HOLDLOCK evita folios
            -- duplicados bajo inserciones concurrentes.
            DECLARE @entryNumber INT = (
                SELECT ISNULL(MAX(entryNumber), 0) + 1
                FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @companyId
            );

            INSERT INTO [dbo].[journalEntries]
                (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                 status, totalDebit, totalCredit, createdByUserId)
            VALUES
                (@companyId, @entryNumber, @entryDate, @description, @referenceType, @referenceId,
                 'POSTED', @sumDebit, @sumCredit, @createdByUserId);

            DECLARE @entryId INT = SCOPE_IDENTITY();

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT @entryId, accountId, debit, credit, lineDescription
            FROM @Lines;

            COMMIT TRAN;

            SELECT (SELECT TOP 1 entryId, companyId, entryNumber,
                           CONVERT(NVARCHAR, entryDate, 23) AS entryDate,
                           description, referenceType, referenceId, status,
                           totalDebit, totalCredit
                    FROM [dbo].[journalEntries]
                    WHERE entryId = @entryId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- VOID (única transición permitida: POSTED -> VOID)
        BEGIN
            DECLARE @entryIdToVoid INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].entryId'));
            DECLARE @newStatus     NVARCHAR(10) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].status');

            IF @entryIdToVoid IS NULL
                RAISERROR('entryId es requerido.', 16, 1);

            IF @newStatus IS NULL OR @newStatus <> 'VOID'
                RAISERROR('Solo se permite la transición POSTED -> VOID. entryDate/description/lines son inmutables una vez posteado.', 16, 1);

            IF NOT EXISTS (
                SELECT 1 FROM [dbo].[journalEntries]
                WHERE entryId = @entryIdToVoid AND companyId = @companyId AND status = 'POSTED'
            )
                RAISERROR('El asiento no existe, no pertenece a esta empresa, o ya no está POSTED.', 16, 1);

            UPDATE [dbo].[journalEntries]
            SET status = 'VOID', updated_at = GETUTCDATE()
            WHERE entryId = @entryIdToVoid AND companyId = @companyId;

            SELECT (SELECT TOP 1 entryId, entryNumber, status,
                           CONVERT(NVARCHAR, updated_at, 127) AS updated_at
                    FROM [dbo].[journalEntries]
                    WHERE entryId = @entryIdToVoid
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE — siempre rechazado
        BEGIN
            RAISERROR('DELETE no está permitido en journalEntries. Postea un asiento de reversión en su lugar.', 16, 1);
        END

        ELSE
            RAISERROR('Invalid action. Use 1=post, 2=void.', 16, 1);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SET @Error = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- Verify (expect 1).
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries')) LIKE '%duplicado rechazado%'
            THEN 1 ELSE 0 END AS duplicateGuardDeployed;
GO

SET NOEXEC OFF;
GO

-- #############################################################################
-- [43/67] 2026-10-01e_backfill_income_commissions_sp.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [43/67] 2026-10-01e_backfill_income_commissions_sp.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 4 — journal the card-terminal commissions (backfill procedure)
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 4 (§7.1).
-- Test:    sql/tests/2026-10-01e_backfill_income_commissions_test.sql
-- Run:     sql/migration_history/migrations/2026-10-01f_run_income_commission_backfill.sql (after the test passes)
-- Live:    new card sales are journaled by modules/income.py →
--          post_income_commission_journal_entry (Dr 5120 / Cr 1105).
--
-- WHY: income.commissionAmount (4.2% card terminal, 2026-09-30 migration) is
-- stored per sale but was never journaled, so Bancos was overstated by every
-- commission and 5120 Comisiones bancarias stayed empty.
--
-- WHAT: dbo.sp_journalEntries_backfillIncomeCommissions
--   @companyId INT  = NULL          -- NULL = every company
--   @fromDate  DATE = '2026-09-01'  -- books open 2026-09-01 (owner decision Q1)
--   @dryRun    BIT  = 1             -- 1 = report only, 0 = post
-- Posts ONE entry per sale:  Dr 5120 Comisiones bancarias / Cr 1105 Bancos,
--   amount = income.commissionAmount, referenceType 'income_commission',
--   referenceId = incomeId, entryDate = the sale's own POSTED income entry date
--   (same day as the sale in the journal).
-- Only sales that ALREADY have a POSTED income entry dated >= @fromDate.
--   A sale without one is counted (skippedNoIncomeEntry) and NOT posted:
--   booking its commission alone would push Bancos below reality; those sales
--   are handled together with their income in Step 7/10 reconciliation.
-- Idempotent: skips sales that already have a POSTED 'income_commission' entry
--   (same rule as the sp_journalEntries duplicate guard), checked inside the
--   transaction under UPDLOCK/HOLDLOCK. Never updates or deletes anything.
-- Transactions: commits its own work when called alone; inside a caller's
--   transaction it uses a savepoint (so the rolled-back test can call it).
-- Returns ONE plain row (no FOR JSON, so tests can INSERT…EXEC it):
--   dryRun, candidates, posted, postedAmount, skippedNoIncomeEntry, skippedMissingAccount
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_backfillIncomeCommissions]
    @companyId INT  = NULL,
    @fromDate  DATE = '2026-09-01',
    @dryRun    BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @c TABLE (
        companyId INT, incomeId INT, amount DECIMAL(12,2), entryDate DATE,
        drAccountId INT NULL, crAccountId INT NULL
    );
    DECLARE @posted INT = 0, @postedAmount DECIMAL(14,2) = 0;
    DECLARE @tc INT = @@TRANCOUNT;

    BEGIN TRY
        IF @dryRun = 0
        BEGIN
            IF @tc = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION bfIncomeCommissions;
            -- Serialize with live posts: nobody may add entries for these
            -- companies while we decide what is missing and number the folios.
            DECLARE @lock INT = (SELECT COUNT(*) FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                                 WHERE @companyId IS NULL OR companyId = @companyId);
        END

        -- Candidates: stamped sales with a POSTED income entry on/after the
        -- opening date and no POSTED commission entry yet.
        INSERT INTO @c (companyId, incomeId, amount, entryDate, drAccountId, crAccountId)
        SELECT i.companyId, i.incomeId, i.commissionAmount, ie.entryDate,
               a5120.accountId, a1105.accountId
        FROM [dbo].[income] i
        CROSS APPLY (
            SELECT TOP 1 e.entryDate
            FROM [dbo].[journalEntries] e
            WHERE e.companyId = i.companyId AND e.referenceType = 'income'
              AND e.referenceId = i.incomeId AND e.status = 'POSTED'
            ORDER BY e.entryId
        ) ie
        LEFT JOIN [dbo].[chartOfAccounts] a5120
            ON a5120.companyId = i.companyId AND a5120.code = '5120' AND a5120.isPostable = 1 AND a5120.isActive = 1
        LEFT JOIN [dbo].[chartOfAccounts] a1105
            ON a1105.companyId = i.companyId AND a1105.code = '1105' AND a1105.isPostable = 1 AND a1105.isActive = 1
        WHERE (@companyId IS NULL OR i.companyId = @companyId)
          AND i.commissionAmount > 0
          AND ie.entryDate >= @fromDate
          AND NOT EXISTS (SELECT 1 FROM [dbo].[journalEntries] x
                          WHERE x.companyId = i.companyId AND x.referenceType = 'income_commission'
                            AND x.referenceId = i.incomeId AND x.status = 'POSTED');

        IF @dryRun = 0
        BEGIN
            DECLARE @max TABLE (companyId INT PRIMARY KEY, maxNum INT);
            INSERT INTO @max (companyId, maxNum)
            SELECT d.companyId,
                   ISNULL((SELECT MAX(entryNumber) FROM [dbo].[journalEntries] WHERE companyId = d.companyId), 0)
            FROM (SELECT DISTINCT companyId FROM @c WHERE drAccountId IS NOT NULL AND crAccountId IS NOT NULL) d;

            DECLARE @map TABLE (entryId INT, companyId INT, incomeId INT);

            INSERT INTO [dbo].[journalEntries]
                (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                 status, totalDebit, totalCredit, createdByUserId)
            OUTPUT inserted.entryId, inserted.companyId, inserted.referenceId INTO @map (entryId, companyId, incomeId)
            SELECT c.companyId,
                   m.maxNum + ROW_NUMBER() OVER (PARTITION BY c.companyId ORDER BY c.entryDate, c.incomeId),
                   c.entryDate,
                   N'Comisión terminal ingreso #' + CAST(c.incomeId AS NVARCHAR(12)) + N' (backfill)',
                   'income_commission', c.incomeId, 'POSTED', c.amount, c.amount, NULL
            FROM @c c
            JOIN @max m ON m.companyId = c.companyId
            WHERE c.drAccountId IS NOT NULL AND c.crAccountId IS NOT NULL;

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT mp.entryId, c.drAccountId, c.amount, 0, N'Comisión terminal (backfill)'
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.incomeId = mp.incomeId
            UNION ALL
            SELECT mp.entryId, c.crAccountId, 0, c.amount, N'Comisión terminal (backfill)'
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.incomeId = mp.incomeId;

            SELECT @posted = COUNT(*), @postedAmount = ISNULL(SUM(c.amount), 0)
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.incomeId = mp.incomeId;

            IF @tc = 0 COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @tc = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF @tc > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION bfIncomeCommissions;
        THROW;
    END CATCH

    SELECT
        @dryRun AS dryRun,
        (SELECT COUNT(*) FROM @c WHERE drAccountId IS NOT NULL AND crAccountId IS NOT NULL) AS candidates,
        @posted AS posted,
        @postedAmount AS postedAmount,
        (SELECT COUNT(*) FROM [dbo].[income] i
         WHERE (@companyId IS NULL OR i.companyId = @companyId)
           AND i.commissionAmount > 0
           AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= @fromDate
           AND NOT EXISTS (SELECT 1 FROM [dbo].[journalEntries] e
                           WHERE e.companyId = i.companyId AND e.referenceType = 'income'
                             AND e.referenceId = i.incomeId AND e.status = 'POSTED')) AS skippedNoIncomeEntry,
        (SELECT COUNT(*) FROM @c WHERE drAccountId IS NULL OR crAccountId IS NULL) AS skippedMissingAccount;
END
GO

-- Verify (expect 1) + a DRY RUN over every company (posts nothing).
SELECT CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillIncomeCommissions', 'P') IS NOT NULL THEN 1 ELSE 0 END AS backfillSpDeployed;
EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
GO

-- #############################################################################
-- [44/67] 2026-10-01f_run_income_commission_backfill.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [44/67] 2026-10-01f_run_income_commission_backfill.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 4 — RUN the commission backfill (real posting) + reconciliation
-- =============================================================================
-- Run ONLY after:
--   1. 2026-10-01e_backfill_income_commissions_sp.sql   (SP created, dry run shown)
--   2. tests/2026-10-01e_backfill_income_commissions_test.sql → ALL CHECKS PASS
-- Posts Dr 5120 / Cr 1105 for every stamped card sale (books from 2026-09-01)
-- that has a POSTED income entry and no commission entry yet, all companies.
-- Idempotent: running it again posts 0. Never updates or deletes anything.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── BEFORE ───────────────────────────────────────────────────────────────────
SELECT 'BEFORE' AS phase, e.companyId,
       COUNT(*) AS commissionEntries, ISNULL(SUM(e.totalDebit), 0) AS commissionAmount
FROM dbo.journalEntries e
WHERE e.referenceType = 'income_commission' AND e.status = 'POSTED'
GROUP BY e.companyId;

-- ── RUN ──────────────────────────────────────────────────────────────────────
EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 0;
GO

-- ── RECONCILIATION (per company, books from 2026-09-01) ──────────────────────
-- stampedWithIncomeEntry must equal commissionEntries, and the amounts must match.
SELECT i.companyId,
       COUNT(*)                                   AS stampedWithIncomeEntry,
       SUM(i.commissionAmount)                    AS stampedCommission,
       SUM(CASE WHEN c.entryId IS NOT NULL THEN 1 ELSE 0 END) AS commissionEntries,
       ISNULL(SUM(c.totalDebit), 0)               AS journaledCommission,
       SUM(CASE WHEN c.entryId IS NULL THEN 1 ELSE 0 END)     AS missing,
       SUM(CASE WHEN c.entryId IS NOT NULL AND c.totalDebit <> i.commissionAmount THEN 1 ELSE 0 END) AS amountMismatch
FROM dbo.income i
JOIN dbo.journalEntries ie
  ON ie.companyId = i.companyId AND ie.referenceType = 'income' AND ie.referenceId = i.incomeId
 AND ie.status = 'POSTED' AND ie.entryDate >= '2026-09-01'
LEFT JOIN dbo.journalEntries c
  ON c.companyId = i.companyId AND c.referenceType = 'income_commission' AND c.referenceId = i.incomeId
 AND c.status = 'POSTED'
WHERE i.commissionAmount > 0
GROUP BY i.companyId
ORDER BY i.companyId;

-- Duplicates (expect 0 rows).
SELECT companyId, referenceId AS incomeId, COUNT(*) AS postedCommissionEntries
FROM dbo.journalEntries
WHERE referenceType = 'income_commission' AND status = 'POSTED'
GROUP BY companyId, referenceId
HAVING COUNT(*) > 1;

-- Stamped card sales since 2026-09-01 with NO income entry (left for Step 7/10).
SELECT i.companyId, COUNT(*) AS salesWithoutIncomeEntry, SUM(i.total) AS salesTotal, SUM(i.commissionAmount) AS commission
FROM dbo.income i
WHERE i.commissionAmount > 0
  AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= '2026-09-01'
  AND NOT EXISTS (SELECT 1 FROM dbo.journalEntries e
                  WHERE e.companyId = i.companyId AND e.referenceType = 'income'
                    AND e.referenceId = i.incomeId AND e.status = 'POSTED')
GROUP BY i.companyId;

-- Re-run proof (expect candidates 0, posted 0).
EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
GO

-- #############################################################################
-- [45/67] 2026-10-01g_income_reverse_on_delete.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [45/67] 2026-10-01g_income_reverse_on_delete.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 5 — deleting a sale reverses its accounting and its points
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 5.
-- Test:    sql/tests/2026-10-01g_income_reverse_on_delete_test.sql
-- Hook:    modules/income.py calls it after a successful sp_income action=2.
--
-- OWNER DECISIONS (2026-10-01):
--   Q6 Rewards redemption = PURELY PROMOTIONAL → no journal entry is ever
--      created for points (earn, redeem, adjust, expire, reversal).
--   Sale deleted → its journal entries are VOIDed automatically.
--   Sale deleted → the points it earned are reversed.
--
-- WHY: sp_income action=2 hard-deletes the sale (income, incomeDetails,
-- cashRegisterMovements) but left its POSTED journal entries (Caja/Bancos and
-- Ventas kept counting a sale that no longer exists) and its earned points.
--
-- WHAT: dbo.sp_income_reverseOnDelete @incomeId
--   1. Journal: POSTED entries with referenceType IN ('income','income_commission')
--      and referenceId = @incomeId → status 'VOID' (the only mutation the
--      journal allows; nothing is deleted).
--   2. POS rewards (posRewardTransactions/posRewardBalances): the ticket's EARN
--      row (referenceType 'ticket', referenceId = incomeId) is taken back with
--      an ADJUSTMENT/D row. The schema allows referenceType ticket|redemption|
--      manual only, and the filtered unique index UQ_posRewardTransactions_ticket
--      reserves 'ticket' for the EARN row, so the reversal is
--      referenceType 'manual' + referenceId = incomeId + description
--      'Reversa venta eliminada #<incomeId>' (that pair is the idempotency key).
--   3. Loyalty rewards (rewardTransactions/rewardPoints, modules/rewards.py
--      earn_points_for_income: txType 'earn', referenceId = '<incomeId>'):
--      taken back with txType 'adjustment', points negative,
--      referenceId 'reversal:<incomeId>' (idempotency key).
--   Balances never go below zero: if the client already spent those points,
--   only what is left is taken back and the rest is reported as *Shortfall*
--   (also written in the adjustment's description).
--   Refuses to run while the income row still exists (it is a post-delete
--   step, never a way to cancel a live sale's books).
--   Idempotent. Savepoint-aware (testable inside a rolled-back transaction).
--   Returns ONE plain row: voidedEntries, posPointsReversed, posPointsShortfall,
--   loyaltyPointsReversed, loyaltyPointsShortfall, alreadyReversed.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_income_reverseOnDelete]
    @incomeId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @voided INT = 0,
            @posReversed DECIMAL(12,2) = 0, @posShort DECIMAL(12,2) = 0,
            @loyReversed INT = 0, @loyShort INT = 0,
            @alreadyReversed BIT = 0;
    DECLARE @tc INT = @@TRANCOUNT;
    DECLARE @tag NVARCHAR(60) = N'Reversa venta eliminada #' + CAST(@incomeId AS NVARCHAR(12));
    DECLARE @loyRef NVARCHAR(100) = N'reversal:' + CAST(@incomeId AS NVARCHAR(12));

    IF @incomeId IS NULL
    BEGIN
        RAISERROR('incomeId es requerido.', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM [dbo].[income] WHERE incomeId = @incomeId)
    BEGIN
        RAISERROR('La venta todavía existe: la reversa solo corre después de eliminarla.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        IF @tc = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION revIncome;

        -- 1) Journal: VOID the sale and its commission.
        UPDATE [dbo].[journalEntries]
        SET status = 'VOID', updated_at = GETUTCDATE()
        WHERE referenceType IN ('income', 'income_commission')
          AND referenceId = @incomeId
          AND status = 'POSTED';
        SET @voided = @@ROWCOUNT;

        -- 2) POS rewards.
        DECLARE @pc INT, @pcl INT, @earned DECIMAL(12,2), @bal DECIMAL(12,2), @nb DECIMAL(12,2);
        SELECT TOP 1 @pc = companyId, @pcl = clientId, @earned = points
        FROM [dbo].[posRewardTransactions]
        WHERE txType = 'EARN' AND referenceType = 'ticket' AND referenceId = @incomeId;

        IF @pc IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[posRewardTransactions]
                       WHERE companyId = @pc AND txType = 'ADJUSTMENT' AND referenceType = 'manual'
                         AND referenceId = @incomeId AND description LIKE @tag + N'%')
                SET @alreadyReversed = 1;
            ELSE
            BEGIN
                SELECT @bal = balance FROM [dbo].[posRewardBalances] WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @pc AND clientId = @pcl;
                SET @bal = ISNULL(@bal, 0);
                SET @posReversed = CASE WHEN @earned <= @bal THEN @earned WHEN @bal > 0 THEN @bal ELSE 0 END;
                SET @posShort = @earned - @posReversed;

                DECLARE @negPos DECIMAL(12,2) = -@posReversed;
                EXEC [dbo].[sp_posRewardBalances_applyDelta]
                    @companyId = @pc, @clientId = @pcl,
                    @pointsDelta = @negPos, @earnedDelta = @negPos, @redeemedDelta = 0,
                    @newBalance = @nb OUTPUT;

                INSERT INTO [dbo].[posRewardTransactions]
                    (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
                VALUES
                    (@pc, @pcl, 'ADJUSTMENT', 'D', @posReversed, 'manual', @incomeId, ISNULL(@nb, 0),
                     @tag + CASE WHEN @posShort > 0
                                 THEN N' (faltante ' + CAST(@posShort AS NVARCHAR(20)) + N' pts ya canjeados)'
                                 ELSE N'' END);
            END
        END

        -- 3) Loyalty rewards (rewardTransactions / rewardPoints).
        DECLARE @rc INT, @rcl INT, @rEarned INT, @rBal INT;
        SELECT TOP 1 @rc = companyId, @rcl = clientId
        FROM [dbo].[rewardTransactions]
        WHERE txType = 'earn' AND referenceId = CAST(@incomeId AS NVARCHAR(100));

        IF @rc IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[rewardTransactions]
                       WHERE companyId = @rc AND txType = 'adjustment' AND referenceId = @loyRef)
                SET @alreadyReversed = 1;
            ELSE
            BEGIN
                SELECT @rEarned = ISNULL(SUM(points), 0) FROM [dbo].[rewardTransactions]
                WHERE companyId = @rc AND clientId = @rcl AND txType = 'earn'
                  AND referenceId = CAST(@incomeId AS NVARCHAR(100));
                SELECT @rBal = balance FROM [dbo].[rewardPoints] WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @rc AND clientId = @rcl;
                SET @rBal = ISNULL(@rBal, 0);
                SET @loyReversed = CASE WHEN @rEarned <= @rBal THEN @rEarned WHEN @rBal > 0 THEN @rBal ELSE 0 END;
                SET @loyShort = @rEarned - @loyReversed;

                UPDATE [dbo].[rewardPoints]
                SET balance = balance - @loyReversed,
                    lifetimeEarned = lifetimeEarned - @loyReversed,
                    lastActivity = GETUTCDATE(), updated_at = GETUTCDATE()
                WHERE companyId = @rc AND clientId = @rcl;

                INSERT INTO [dbo].[rewardTransactions]
                    (companyId, clientId, ruleId, txType, points, balanceAfter, referenceId, description, createdBy)
                VALUES
                    (@rc, @rcl, NULL, 'adjustment', -@loyReversed,
                     ISNULL((SELECT balance FROM [dbo].[rewardPoints] WHERE companyId = @rc AND clientId = @rcl), 0),
                     @loyRef,
                     @tag + CASE WHEN @loyShort > 0
                                 THEN N' (faltante ' + CAST(@loyShort AS NVARCHAR(20)) + N' pts ya canjeados)'
                                 ELSE N'' END,
                     NULL);
            END
        END

        IF @tc = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tc = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF @tc > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION revIncome;
        THROW;
    END CATCH

    SELECT @voided AS voidedEntries,
           @posReversed AS posPointsReversed, @posShort AS posPointsShortfall,
           @loyReversed AS loyaltyPointsReversed, @loyShort AS loyaltyPointsShortfall,
           @alreadyReversed AS alreadyReversed;
END
GO

-- Verify (expect 1).
SELECT CASE WHEN OBJECT_ID('dbo.sp_income_reverseOnDelete', 'P') IS NOT NULL THEN 1 ELSE 0 END AS reverseOnDeleteDeployed;

-- Sales ALREADY deleted whose journal entries are still POSTED (report only —
-- not repaired here; Step 10 reconciliation decides, explicitly).
SELECT e.companyId, e.referenceType, COUNT(*) AS postedEntriesForDeletedSales, SUM(e.totalDebit) AS amount
FROM dbo.journalEntries e
WHERE e.status = 'POSTED'
  AND e.referenceType IN ('income', 'income_commission')
  AND NOT EXISTS (SELECT 1 FROM dbo.income i WHERE i.incomeId = e.referenceId)
GROUP BY e.companyId, e.referenceType;
GO

-- #############################################################################
-- [46/67] 2026-10-01h_opening_balance_guard.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [46/67] 2026-10-01h_opening_balance_guard.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 6 — opening balances: one per company, balance-sheet accounts only
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB, AFTER
-- 2026-10-01d_journalEntries_duplicate_guard.sql (already deployed).
-- Roadmap: POSVending/docs/accounting-module.md, Step 6 (§7.4).
-- Test:    sql/tests/2026-10-01h_opening_balance_guard_test.sql
-- UI:      Accounting → Libro Diario → Nuevo asiento → Tipo "Saldos iniciales".
--
-- OWNER DECISION (2026-10-01): opening balances for company 1 only, at ZERO for
-- now → no opening entry is posted today (the SP rejects zero-amount lines).
-- When real figures exist (Caja, Bancos, Deudas as of 2026-09-01) the owner
-- posts ONE entry with referenceType 'opening_balance', dated 2026-09-01:
--   Dr 1101 Caja / Dr 1105 Bancos  /  Cr 2105 Cuentas por pagar / Cr 3105 Capital social
--
-- RULES added to sp_journalEntries action=1 (inside the transaction, locked):
--   - at most ONE POSTED 'opening_balance' entry per company (VOID → replace);
--   - every line must be an ASSET / LIABILITY / EQUITY account.
-- Everything else in the SP is unchanged (repo body + Step 3 guard + this).
-- Stops without altering if the live SP no longer matches the repo version.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries'));
SELECT
    CASE WHEN @def LIKE '%Asiento no balanceado%' THEN 1 ELSE 0 END AS hasBalanceCheck,
    CASE WHEN @def LIKE '%duplicado rechazado%'   THEN 1 ELSE 0 END AS hasDuplicateGuard,
    CASE WHEN @def LIKE '%saldos iniciales%'      THEN 1 ELSE 0 END AS alreadyHasOpeningGuard;

-- Existing opening entries (expect 0 rows today).
SELECT companyId, status, COUNT(*) AS openingEntries
FROM dbo.journalEntries WHERE referenceType = 'opening_balance'
GROUP BY companyId, status;

IF @def IS NULL
   OR @def NOT LIKE '%Asiento no balanceado%'
   OR @def NOT LIKE '%duplicado rechazado%'
BEGIN
    RAISERROR('Live sp_journalEntries does not match the repo version (Step 3 guard missing?) — NOT altering.', 16, 1);
    SET NOEXEC ON;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- Sample payload (action=1 — post)
    DECLARE @pjsonfile NVARCHAR(MAX) = '
    {
      "journalEntries": [
        {
          "action": 1,
          "companyId": 1008,
          "entryDate": "2026-09-02",
          "description": "Venta #10234",
          "referenceType": "income",
          "referenceId": 10234,
          "createdByUserId": null,
          "lines": [
            { "accountId": 5,  "debit": 4500.00, "credit": 0,       "lineDescription": "Cobro en banco" },
            { "accountId": 12, "debit": 0,        "credit": 4500.00,"lineDescription": "Venta de producto" }
          ]
        }
      ]
    }';

    -- Sample payload (action=2 — void)
    DECLARE @pjsonfile NVARCHAR(MAX) = '
    {"journalEntries":[{"action":2,"entryId":123,"companyId":1008,"status":"VOID"}]}';
    */

    DECLARE @Error NVARCHAR(500) = N'';

    BEGIN TRY
        DECLARE @action    INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].action'));
        IF @action IS NULL RAISERROR('Invalid or missing action.', 16, 1);

        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId'));
        IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.companies WHERE companyId = @companyId)
            RAISERROR('companyId es requerido y debe existir.', 16, 1);

        IF @action = 1
        BEGIN
            --------------------------------------------------------------
            -- Header
            --------------------------------------------------------------
            DECLARE
                @entryDate       DATE          = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].entryDate')),
                @description     NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].description'),
                @referenceType   NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceType'),
                @referenceId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceId')),
                @createdByUserId INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].createdByUserId'));

            IF @entryDate IS NULL OR @description IS NULL
                RAISERROR('entryDate y description son requeridos.', 16, 1);

            --------------------------------------------------------------
            -- Lines
            --------------------------------------------------------------
            DECLARE @Lines TABLE (
                idx             INT IDENTITY(1,1) PRIMARY KEY,
                accountId       INT           NOT NULL,
                debit           DECIMAL(12,2) NOT NULL,
                credit          DECIMAL(12,2) NOT NULL,
                lineDescription NVARCHAR(255) NULL
            );

            INSERT INTO @Lines (accountId, debit, credit, lineDescription)
            SELECT
                TRY_CONVERT(INT, JSON_VALUE(L.value, '$.accountId')),
                ISNULL(TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(L.value, '$.debit')), 0),
                ISNULL(TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(L.value, '$.credit')), 0),
                JSON_VALUE(L.value, '$.lineDescription')
            FROM OPENJSON(JSON_QUERY(@pjsonfile, '$.journalEntries[0].lines')) L;

            IF (SELECT COUNT(*) FROM @Lines) < 2
                RAISERROR('Un asiento contable necesita al menos 2 líneas (Debe y Haber).', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE accountId IS NULL)
                RAISERROR('Todas las líneas requieren accountId.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE debit > 0 AND credit > 0)
                RAISERROR('Una línea no puede tener Debe y Haber al mismo tiempo.', 16, 1);

            IF EXISTS (SELECT 1 FROM @Lines WHERE debit = 0 AND credit = 0)
                RAISERROR('Cada línea debe tener un monto en Debe o en Haber.', 16, 1);

            IF EXISTS (
                SELECT 1 FROM @Lines Ln
                LEFT JOIN [dbo].[chartOfAccounts] A
                    ON A.accountId = Ln.accountId AND A.companyId = @companyId
                       AND A.isPostable = 1 AND A.isActive = 1
                WHERE A.accountId IS NULL
            )
                RAISERROR('Una o más accountId no son cuentas postulables activas de esta empresa.', 16, 1);

            DECLARE @sumDebit  DECIMAL(12,2) = (SELECT SUM(debit)  FROM @Lines);
            DECLARE @sumCredit DECIMAL(12,2) = (SELECT SUM(credit) FROM @Lines);

            IF ROUND(@sumDebit, 2) <> ROUND(@sumCredit, 2)
            BEGIN
                -- RAISERROR's %s placeholder only accepts (n)varchar args, never a
                -- DECIMAL directly — cast first or SQL Server rejects the RAISERROR itself.
                DECLARE @sumDebitStr  NVARCHAR(30) = CONVERT(NVARCHAR(30), @sumDebit);
                DECLARE @sumCreditStr NVARCHAR(30) = CONVERT(NVARCHAR(30), @sumCredit);
                RAISERROR('Asiento no balanceado: Debe (%s) <> Haber (%s).', 16, 1, @sumDebitStr, @sumCreditStr);
            END

            BEGIN TRAN;

            -- One POSTED entry per movement (Step 3, 2026-10-01): a retried
            -- auto-post hook or a backfill must never book the same income,
            -- expense or commission twice. VOID entries don't count, so a
            -- voided movement can be re-posted. The lock keeps two concurrent
            -- posts of the same reference from both passing the check.
            IF @referenceId IS NOT NULL
               AND @referenceType IN ('income', 'expense', 'income_commission')
               AND EXISTS (SELECT 1 FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                           WHERE companyId = @companyId AND referenceType = @referenceType
                             AND referenceId = @referenceId AND status = 'POSTED')
            BEGIN
                DECLARE @refStr NVARCHAR(60) = @referenceType + N' #' + CONVERT(NVARCHAR(20), @referenceId);
                RAISERROR('Ya existe un asiento POSTED para %s (duplicado rechazado).', 16, 1, @refStr);
            END

            -- Opening balances (Step 6, 2026-10-01): one POSTED 'opening_balance'
            -- entry per company (VOID it to replace it), and balance-sheet
            -- accounts only — an income/expense line would distort the result.
            IF @referenceType = 'opening_balance'
            BEGIN
                IF EXISTS (SELECT 1 FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                           WHERE companyId = @companyId AND referenceType = 'opening_balance'
                             AND status = 'POSTED')
                    RAISERROR('La empresa ya tiene un asiento de saldos iniciales POSTED (anúlalo antes de registrar otro).', 16, 1);

                IF EXISTS (SELECT 1 FROM @Lines Ln
                           JOIN [dbo].[chartOfAccounts] A ON A.accountId = Ln.accountId
                           WHERE A.accountType NOT IN ('ASSET', 'LIABILITY', 'EQUITY'))
                    RAISERROR('Los saldos iniciales solo pueden usar cuentas de Activo, Pasivo o Capital.', 16, 1);
            END

            -- Folio consecutivo por empresa; UPDLOCK+HOLDLOCK evita folios
            -- duplicados bajo inserciones concurrentes.
            DECLARE @entryNumber INT = (
                SELECT ISNULL(MAX(entryNumber), 0) + 1
                FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @companyId
            );

            INSERT INTO [dbo].[journalEntries]
                (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                 status, totalDebit, totalCredit, createdByUserId)
            VALUES
                (@companyId, @entryNumber, @entryDate, @description, @referenceType, @referenceId,
                 'POSTED', @sumDebit, @sumCredit, @createdByUserId);

            DECLARE @entryId INT = SCOPE_IDENTITY();

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT @entryId, accountId, debit, credit, lineDescription
            FROM @Lines;

            COMMIT TRAN;

            SELECT (SELECT TOP 1 entryId, companyId, entryNumber,
                           CONVERT(NVARCHAR, entryDate, 23) AS entryDate,
                           description, referenceType, referenceId, status,
                           totalDebit, totalCredit
                    FROM [dbo].[journalEntries]
                    WHERE entryId = @entryId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- VOID (única transición permitida: POSTED -> VOID)
        BEGIN
            DECLARE @entryIdToVoid INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].entryId'));
            DECLARE @newStatus     NVARCHAR(10) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].status');

            IF @entryIdToVoid IS NULL
                RAISERROR('entryId es requerido.', 16, 1);

            IF @newStatus IS NULL OR @newStatus <> 'VOID'
                RAISERROR('Solo se permite la transición POSTED -> VOID. entryDate/description/lines son inmutables una vez posteado.', 16, 1);

            IF NOT EXISTS (
                SELECT 1 FROM [dbo].[journalEntries]
                WHERE entryId = @entryIdToVoid AND companyId = @companyId AND status = 'POSTED'
            )
                RAISERROR('El asiento no existe, no pertenece a esta empresa, o ya no está POSTED.', 16, 1);

            UPDATE [dbo].[journalEntries]
            SET status = 'VOID', updated_at = GETUTCDATE()
            WHERE entryId = @entryIdToVoid AND companyId = @companyId;

            SELECT (SELECT TOP 1 entryId, entryNumber, status,
                           CONVERT(NVARCHAR, updated_at, 127) AS updated_at
                    FROM [dbo].[journalEntries]
                    WHERE entryId = @entryIdToVoid
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE — siempre rechazado
        BEGIN
            RAISERROR('DELETE no está permitido en journalEntries. Postea un asiento de reversión en su lugar.', 16, 1);
        END

        ELSE
            RAISERROR('Invalid action. Use 1=post, 2=void.', 16, 1);
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        SET @Error = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- Verify (expect 1, 1).
SELECT
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries')) LIKE '%saldos iniciales%' THEN 1 ELSE 0 END AS openingGuardDeployed,
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries')) LIKE '%duplicado rechazado%' THEN 1 ELSE 0 END AS duplicateGuardStillThere;
GO

SET NOEXEC OFF;
GO

-- #############################################################################
-- [47/67] 2026-10-01i_reconcile_and_backfill_movements.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [47/67] 2026-10-01i_reconcile_and_backfill_movements.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 7 — historical strategy: books from 2026-09-01 (Option A), reconciled
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 7 (§7.5).
-- Test:    sql/tests/2026-10-01i_reconcile_and_backfill_movements_test.sql
-- Repair:  sql/migration_history/migrations/2026-10-01j_run_books_period_repair.sql (explicit run)
--
-- OWNER DECISION (Q1, 2026-10-01): Option A — formal books start 2026-09-01.
-- Movements before that date stay operational history and are NEVER posted.
-- Inside the books period every income/expense/commission must be in the
-- journal exactly once; today they are not (e.g. the income hook silently
-- never fired for a while — see modules/income.py — so ~$7,040 of company 1's
-- September income has no entry).
--
-- 1) dbo.sp_journalEntries_reconcileMovements  (READ-ONLY; reused by Step 10)
--    @companyId INT = NULL, @fromDate DATE = '2026-09-01', @toDate DATE = NULL
--    One plain row per issue (no FOR JSON → testable with INSERT…EXEC):
--      issueType, companyId, referenceType, referenceId, movementAmount,
--      journalAmount, movementDate, journalDate
--    issueType:
--      MISSING_JOURNAL     movement in period, no entry at all for it
--      VOID_MISMATCH       movement exists, but its only entries are VOID
--      MISSING_COMMISSION  card sale with commissionAmount and a POSTED income
--                          entry, but no POSTED commission entry
--      AMOUNT_MISMATCH     POSTED entry total <> movement amount
--      DATE_MISMATCH       entryDate <> the movement's Hermosillo date
--      DUPLICATE_JOURNAL   more than one POSTED entry for the same reference
--      ORPHAN_JOURNAL      POSTED entry whose movement no longer exists
--      COMPANY_MISMATCH    POSTED entry in another company than its movement
--    Movement date = Hermosillo date of paymentDate (UTC-7).
--
-- 2) dbo.sp_journalEntries_backfillMovements  (explicit repair, dry run default)
--    @companyId INT = NULL, @fromDate DATE = '2026-09-01', @dryRun BIT = 1
--    Posts ONLY MISSING_JOURNAL movements (no entry at all, POSTED or VOID),
--    with the same map as modules/journalEntries.py (Step 3):
--      income   Efectivo → Dr 1101 Caja, else Dr 1105 Bancos / Cr 4105
--      expense  Dr by type (payroll 5110, general 5115, inventory 5105)
--               Cr 1101 Caja (Efectivo) or 1105 Bancos
--    entryDate = Hermosillo date of paymentDate. referenceType income/expense +
--    referenceId → the Step 3 guard rule; idempotent (re-run posts 0).
--    VOID_MISMATCH rows are NOT re-posted (a VOID was a decision; review them).
--    Savepoint-aware; returns ONE plain row:
--      dryRun, incomeCandidates, expenseCandidates, posted, postedAmount, skippedMissingAccount
-- Nothing is ever updated or deleted by either procedure.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_reconcileMovements]
    @companyId INT  = NULL,
    @fromDate  DATE = '2026-09-01',
    @toDate    DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Movements in the books period (Hermosillo date).
    DECLARE @mov TABLE (refType NVARCHAR(30), refId INT, companyId INT, amount DECIMAL(12,2), movDate DATE);
    INSERT INTO @mov
    SELECT 'income', i.incomeId, i.companyId, i.total, CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE)
    FROM [dbo].[income] i
    WHERE (@companyId IS NULL OR i.companyId = @companyId)
      AND i.paymentDate IS NOT NULL
      AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= @fromDate
      AND (@toDate IS NULL OR CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) <= @toDate);
    INSERT INTO @mov
    SELECT 'income_commission', i.incomeId, i.companyId, i.commissionAmount, CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE)
    FROM [dbo].[income] i
    WHERE (@companyId IS NULL OR i.companyId = @companyId)
      AND i.commissionAmount > 0 AND i.paymentDate IS NOT NULL
      AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= @fromDate
      AND (@toDate IS NULL OR CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) <= @toDate);
    INSERT INTO @mov
    SELECT 'expense', x.expenseId, x.companyId, x.total, CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE)
    FROM [dbo].[expenses] x
    WHERE (@companyId IS NULL OR x.companyId = @companyId)
      AND x.paymentDate IS NOT NULL
      AND CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE) >= @fromDate
      AND (@toDate IS NULL OR CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE) <= @toDate);

    -- Movement-linked journal entries (any company, any status) for those references
    -- + every POSTED movement entry dated in the period (for orphans/duplicates).
    DECLARE @je TABLE (entryId INT, refType NVARCHAR(30), refId INT, companyId INT, status NVARCHAR(10), amount DECIMAL(12,2), entryDate DATE);
    INSERT INTO @je
    SELECT e.entryId, e.referenceType, e.referenceId, e.companyId, e.status, e.totalDebit, e.entryDate
    FROM [dbo].[journalEntries] e
    WHERE e.referenceType IN ('income', 'income_commission', 'expense') AND e.referenceId IS NOT NULL
      AND (
            EXISTS (SELECT 1 FROM @mov m WHERE m.refType = e.referenceType AND m.refId = e.referenceId)
         OR (    e.status = 'POSTED'
             AND (@companyId IS NULL OR e.companyId = @companyId)
             AND e.entryDate >= @fromDate AND (@toDate IS NULL OR e.entryDate <= @toDate))
      );

    DECLARE @issues TABLE (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                           movementAmount DECIMAL(12,2) NULL, journalAmount DECIMAL(12,2) NULL,
                           movementDate DATE NULL, journalDate DATE NULL);

    -- MISSING_COMMISSION (needs the sale's POSTED income entry) / MISSING_JOURNAL / VOID_MISMATCH
    INSERT INTO @issues (issueType, companyId, referenceType, referenceId, movementAmount, movementDate)
    SELECT CASE WHEN m.refType = 'income_commission' THEN 'MISSING_COMMISSION'
                WHEN EXISTS (SELECT 1 FROM @je j WHERE j.refType = m.refType AND j.refId = m.refId) THEN 'VOID_MISMATCH'
                ELSE 'MISSING_JOURNAL' END,
           m.companyId, m.refType, m.refId, m.amount, m.movDate
    FROM @mov m
    WHERE NOT EXISTS (SELECT 1 FROM @je j WHERE j.refType = m.refType AND j.refId = m.refId AND j.status = 'POSTED')
      AND (m.refType <> 'income_commission'
           OR EXISTS (SELECT 1 FROM @je j WHERE j.refType = 'income' AND j.refId = m.refId AND j.status = 'POSTED'));

    -- AMOUNT / DATE / COMPANY mismatches on POSTED entries of existing movements
    INSERT INTO @issues (issueType, companyId, referenceType, referenceId, movementAmount, journalAmount, movementDate, journalDate)
    SELECT 'COMPANY_MISMATCH', j.companyId, j.refType, j.refId, m.amount, j.amount, m.movDate, j.entryDate
    FROM @je j JOIN @mov m ON m.refType = j.refType AND m.refId = j.refId
    WHERE j.status = 'POSTED' AND j.companyId <> m.companyId
    UNION ALL
    SELECT 'AMOUNT_MISMATCH', j.companyId, j.refType, j.refId, m.amount, j.amount, m.movDate, j.entryDate
    FROM @je j JOIN @mov m ON m.refType = j.refType AND m.refId = j.refId
    WHERE j.status = 'POSTED' AND j.companyId = m.companyId AND j.amount <> m.amount
    UNION ALL
    SELECT 'DATE_MISMATCH', j.companyId, j.refType, j.refId, m.amount, j.amount, m.movDate, j.entryDate
    FROM @je j JOIN @mov m ON m.refType = j.refType AND m.refId = j.refId
    WHERE j.status = 'POSTED' AND j.companyId = m.companyId AND j.entryDate <> m.movDate;

    -- DUPLICATE_JOURNAL
    INSERT INTO @issues (issueType, companyId, referenceType, referenceId, journalAmount)
    SELECT 'DUPLICATE_JOURNAL', j.companyId, j.refType, j.refId, SUM(j.amount)
    FROM @je j WHERE j.status = 'POSTED'
    GROUP BY j.companyId, j.refType, j.refId
    HAVING COUNT(*) > 1;

    -- ORPHAN_JOURNAL (movement gone)
    INSERT INTO @issues (issueType, companyId, referenceType, referenceId, journalAmount, journalDate)
    SELECT 'ORPHAN_JOURNAL', j.companyId, j.refType, j.refId, j.amount, j.entryDate
    FROM @je j
    WHERE j.status = 'POSTED'
      AND (   (j.refType IN ('income', 'income_commission') AND NOT EXISTS (SELECT 1 FROM [dbo].[income] i WHERE i.incomeId = j.refId))
           OR (j.refType = 'expense' AND NOT EXISTS (SELECT 1 FROM [dbo].[expenses] x WHERE x.expenseId = j.refId)));

    SELECT issueType, companyId, referenceType, referenceId, movementAmount, journalAmount, movementDate, journalDate
    FROM @issues
    ORDER BY companyId, issueType, referenceType, referenceId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_backfillMovements]
    @companyId INT  = NULL,
    @fromDate  DATE = '2026-09-01',
    @dryRun    BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @c TABLE (companyId INT, refType NVARCHAR(30), refId INT, amount DECIMAL(12,2), entryDate DATE,
                      drCode NVARCHAR(20), crCode NVARCHAR(20), drAccountId INT NULL, crAccountId INT NULL);
    DECLARE @posted INT = 0, @postedAmount DECIMAL(14,2) = 0;
    DECLARE @tc INT = @@TRANCOUNT;

    BEGIN TRY
        IF @dryRun = 0
        BEGIN
            IF @tc = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION bfMovements;
            DECLARE @lock INT = (SELECT COUNT(*) FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                                 WHERE @companyId IS NULL OR companyId = @companyId);
        END

        -- Income with no journal entry at all (POSTED or VOID).
        INSERT INTO @c (companyId, refType, refId, amount, entryDate, drCode, crCode)
        SELECT i.companyId, 'income', i.incomeId, i.total, CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE),
               CASE WHEN LOWER(LTRIM(RTRIM(i.paymentMethod))) IN ('efectivo', 'cash') THEN '1101' ELSE '1105' END,
               '4105'
        FROM [dbo].[income] i
        WHERE (@companyId IS NULL OR i.companyId = @companyId)
          AND i.total > 0 AND i.paymentDate IS NOT NULL
          AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= @fromDate
          AND NOT EXISTS (SELECT 1 FROM [dbo].[journalEntries] e
                          WHERE e.referenceType = 'income' AND e.referenceId = i.incomeId);

        -- Expenses with no journal entry at all.
        INSERT INTO @c (companyId, refType, refId, amount, entryDate, drCode, crCode)
        SELECT x.companyId, 'expense', x.expenseId, x.total, CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE),
               CASE LOWER(ISNULL(NULLIF(LTRIM(RTRIM(x.expenseType)), ''), 'inventory'))
                    WHEN 'payroll' THEN '5110' WHEN 'general' THEN '5115' ELSE '5105' END,
               CASE WHEN LOWER(LTRIM(RTRIM(x.paymentMethod))) IN ('efectivo', 'cash') THEN '1101' ELSE '1105' END
        FROM [dbo].[expenses] x
        WHERE (@companyId IS NULL OR x.companyId = @companyId)
          AND x.total > 0 AND x.paymentDate IS NOT NULL
          AND CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE) >= @fromDate
          AND NOT EXISTS (SELECT 1 FROM [dbo].[journalEntries] e
                          WHERE e.referenceType = 'expense' AND e.referenceId = x.expenseId);

        UPDATE c SET
            drAccountId = (SELECT a.accountId FROM [dbo].[chartOfAccounts] a
                           WHERE a.companyId = c.companyId AND a.code = c.drCode AND a.isPostable = 1 AND a.isActive = 1),
            crAccountId = (SELECT a.accountId FROM [dbo].[chartOfAccounts] a
                           WHERE a.companyId = c.companyId AND a.code = c.crCode AND a.isPostable = 1 AND a.isActive = 1)
        FROM @c c;

        IF @dryRun = 0
        BEGIN
            DECLARE @max TABLE (companyId INT PRIMARY KEY, maxNum INT);
            INSERT INTO @max (companyId, maxNum)
            SELECT d.companyId,
                   ISNULL((SELECT MAX(entryNumber) FROM [dbo].[journalEntries] WHERE companyId = d.companyId), 0)
            FROM (SELECT DISTINCT companyId FROM @c WHERE drAccountId IS NOT NULL AND crAccountId IS NOT NULL) d;

            DECLARE @map TABLE (entryId INT, companyId INT, refType NVARCHAR(30), refId INT);

            INSERT INTO [dbo].[journalEntries]
                (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                 status, totalDebit, totalCredit, createdByUserId)
            OUTPUT inserted.entryId, inserted.companyId, inserted.referenceType, inserted.referenceId
              INTO @map (entryId, companyId, refType, refId)
            SELECT c.companyId,
                   m.maxNum + ROW_NUMBER() OVER (PARTITION BY c.companyId ORDER BY c.entryDate, c.refType, c.refId),
                   c.entryDate,
                   CASE c.refType WHEN 'income' THEN N'Ingreso #' ELSE N'Egreso #' END
                       + CAST(c.refId AS NVARCHAR(12)) + N' (backfill)',
                   c.refType, c.refId, 'POSTED', c.amount, c.amount, NULL
            FROM @c c JOIN @max m ON m.companyId = c.companyId
            WHERE c.drAccountId IS NOT NULL AND c.crAccountId IS NOT NULL;

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT mp.entryId, c.drAccountId, c.amount, 0, N'Backfill libros 2026-09-01'
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.refType = mp.refType AND c.refId = mp.refId
            UNION ALL
            SELECT mp.entryId, c.crAccountId, 0, c.amount, N'Backfill libros 2026-09-01'
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.refType = mp.refType AND c.refId = mp.refId;

            SELECT @posted = COUNT(*), @postedAmount = ISNULL(SUM(c.amount), 0)
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.refType = mp.refType AND c.refId = mp.refId;

            IF @tc = 0 COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @tc = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF @tc > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION bfMovements;
        THROW;
    END CATCH

    SELECT @dryRun AS dryRun,
           (SELECT COUNT(*) FROM @c WHERE refType = 'income'  AND drAccountId IS NOT NULL AND crAccountId IS NOT NULL) AS incomeCandidates,
           (SELECT COUNT(*) FROM @c WHERE refType = 'expense' AND drAccountId IS NOT NULL AND crAccountId IS NOT NULL) AS expenseCandidates,
           @posted AS posted,
           @postedAmount AS postedAmount,
           (SELECT COUNT(*) FROM @c WHERE drAccountId IS NULL OR crAccountId IS NULL) AS skippedMissingAccount;
END
GO

-- ── Verify + READ-ONLY evidence (nothing is posted by this script) ───────────
SELECT CASE WHEN OBJECT_ID('dbo.sp_journalEntries_reconcileMovements', 'P') IS NOT NULL THEN 1 ELSE 0 END AS reconcileSpDeployed,
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillMovements', 'P') IS NOT NULL THEN 1 ELSE 0 END AS backfillMovementsSpDeployed;

CREATE TABLE #rec (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                   movementAmount DECIMAL(12,2), journalAmount DECIMAL(12,2), movementDate DATE, journalDate DATE);
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';

-- Summary per company / issue (books since 2026-09-01).
SELECT companyId, issueType, referenceType, COUNT(*) AS issues,
       SUM(movementAmount) AS movementAmount, SUM(journalAmount) AS journalAmount
FROM #rec GROUP BY companyId, issueType, referenceType ORDER BY companyId, issueType, referenceType;

-- What the repair would post (dry run).
EXEC dbo.sp_journalEntries_backfillMovements @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
DROP TABLE #rec;
GO

-- #############################################################################
-- [48/67] 2026-10-01j_run_books_period_repair.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [48/67] 2026-10-01j_run_books_period_repair.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 7 — REPAIR the books period (2026-09-01 onward), explicitly
-- =============================================================================
-- Run ONLY after:
--   - 2026-09-30_fix_expense_paymentdate_midnight.sql  (expense dates; checked below)
--   - 2026-10-01e_backfill_income_commissions_sp.sql   (Step 4 SP; checked below)
--   - 2026-10-01g_income_reverse_on_delete.sql         (Step 5 SP; checked below)
--   - 2026-10-01i_reconcile_and_backfill_movements.sql + its test → ALL PASS
--
-- Order (each part idempotent; nothing is ever updated except status→VOID):
--   1. BEFORE: reconciliation summary
--   2. Post every income/expense in the period that has NO entry at all
--      (sp_journalEntries_backfillMovements, Step 3 map, Hermosillo dates)
--   3. Post the card commissions of sales that now have an income entry
--      (sp_journalEntries_backfillIncomeCommissions, Step 4)
--   4. Deleted sales whose entries are still POSTED → sp_income_reverseOnDelete
--      (VOID + points reversal — owner decision for deleted sales, Step 5)
--   5. AFTER: reconciliation summary + detail of what remains
-- Remaining after the run, by design (NOT auto-repaired — decide explicitly):
--   VOID_MISMATCH, AMOUNT_MISMATCH, DATE_MISMATCH (posted entries are immutable;
--   legacy income entries dated with the UTC day), COMPANY_MISMATCH,
--   DUPLICATE_JOURNAL, expense ORPHAN_JOURNAL.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── Pre-checks ───────────────────────────────────────────────────────────────
DECLARE @midnightExpenses INT = (
    SELECT COUNT(*) FROM dbo.expenses
    WHERE paymentDate >= '2026-08-31' AND CAST(paymentDate AS TIME) = '00:00:00');
SELECT @midnightExpenses AS expensesStillAtUtcMidnight,
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillIncomeCommissions', 'P') IS NOT NULL THEN 1 ELSE 0 END AS step4SpPresent,
       CASE WHEN OBJECT_ID('dbo.sp_income_reverseOnDelete', 'P') IS NOT NULL THEN 1 ELSE 0 END AS step5SpPresent,
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillMovements', 'P') IS NOT NULL THEN 1 ELSE 0 END AS step7SpPresent;

IF @midnightExpenses > 0
   OR OBJECT_ID('dbo.sp_journalEntries_backfillIncomeCommissions', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_income_reverseOnDelete', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_journalEntries_backfillMovements', 'P') IS NULL
BEGIN
    RAISERROR('Prerequisites missing (midnight expense fix / Step 4, 5 or 7 SP) — nothing was posted.', 16, 1);
    SET NOEXEC ON;
END
GO

-- ── 1. BEFORE ────────────────────────────────────────────────────────────────
CREATE TABLE #rec (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                   movementAmount DECIMAL(12,2), journalAmount DECIMAL(12,2), movementDate DATE, journalDate DATE);
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
SELECT 'BEFORE' AS phase, companyId, issueType, referenceType, COUNT(*) AS issues,
       SUM(movementAmount) AS movementAmount, SUM(journalAmount) AS journalAmount
FROM #rec GROUP BY companyId, issueType, referenceType ORDER BY companyId, issueType, referenceType;

-- ── 2. Missing income / expense postings ─────────────────────────────────────
EXEC dbo.sp_journalEntries_backfillMovements @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 0;

-- ── 3. Commissions of sales that now have an income entry ────────────────────
EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 0;

-- ── 4. Deleted sales still counted → VOID + reverse points ───────────────────
DELETE FROM #rec;
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
DECLARE @orphanIncome INT;
DECLARE oc CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT referenceId FROM #rec
    WHERE issueType = 'ORPHAN_JOURNAL' AND referenceType IN ('income', 'income_commission');
OPEN oc; FETCH NEXT FROM oc INTO @orphanIncome;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_income_reverseOnDelete @incomeId = @orphanIncome;
    FETCH NEXT FROM oc INTO @orphanIncome;
END
CLOSE oc; DEALLOCATE oc;

-- ── 5. AFTER ─────────────────────────────────────────────────────────────────
DELETE FROM #rec;
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
SELECT 'AFTER' AS phase, companyId, issueType, referenceType, COUNT(*) AS issues,
       SUM(movementAmount) AS movementAmount, SUM(journalAmount) AS journalAmount
FROM #rec GROUP BY companyId, issueType, referenceType ORDER BY companyId, issueType, referenceType;

-- Gate: these must be 0 after the repair.
SELECT
    SUM(CASE WHEN issueType = 'MISSING_JOURNAL' THEN 1 ELSE 0 END)    AS missingJournal,
    SUM(CASE WHEN issueType = 'MISSING_COMMISSION' THEN 1 ELSE 0 END) AS missingCommission,
    SUM(CASE WHEN issueType = 'ORPHAN_JOURNAL' AND referenceType <> 'expense' THEN 1 ELSE 0 END) AS incomeOrphans
FROM #rec;

-- Detail of what remains for explicit decisions.
SELECT * FROM #rec ORDER BY companyId, issueType, referenceType, referenceId;

-- Operational vs journal for company 1, books period (totals should now agree
-- except for remaining AMOUNT/VOID/DUPLICATE items listed above).
SELECT 'operational' AS source,
       (SELECT ISNULL(SUM(total), 0) FROM dbo.income   WHERE companyId = 1 AND CAST(DATEADD(HOUR,-7,paymentDate) AS DATE) >= '2026-09-01') AS income,
       (SELECT ISNULL(SUM(total), 0) FROM dbo.expenses WHERE companyId = 1 AND CAST(DATEADD(HOUR,-7,paymentDate) AS DATE) >= '2026-09-01') AS expenses
UNION ALL
SELECT 'journal',
       (SELECT ISNULL(SUM(totalDebit), 0) FROM dbo.journalEntries WHERE companyId = 1 AND status = 'POSTED' AND referenceType = 'income'  AND entryDate >= '2026-09-01'),
       (SELECT ISNULL(SUM(totalDebit), 0) FROM dbo.journalEntries WHERE companyId = 1 AND status = 'POSTED' AND referenceType = 'expense' AND entryDate >= '2026-09-01');
DROP TABLE #rec;
GO

SET NOEXEC OFF;
GO

-- #############################################################################
-- [49/67] 2026-10-01k_add_income_payments.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [49/67] 2026-10-01k_add_income_payments.sql', 0, 1) WITH NOWAIT;
GO

-- incomePayments: itemized payment-method breakdown for a split-payment
-- sale (e.g. 60% Efectivo + 40% Tarjeta on one ticket). dbo.income.total and
-- dbo.income.paymentMethod stay as the single source of truth for the sale
-- total and a summary label ("Dividido" for a split sale) -- this table adds
-- the itemized detail underneath, same split as sp_clientLoginCodes's
-- "business logic in Python, storage in a plain proc" pattern used
-- elsewhere in this backend.
--
-- KNOWN GAP (2026-10-01): card-terminal commission journaling
-- (modules/income.py::_apply_terminal_commission /
-- post_income_commission_journal_entry) only fires when
-- income.paymentMethod is exactly 'tarjeta'/'terminal'. A split sale's
-- paymentMethod is 'Dividido', so the card portion of a split payment does
-- NOT get a commission journal entry yet -- deliberate v1 scope, not an
-- oversight. Fix in a follow-up once the commission math for a partial
-- card amount (not the full income.total) is worked out.

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'incomePayments')
CREATE TABLE [dbo].[incomePayments] (
    incomePaymentId INT IDENTITY(1,1) NOT NULL,
    incomeId        INT NOT NULL,
    method          VARCHAR(20) NOT NULL,   -- 'efectivo' | 'tarjeta' | 'transferir'
    amount          DECIMAL(10,2) NOT NULL,
    cashPaid        DECIMAL(10,2) NULL,     -- only meaningful for method='efectivo'
    cashReturn      DECIMAL(10,2) NULL,
    created_At      DATETIME2(7) NOT NULL DEFAULT (GETUTCDATE()),
    CONSTRAINT PK_incomePayments PRIMARY KEY CLUSTERED (incomePaymentId)
);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_incomePayments_incomeId' AND object_id = OBJECT_ID('dbo.incomePayments'))
CREATE NONCLUSTERED INDEX IX_incomePayments_incomeId ON dbo.incomePayments (incomeId);
GO

-- action 1 -- bulk insert the payment lines for one incomeId.
--   Input: { "incomePayments": [{ "action": 1, "incomeId": int,
--             "payments": [{ "method": str, "amount": num,
--                             "cashPaid": num|null, "cashReturn": num|null }, ...] }] }
-- action 2 -- list the payment lines for one incomeId (receipts).
--   Input: { "incomePayments": [{ "action": 2, "incomeId": int }] }
--   Output: { "result": [{ "payments": [...] }] }
CREATE OR ALTER PROC [dbo].[sp_incomePayments] (@pjsonfile NVARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @Outputmessage NVARCHAR(MAX) = '{
      "result": [{ "value": "", "msg": "", "error": "" }]
    }'

    DECLARE @action   INT = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action')) FROM OPENJSON(@pjsonfile, '$.incomePayments'));
    DECLARE @incomeId INT = (SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.incomeId')) FROM OPENJSON(@pjsonfile, '$.incomePayments'));

    BEGIN TRY
        IF @incomeId IS NULL
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'incomeId es requerido.')
        END
        ELSE IF @action = 1
        BEGIN
            DECLARE @paymentsArray NVARCHAR(MAX) = (
                SELECT TOP 1 JSON_QUERY(value, '$.payments') FROM OPENJSON(@pjsonfile, '$.incomePayments')
            );

            INSERT INTO dbo.incomePayments (incomeId, method, amount, cashPaid, cashReturn)
            SELECT @incomeId, p.method, p.amount, p.cashPaid, p.cashReturn
            FROM OPENJSON(@paymentsArray)
            WITH (
                method     VARCHAR(20)   '$.method',
                amount     DECIMAL(10,2) '$.amount',
                cashPaid   DECIMAL(10,2) '$.cashPaid',
                cashReturn DECIMAL(10,2) '$.cashReturn'
            ) AS p;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully')
        END
        ELSE IF @action = 2
        BEGIN
            DECLARE @paymentsJson NVARCHAR(MAX) = (
                SELECT incomePaymentId, incomeId, method, amount, cashPaid, cashReturn, created_At
                FROM dbo.incomePayments
                WHERE incomeId = @incomeId
                FOR JSON PATH
            );
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].payments', JSON_QUERY(ISNULL(@paymentsJson, '[]')))
        END
        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Unknown action.')
        END
    END TRY
    BEGIN CATCH
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE())
    END CATCH

    SELECT @Outputmessage AS jsonResult
END
GO

-- #############################################################################
-- [50/67] 2026-10-01k_balance_sheet.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [50/67] 2026-10-01k_balance_sheet.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 8 — Balance General (Estado de Situación Financiera) — read projection
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB, AFTER
-- 2026-10-01b_journal_accountTotals_fn.sql (uses fn_journalEntries_accountTotals).
-- Roadmap: POSVending/docs/accounting-module.md, Step 8 (§8).
-- Test:    sql/tests/2026-10-01k_balance_sheet_test.sql
-- API:     POST /journalEntries/balance-sheet (modules/journalEntries.py)
--
-- No new table, no stored balance: everything is computed from the journal
-- through dbo.fn_journalEntries_accountTotals (POSTED only, entryDate <= cutoff,
-- one company, signed by naturaleza) — the same aggregation as the Balanza.
--
-- OBJECTS
--   fn_journalEntries_balanceSheet(@companyId, @asOfDate)        inline TVF
--     one row per report line: section, grp, accountId, code, name, balance
--       ASSET     current (11xx and any other 1xxx) | nonCurrent (12xx)
--       LIABILITY current (21xx and any other 2xxx) | nonCurrent (22xx)
--       EQUITY    accounts
--       RESULT    priorYears  = Σ income − Σ expense, entryDate < Jan 1 of @asOfDate's year
--                 currentYear = Σ income − Σ expense, Jan 1 … @asOfDate
--     Accounts with a zero balance are omitted. No closing entries are needed:
--     income/expense are never zeroed; once real closing entries exist they
--     post to 3205/3210 and appear as equity accounts.
--   fn_journalEntries_balanceSheetJson(@companyId, @asOfDate)    scalar → JSON
--     { companyId, asOfDate,
--       assets:      { current:[{code,name,balance}], nonCurrent:[…], total },
--       liabilities: { current:[…], nonCurrent:[…], total },
--       equity:      { accounts:[…], priorYearsResult, currentYearResult, total },
--       totalLiabilitiesAndEquity, balanced }
--     balanced = ROUND(assets.total,2) = ROUND(totalLiabilitiesAndEquity,2)
--   sp_journalEntries_balanceSheet @pjsonfile
--     { "journalEntries":[{ "companyId":1, "asOfDate":"2026-09-30", "compareDate"?:"2025-12-31" }] }
--     asOfDate defaults to today in Hermosillo (UTC-7). With compareDate the
--     response gets "comparison": { same shape at compareDate }.
--     Returns one row/one column [jsonResult]; {"error":…} on bad input.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[fn_journalEntries_balanceSheet]
(
    @companyId INT,
    @asOfDate  DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH t AS (
        SELECT * FROM [dbo].[fn_journalEntries_accountTotals](@companyId, @asOfDate)
    ),
    priorYears AS (
        SELECT * FROM [dbo].[fn_journalEntries_accountTotals](@companyId, DATEADD(DAY, -1, DATEFROMPARTS(YEAR(@asOfDate), 1, 1)))
    )
    SELECT 'ASSET' AS section,
           CASE WHEN code LIKE '12%' THEN 'nonCurrent' ELSE 'current' END AS grp,
           accountId, code, name, balance
    FROM t WHERE accountType = 'ASSET' AND balance <> 0
    UNION ALL
    SELECT 'LIABILITY',
           CASE WHEN code LIKE '22%' THEN 'nonCurrent' ELSE 'current' END,
           accountId, code, name, balance
    FROM t WHERE accountType = 'LIABILITY' AND balance <> 0
    UNION ALL
    SELECT 'EQUITY', 'accounts', accountId, code, name, balance
    FROM t WHERE accountType = 'EQUITY' AND balance <> 0
    UNION ALL
    SELECT 'RESULT', 'priorYears', NULL, NULL, N'Resultados de ejercicios anteriores',
           ISNULL((SELECT SUM(CASE accountType WHEN 'INCOME' THEN balance ELSE -balance END)
                   FROM priorYears WHERE accountType IN ('INCOME', 'EXPENSE')), 0)
    UNION ALL
    SELECT 'RESULT', 'currentYear', NULL, NULL, N'Resultado del ejercicio',
           ISNULL((SELECT SUM(CASE accountType WHEN 'INCOME' THEN balance ELSE -balance END)
                   FROM t WHERE accountType IN ('INCOME', 'EXPENSE')), 0)
         - ISNULL((SELECT SUM(CASE accountType WHEN 'INCOME' THEN balance ELSE -balance END)
                   FROM priorYears WHERE accountType IN ('INCOME', 'EXPENSE')), 0)
);
GO

CREATE OR ALTER FUNCTION [dbo].[fn_journalEntries_balanceSheetJson]
(
    @companyId INT,
    @asOfDate  DATE
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @lines TABLE (section NVARCHAR(10), grp NVARCHAR(12), code NVARCHAR(20), name NVARCHAR(150), balance DECIMAL(14,2));
    INSERT INTO @lines (section, grp, code, name, balance)
    SELECT section, grp, code, name, balance FROM [dbo].[fn_journalEntries_balanceSheet](@companyId, @asOfDate);

    DECLARE @assets DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'ASSET'), 0);
    DECLARE @liabilities DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'LIABILITY'), 0);
    DECLARE @equityAccounts DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'EQUITY'), 0);
    DECLARE @prior DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'RESULT' AND grp = 'priorYears'), 0);
    DECLARE @current DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'RESULT' AND grp = 'currentYear'), 0);
    DECLARE @equity DECIMAL(14,2) = @equityAccounts + @prior + @current;

    RETURN (
        SELECT
            @companyId AS companyId,
            CONVERT(NVARCHAR(10), @asOfDate, 23) AS asOfDate,
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'ASSET' AND grp = 'current' ORDER BY code FOR JSON PATH), '[]')) AS [assets.current],
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'ASSET' AND grp = 'nonCurrent' ORDER BY code FOR JSON PATH), '[]')) AS [assets.nonCurrent],
            @assets AS [assets.total],
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'LIABILITY' AND grp = 'current' ORDER BY code FOR JSON PATH), '[]')) AS [liabilities.current],
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'LIABILITY' AND grp = 'nonCurrent' ORDER BY code FOR JSON PATH), '[]')) AS [liabilities.nonCurrent],
            @liabilities AS [liabilities.total],
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'EQUITY' ORDER BY code FOR JSON PATH), '[]')) AS [equity.accounts],
            @prior AS [equity.priorYearsResult],
            @current AS [equity.currentYearResult],
            @equity AS [equity.total],
            @liabilities + @equity AS totalLiabilitiesAndEquity,
            CAST(CASE WHEN ROUND(@assets, 2) = ROUND(@liabilities + @equity, 2) THEN 1 ELSE 0 END AS BIT) AS balanced
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_balanceSheet]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @companyId   INT  = TRY_CONVERT(INT,  JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId'));
    DECLARE @asOfRaw     NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].asOfDate');
    DECLARE @compareRaw  NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].compareDate');
    DECLARE @asOfDate    DATE = TRY_CONVERT(DATE, @asOfRaw);
    DECLARE @compareDate DATE = TRY_CONVERT(DATE, @compareRaw);

    IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[companies] WHERE companyId = @companyId)
    BEGIN
        SELECT N'{"error":"companyId es requerido y debe existir."}' AS [jsonResult];
        RETURN;
    END
    IF (@asOfRaw IS NOT NULL AND @asOfDate IS NULL) OR (@compareRaw IS NOT NULL AND @compareDate IS NULL)
    BEGIN
        SELECT N'{"error":"asOfDate/compareDate deben ser fechas YYYY-MM-DD."}' AS [jsonResult];
        RETURN;
    END

    -- Default cutoff: today in Hermosillo (UTC-7, no DST).
    SET @asOfDate = ISNULL(@asOfDate, CAST(DATEADD(HOUR, -7, GETUTCDATE()) AS DATE));

    DECLARE @json NVARCHAR(MAX) = [dbo].[fn_journalEntries_balanceSheetJson](@companyId, @asOfDate);
    IF @compareDate IS NOT NULL
        SET @json = JSON_MODIFY(@json, '$.comparison',
                                JSON_QUERY([dbo].[fn_journalEntries_balanceSheetJson](@companyId, @compareDate)));

    SELECT @json AS [jsonResult];
END
GO

-- Verify (expect 1, 1, 1).
SELECT CASE WHEN OBJECT_ID('dbo.fn_journalEntries_balanceSheet', 'IF') IS NOT NULL THEN 1 ELSE 0 END AS balanceSheetFn,
       CASE WHEN OBJECT_ID('dbo.fn_journalEntries_balanceSheetJson', 'FN') IS NOT NULL THEN 1 ELSE 0 END AS balanceSheetJsonFn,
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_balanceSheet', 'P') IS NOT NULL THEN 1 ELSE 0 END AS balanceSheetSp;
GO

-- #############################################################################
-- [51/67] 2026-10-01l_add_expense_service.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [51/67] 2026-10-01l_add_expense_service.sql', 0, 1) WITH NOWAIT;
GO

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

-- #############################################################################
-- [52/67] 2026-10-01l_correct_entry_dates.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [52/67] 2026-10-01l_correct_entry_dates.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 7 (cont.) — correct journal entries dated with the UTC day
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 7.
-- Test:    sql/tests/2026-10-01l_correct_entry_dates_test.sql
-- Run:     sql/migration_history/migrations/2026-10-01m_run_correct_entry_dates.sql (explicit)
--
-- WHY: until 2026-10-01 the posting helper took the first 10 characters of the
-- POS cart's UTC timestamp as the entry date, so sales after 17:00 Hermosillo
-- were dated the NEXT day. Live reconciliation (company 1): 29 income + 15
-- commission entries; 3 sales of Sept 30 evening ($700, commissions $29.40)
-- landed in October. Owner decision (2026-10-01): correct ALL of them.
--
-- HOW (the plan's correction mechanism — nothing is deleted or edited):
--   for each POSTED entry with referenceType income | income_commission |
--   expense whose entryDate <> the Hermosillo date of its movement
--   (income/expenses.paymentDate − 7h; a commission uses its sale's date):
--     1. status → VOID
--     2. a new POSTED entry: same companyId, referenceType, referenceId,
--        totals and lines; entryDate = the correct date; new folio;
--        description + ' (fecha corregida)'.
--   Idempotent: corrected entries match their movement, so a re-run finds 0.
--   Only same-company movements (COMPANY_MISMATCH entries are left alone).
--   Savepoint-aware. Returns ONE plain row: dryRun, candidates, corrected, amount
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_correctDates]
    @companyId INT  = NULL,
    @fromDate  DATE = '2026-09-01',
    @dryRun    BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @c TABLE (entryId INT PRIMARY KEY, companyId INT, correctDate DATE, amount DECIMAL(12,2));
    DECLARE @corrected INT = 0, @amount DECIMAL(14,2) = 0;
    DECLARE @tc INT = @@TRANCOUNT;

    BEGIN TRY
        IF @dryRun = 0
        BEGIN
            IF @tc = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION correctDates;
            DECLARE @lock INT = (SELECT COUNT(*) FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                                 WHERE @companyId IS NULL OR companyId = @companyId);
        END

        INSERT INTO @c (entryId, companyId, correctDate, amount)
        SELECT e.entryId, e.companyId, m.localDate, e.totalDebit
        FROM [dbo].[journalEntries] e
        CROSS APPLY (
            SELECT CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) AS localDate, i.companyId
            FROM [dbo].[income] i
            WHERE e.referenceType IN ('income', 'income_commission') AND i.incomeId = e.referenceId
            UNION ALL
            SELECT CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE), x.companyId
            FROM [dbo].[expenses] x
            WHERE e.referenceType = 'expense' AND x.expenseId = e.referenceId
        ) m
        WHERE e.status = 'POSTED'
          AND e.referenceType IN ('income', 'income_commission', 'expense')
          AND (@companyId IS NULL OR e.companyId = @companyId)
          AND m.companyId = e.companyId
          AND m.localDate IS NOT NULL
          AND m.localDate >= @fromDate
          AND e.entryDate <> m.localDate;

        IF @dryRun = 0
        BEGIN
            DECLARE @max TABLE (companyId INT PRIMARY KEY, maxNum INT);
            INSERT INTO @max (companyId, maxNum)
            SELECT d.companyId, ISNULL((SELECT MAX(entryNumber) FROM [dbo].[journalEntries] WHERE companyId = d.companyId), 0)
            FROM (SELECT DISTINCT companyId FROM @c) d;

            UPDATE e SET status = 'VOID', updated_at = GETUTCDATE()
            FROM [dbo].[journalEntries] e JOIN @c c ON c.entryId = e.entryId;

            DECLARE @map TABLE (oldEntryId INT, newEntryId INT);

            -- MERGE (not INSERT…SELECT) so OUTPUT can pair each new entry with its original.
            MERGE [dbo].[journalEntries] AS tgt
            USING (
                SELECT e.entryId AS oldEntryId, e.companyId,
                       m.maxNum + ROW_NUMBER() OVER (PARTITION BY e.companyId ORDER BY c.correctDate, e.entryId) AS entryNumber,
                       c.correctDate, LEFT(e.description, 255 - 18) + N' (fecha corregida)' AS description,
                       e.referenceType, e.referenceId, e.totalDebit, e.totalCredit
                FROM @c c
                JOIN [dbo].[journalEntries] e ON e.entryId = c.entryId
                JOIN @max m ON m.companyId = e.companyId
            ) AS src
            ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                        status, totalDebit, totalCredit, createdByUserId)
                VALUES (src.companyId, src.entryNumber, src.correctDate, src.description, src.referenceType,
                        src.referenceId, 'POSTED', src.totalDebit, src.totalCredit, NULL)
            OUTPUT src.oldEntryId, inserted.entryId INTO @map (oldEntryId, newEntryId);

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT mp.newEntryId, l.accountId, l.debit, l.credit, l.lineDescription
            FROM @map mp JOIN [dbo].[journalEntryLines] l ON l.journalEntryId = mp.oldEntryId;

            SELECT @corrected = COUNT(*) FROM @map;
            SELECT @amount = ISNULL(SUM(amount), 0) FROM @c;

            IF @tc = 0 COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @tc = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF @tc > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION correctDates;
        THROW;
    END CATCH

    SELECT @dryRun AS dryRun, (SELECT COUNT(*) FROM @c) AS candidates, @corrected AS corrected,
           CASE WHEN @dryRun = 1 THEN (SELECT ISNULL(SUM(amount), 0) FROM @c) ELSE @amount END AS amount;
END
GO

SELECT CASE WHEN OBJECT_ID('dbo.sp_journalEntries_correctDates', 'P') IS NOT NULL THEN 1 ELSE 0 END AS correctDatesSpDeployed;
-- Dry run, all companies (posts nothing).
EXEC dbo.sp_journalEntries_correctDates @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
GO

-- #############################################################################
-- [53/67] 2026-10-01m_run_correct_entry_dates.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [53/67] 2026-10-01m_run_correct_entry_dates.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Step 7 — RUN the date correction (explicit) + reconciliation
-- =============================================================================
-- Run ONLY after 2026-10-01l_correct_entry_dates.sql and its test → ALL PASS.
-- VOIDs every POSTED income / commission / expense entry dated with the wrong
-- (UTC) day and re-posts an identical copy on the Hermosillo day. Idempotent.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

EXEC dbo.sp_journalEntries_correctDates @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
EXEC dbo.sp_journalEntries_correctDates @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 0;
-- Re-run proof (expect candidates 0).
EXEC dbo.sp_journalEntries_correctDates @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;

CREATE TABLE #rec (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                   movementAmount DECIMAL(12,2), journalAmount DECIMAL(12,2), movementDate DATE, journalDate DATE);
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
-- Expect NO rows (every movement in the books period posted once, right amount, right day).
SELECT companyId, issueType, referenceType, COUNT(*) AS issues FROM #rec
GROUP BY companyId, issueType, referenceType ORDER BY companyId, issueType;
DROP TABLE #rec;

-- Company 1, September (Hermosillo): operational vs journal must now be equal.
SELECT 'operational' AS source,
       (SELECT SUM(total) FROM dbo.income WHERE companyId = 1
          AND CAST(DATEADD(HOUR,-7,paymentDate) AS DATE) BETWEEN '2026-09-01' AND '2026-09-30') AS septIncome,
       (SELECT SUM(commissionAmount) FROM dbo.income WHERE companyId = 1
          AND CAST(DATEADD(HOUR,-7,paymentDate) AS DATE) BETWEEN '2026-09-01' AND '2026-09-30') AS septCommission
UNION ALL
SELECT 'journal',
       (SELECT SUM(totalDebit) FROM dbo.journalEntries WHERE companyId = 1 AND status = 'POSTED'
          AND referenceType = 'income' AND entryDate BETWEEN '2026-09-01' AND '2026-09-30'),
       (SELECT SUM(totalDebit) FROM dbo.journalEntries WHERE companyId = 1 AND status = 'POSTED'
          AND referenceType = 'income_commission' AND entryDate BETWEEN '2026-09-01' AND '2026-09-30');
GO

-- #############################################################################
-- [54/67] 2026-10-02_expense_return_serviceid.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [54/67] 2026-10-02_expense_return_serviceid.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- sp_expense_all + sp_expense_monthly — also return serviceId
-- =============================================================================
-- NOT YET EXECUTED against any database -- run manually against the live DB.
--
-- WHY: 2026-10-01l_add_expense_service.sql added expenses.serviceId and
-- sp_expense now saves it (verified live: expense 1003 has serviceId = 3), but
-- explicitly left these two SELECT lists unchanged (see its KNOWN LIMITATION
-- note). Result: GET /all_expense and the month view never return serviceId,
-- so the Egresos list can't show WHICH service a 'general' expense paid
-- (Renta, CFE, Internet...) and falls back to the generic type label "General".
--
-- WHAT: adds e.serviceId to both SELECT lists. Nothing else changes — bodies
-- below are the LIVE definitions (read from the DB 2026-10-02, not the
-- repo's drifted copies) plus that one column. The frontend resolves the id to
-- a name the same way it already does for supplierId/employeeId.
-- Idempotent: CREATE OR ALTER. Rollback = re-run without e.serviceId.
-- =============================================================================

CREATE OR ALTER PROC [dbo].[sp_expense_all]
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM [dbo].[expenses])
    BEGIN
        SELECT
            e.expenseId,
            e.orderId,
            e.total,
            e.paymentMethod,
            e.paymentDate,
            e.userId,
            e.supplierId,
            e.serviceId,
            e.companyId,
            e.expenseType,
            e.employeeId,
            e.notes,
            e.receiptUrl
        FROM [dbo].[expenses] e
        FOR JSON AUTO, ROOT('expenses');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [expenses]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO

CREATE OR ALTER PROC [dbo].[sp_expense_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT, @year INT, @month INT;

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @year      = TRY_CONVERT(INT, JSON_VALUE(value, '$.year')),
        @month     = TRY_CONVERT(INT, JSON_VALUE(value, '$.month'))
    FROM OPENJSON(@pjsonfile, '$.expenses');

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    IF @year IS NULL OR @month IS NULL OR @month NOT BETWEEN 1 AND 12 OR @year NOT BETWEEN 2000 AND 2100
    BEGIN
        SET @year  = YEAR(@HermosilloNow);
        SET @month = MONTH(@HermosilloNow);
    END

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(@year, @month, 1) AS DATETIME));
    DECLARE @MonthEndUtc   DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);
    DECLARE @TrendStartUtc DATETIME = DATEADD(MONTH, -11, @MonthStartUtc);

    SELECT
        JSON_QUERY(ISNULL((
            SELECT
                e.expenseId,
                e.orderId,
                e.total,
                e.paymentMethod,
                e.paymentDate,
                e.userId,
                e.supplierId,
                e.serviceId,
                e.companyId,
                e.expenseType,
                e.employeeId,
                e.notes,
                e.receiptUrl
            FROM [dbo].[expenses] e
            WHERE e.companyId = @companyId
              AND e.paymentDate >= @MonthStartUtc
              AND e.paymentDate <  @MonthEndUtc
            ORDER BY e.paymentDate DESC
            FOR JSON PATH
        ), '[]')) AS [expenses],
        JSON_QUERY(ISNULL((
            SELECT
                YEAR(h.localDate)  AS [year],
                MONTH(h.localDate) AS [month],
                SUM(h.total)       AS [total],
                COUNT(*)           AS [count]
            FROM (
                SELECT DATEADD(HOUR, -7, e.paymentDate) AS localDate, e.total
                FROM [dbo].[expenses] e
                WHERE e.companyId = @companyId
                  AND e.paymentDate >= @TrendStartUtc
                  AND e.paymentDate <  @MonthEndUtc
            ) h
            GROUP BY YEAR(h.localDate), MONTH(h.localDate)
            ORDER BY [year], [month]
            FOR JSON PATH
        ), '[]')) AS [monthlyTotals]
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO

-- #############################################################################
-- [55/67] 2026-10-02b_expense_item_quantity_cost_supplies.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [55/67] 2026-10-02b_expense_item_quantity_cost_supplies.sql', 0, 1) WITH NOWAIT;
GO

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
-- [run-all] skipped once products.categoryId is renamed (superseded by 2026-10-15)
IF COL_LENGTH('dbo.products', 'categoryId') IS NOT NULL
    EXEC (N'CREATE OR ALTER PROC [dbo].[sp_products_save]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = ''{"result":[{ "value":"", "msg":"", "error":"" }]}'',
        @Error NVARCHAR(500) = '''',
        @action INT,
        @companyId INT,
        @productId INT;

    BEGIN TRY
        -- 1. Extract Root Context
        SELECT TOP (1)
            @action = TRY_CAST(JSON_VALUE(value, ''$.action'') AS INT),
            @companyId = TRY_CAST(JSON_VALUE(value, ''$.companyId'') AS INT),
            @productId = TRY_CAST(JSON_VALUE(value, ''$.productId'') AS INT)
        FROM OPENJSON(@pjsonfile, ''$.products'');

        -- Validations
        IF @action IS NULL RAISERROR(''action is required (1=insert, 2=update, 3=delete).'', 16, 1);
        IF @companyId IS NULL RAISERROR(''companyId is required.'', 16, 1);
        IF @companyId <> 1 RAISERROR(''Invalid companyId.'', 16, 1);

        BEGIN TRANSACTION;

        /* ============================================================
           STEP 1: BASE PRODUCTS
           ============================================================ */
        IF @action = 1
        BEGIN
            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, categoryId, companyId, isSupply)
            SELECT 
                JSON_VALUE(value, ''$.name''), JSON_VALUE(value, ''$.barCode''), JSON_VALUE(value, ''$.code''),
                JSON_VALUE(value, ''$.dateOfExpire''), TRY_CAST(JSON_VALUE(value, ''$.productFormId'') AS INT),
                TRY_CAST(JSON_VALUE(value, ''$.manufactureId'') AS INT), JSON_VALUE(value, ''$.description''),
                GETDATE(), TRY_CAST(JSON_VALUE(value, ''$.categoryId'') AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, ''$.isSupply'') AS BIT), 0)
            FROM OPENJSON(@pjsonfile, ''$.products'');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR(''productId is required for update.'', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, ''$.name''), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, ''$.barCode''), p.barCode),
                p.code = COALESCE(JSON_VALUE(j.value, ''$.code''), p.code),
                p.dateOfExpire = COALESCE(JSON_VALUE(j.value, ''$.dateOfExpire''), p.dateOfExpire),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.productFormId'') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.manufactureId'') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, ''$.description''), p.description),
                p.updatedAt = GETDATE(),
                p.categoryId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.categoryId'') AS INT), p.categoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.isSupply'') AS BIT), p.isSupply)
            FROM dbo.products p
            CROSS APPLY OPENJSON(@pjsonfile, ''$.products'') j
            WHERE p.productId = @productId AND p.companyId = @companyId;
        END
        ELSE IF @action = 3
        BEGIN
            -- Clean up everything associated with this product (Cascade Delete)
            DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
            DELETE FROM dbo.productOptions WHERE productId = @productId;
            DELETE FROM dbo.productDetails WHERE productId = @productId;
            IF OBJECT_ID(''dbo.productsDescription'', ''U'') IS NOT NULL DELETE FROM dbo.productsDescription WHERE productId = @productId;
            DELETE FROM dbo.products WHERE productId = @productId AND companyId = @companyId;

            COMMIT TRANSACTION;
            
            -- Early return on successful delete
            SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].value'', CAST(@productId AS NVARCHAR(50))), ''$.result[0].msg'', ''Deleted Successfully'');
            SELECT JSON_VALUE(value, ''$.value'') AS [value], JSON_VALUE(value, ''$.msg'') AS [msg], JSON_VALUE(value, ''$.error'') AS [error] FROM OPENJSON(@Outputmessage, ''$.result'');
            RETURN;
        END

        /* ============================================================
           STEP 2: PRODUCT DETAILS (Simple IF EXISTS Check)
           ============================================================ */
        DECLARE @stock INT, @uPrice DECIMAL(10,2), @sPrice DECIMAL(10,2);
        
        SELECT 
            @stock = TRY_CAST(JSON_VALUE(value, ''$.stockQuantity'') AS INT),
            @uPrice = TRY_CAST(JSON_VALUE(value, ''$.unitPrice'') AS DECIMAL(10,2)),
            @sPrice = TRY_CAST(JSON_VALUE(value, ''$.salePrice'') AS DECIMAL(10,2))
        FROM OPENJSON(@pjsonfile, ''$.productDetails'');

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
        IF OBJECT_ID(''dbo.productsDescription'', ''U'') IS NOT NULL
        BEGIN
            DELETE FROM dbo.productsDescription WHERE productId = @productId;

            INSERT INTO dbo.productsDescription (productId, Dosage, measurementId, is_principal, activeIngredientId)
            SELECT 
                @productId, JSON_VALUE(value, ''$.Dosage''), 
                TRY_CAST(JSON_VALUE(value, ''$.measurementId'') AS INT), 
                JSON_VALUE(value, ''$.is_principal''), 
                TRY_CAST(JSON_VALUE(value, ''$.activeIngredientId'') AS INT)
            FROM OPENJSON(@pjsonfile, ''$.productDescriptions'');
        END

        /* ============================================================
           STEP 4: OPTIONS AND CHOICES (Simple Loop/Insert Pattern)
           ============================================================ */
        -- Clear old configurations to avoid messy updates
        DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
        DELETE FROM dbo.productOptions WHERE productId = @productId;

        -- We use a cursor or simple loop over the array index to keep identities synchronized
        DECLARE @index INT = 0, @maxOptions INT;
        SET @maxOptions = (SELECT COUNT(*) FROM OPENJSON(@pjsonfile, ''$.productOptions''));

        WHILE @index < @maxOptions
        BEGIN
            DECLARE @optPath NVARCHAR(100) = ''$.productOptions['' + CAST(@index AS NVARCHAR(10)) + '']'';
            DECLARE @newOptId INT;

            -- Insert the Option Node
            INSERT INTO dbo.productOptions (productId, optionKey, name, type, createdAt, updatedAt)
            SELECT @productId, JSON_VALUE(@pjsonfile, @optPath + ''.optionKey''), JSON_VALUE(@pjsonfile, @optPath + ''.name''), JSON_VALUE(@pjsonfile, @optPath + ''.type''), GETDATE(), GETDATE();
            
            SET @newOptId = SCOPE_IDENTITY();

            -- Insert Nested Choices matching this exact option index
            INSERT INTO dbo.productOptionChoices (productOptionId, choiceKey, name, price, description, createdAt, updatedAt)
            SELECT 
                @newOptId,
                JSON_VALUE(value, ''$.choiceKey''),
                JSON_VALUE(value, ''$.name''),
                COALESCE(TRY_CAST(JSON_VALUE(value, ''$.price'') AS DECIMAL(10,2)), 0.00),
                COALESCE(JSON_VALUE(value, ''$.description''), ''''),
                GETDATE(),
                GETDATE()
            FROM OPENJSON(@pjsonfile, @optPath + ''.optionChoices'');

            SET @index = @index + 1;
        END

        COMMIT TRANSACTION;

        -- Success Output Compilation
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].value'', CAST(@productId AS NVARCHAR(50))), ''$.result[0].msg'', CASE WHEN @action = 1 THEN ''Inserted Successfully'' ELSE ''Updated Successfully'' END);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].error'', ''1''), ''$.result[0].msg'', @Error);
    END CATCH;

    -- Return Status Response
    SELECT JSON_VALUE(value, ''$.value'') AS [value], JSON_VALUE(value, ''$.msg'') AS [msg], JSON_VALUE(value, ''$.error'') AS [error] FROM OPENJSON(@Outputmessage, ''$.result'');
END');
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


-- #############################################################################
-- [56/67] 2026-10-02c_company_token_ledger.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [56/67] 2026-10-02c_company_token_ledger.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Company token ledger — prepaid AI-token balance per company
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB.
--
-- WHY: reading a ticket / chatting with a support agent costs real Gemini
-- tokens, and nothing recorded them (the agents service never stored usage; the
-- agentCostLog PRD was authored but never built). The POS needs to show how many
-- tokens each company has left.
--
-- WHAT: one APPEND-ONLY ledger. Top-ups are positive rows, each agent call is a
-- negative row carrying its real input/output/thought token counts. The balance
-- is SUM(tokensDelta), so the usage log and the balance can never disagree and a
-- correction is a new 'adjustment' row, never an edit.
--   * dbo.companyTokenLedger
--   * sp_companyTokens_record   — one agent call's usage (called by LoanAgents)
--   * sp_companyTokens_topup    — add tokens to a company's balance
--   * sp_companyTokens_balance  — balance + used today / this month (Hermosillo)
-- All JSON in / JSON out via @pjsonfile like the rest of the codebase.
-- Starts at balance 0: nothing is granted automatically — top up explicitly.
-- ROLLBACK: DROP the three procedures, then the table (loses the ledger).
-- =============================================================================

IF OBJECT_ID('dbo.companyTokenLedger', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.companyTokenLedger (
        ledgerId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_companyTokenLedger PRIMARY KEY,
        companyId      INT            NOT NULL,
        -- + top-up / adjustment in, - usage out
        tokensDelta    BIGINT         NOT NULL,
        entryType      VARCHAR(20)    NOT NULL,
        agentName      NVARCHAR(100)  NULL,
        endpointName   NVARCHAR(100)  NULL,
        model          NVARCHAR(100)  NULL,
        inputTokens    INT            NULL,
        outputTokens   INT            NULL,
        thoughtsTokens INT            NULL,
        reference      NVARCHAR(100)  NULL,
        notes          NVARCHAR(300)  NULL,
        createdBy      INT            NULL,
        createdAt      DATETIME       NOT NULL CONSTRAINT DF_companyTokenLedger_createdAt DEFAULT GETUTCDATE(),
        CONSTRAINT CK_companyTokenLedger_type CHECK (entryType IN ('topup', 'usage', 'adjustment')),
        CONSTRAINT FK_companyTokenLedger_company FOREIGN KEY (companyId) REFERENCES dbo.companies (companyId)
    );
    CREATE INDEX IX_companyTokenLedger_company_date ON dbo.companyTokenLedger (companyId, createdAt) INCLUDE (tokensDelta, entryType);
END
GO

CREATE OR ALTER PROC [dbo].[sp_companyTokens_record] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT, @agentName NVARCHAR(100), @endpointName NVARCHAR(100), @model NVARCHAR(100),
            @input INT, @output INT, @thoughts INT, @reference NVARCHAR(100);

    SELECT TOP 1
        @companyId    = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @agentName    = JSON_VALUE(value, '$.agentName'),
        @endpointName = JSON_VALUE(value, '$.endpointName'),
        @model        = JSON_VALUE(value, '$.model'),
        @input        = TRY_CONVERT(INT, JSON_VALUE(value, '$.inputTokens')),
        @output       = TRY_CONVERT(INT, JSON_VALUE(value, '$.outputTokens')),
        @thoughts     = TRY_CONVERT(INT, JSON_VALUE(value, '$.thoughtsTokens')),
        @reference    = JSON_VALUE(value, '$.reference')
    FROM OPENJSON(@pjsonfile, '$.tokens');

    IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.companies WHERE companyId = @companyId)
    BEGIN
        SELECT CAST(0 AS BIT) AS recorded, N'companyId inválido' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    DECLARE @total BIGINT = COALESCE(@input, 0) + COALESCE(@output, 0) + COALESCE(@thoughts, 0);
    IF @total <= 0
    BEGIN
        SELECT CAST(0 AS BIT) AS recorded, N'sin tokens que registrar' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    INSERT INTO dbo.companyTokenLedger
        (companyId, tokensDelta, entryType, agentName, endpointName, model, inputTokens, outputTokens, thoughtsTokens, reference)
    VALUES
        (@companyId, -@total, 'usage', @agentName, @endpointName, @model, @input, @output, @thoughts, @reference);

    SELECT CAST(1 AS BIT) AS recorded,
           @total AS tokens,
           (SELECT SUM(tokensDelta) FROM dbo.companyTokenLedger WHERE companyId = @companyId) AS balance
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO

CREATE OR ALTER PROC [dbo].[sp_companyTokens_topup] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT, @tokens BIGINT, @notes NVARCHAR(300), @userId INT, @entryType VARCHAR(20);

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @tokens    = TRY_CONVERT(BIGINT, JSON_VALUE(value, '$.tokens')),
        @notes     = JSON_VALUE(value, '$.notes'),
        @userId    = TRY_CONVERT(INT, JSON_VALUE(value, '$.userId')),
        @entryType = COALESCE(JSON_VALUE(value, '$.entryType'), 'topup')
    FROM OPENJSON(@pjsonfile, '$.tokens');

    IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.companies WHERE companyId = @companyId)
    BEGIN
        SELECT CAST(0 AS BIT) AS ok, N'companyId inválido' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END
    -- A top-up must add; only an explicit 'adjustment' may carry a negative correction.
    IF @tokens IS NULL OR @tokens = 0 OR (@tokens < 0 AND @entryType <> 'adjustment') OR @entryType NOT IN ('topup', 'adjustment')
    BEGIN
        SELECT CAST(0 AS BIT) AS ok, N'tokens inválidos' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    INSERT INTO dbo.companyTokenLedger (companyId, tokensDelta, entryType, notes, createdBy)
    VALUES (@companyId, @tokens, @entryType, @notes, @userId);

    SELECT CAST(1 AS BIT) AS ok,
           (SELECT SUM(tokensDelta) FROM dbo.companyTokenLedger WHERE companyId = @companyId) AS balance
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO

CREATE OR ALTER PROC [dbo].[sp_companyTokens_balance] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')) FROM OPENJSON(@pjsonfile, '$.tokens'));

    IF @companyId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS ok, N'companyId requerido' AS error FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    -- "Today" and "this month" are Hermosillo calendar periods (UTC-7, no DST).
    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    DECLARE @TodayStartUtc DATETIME = DATEADD(HOUR, 7, CAST(CAST(@HermosilloNow AS DATE) AS DATETIME));
    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(YEAR(@HermosilloNow), MONTH(@HermosilloNow), 1) AS DATETIME));

    SELECT
        CAST(1 AS BIT) AS ok,
        @companyId AS companyId,
        COALESCE(SUM(tokensDelta), 0) AS balance,
        COALESCE(-SUM(CASE WHEN entryType = 'usage' AND createdAt >= @TodayStartUtc THEN tokensDelta END), 0) AS usedToday,
        COALESCE(-SUM(CASE WHEN entryType = 'usage' AND createdAt >= @MonthStartUtc THEN tokensDelta END), 0) AS usedThisMonth,
        COALESCE(SUM(CASE WHEN entryType = 'usage' AND createdAt >= @MonthStartUtc THEN 1 ELSE 0 END), 0) AS callsThisMonth,
        (SELECT TOP 1 tokensDelta FROM dbo.companyTokenLedger WHERE companyId = @companyId AND entryType = 'topup' ORDER BY createdAt DESC, ledgerId DESC) AS lastTopupTokens,
        (SELECT TOP 1 createdAt   FROM dbo.companyTokenLedger WHERE companyId = @companyId AND entryType = 'topup' ORDER BY createdAt DESC, ledgerId DESC) AS lastTopupAt
    FROM dbo.companyTokenLedger
    WHERE companyId = @companyId
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO

-- #############################################################################
-- [57/67] 2026-10-02c_expense_ledger_sync_reads.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [57/67] 2026-10-02c_expense_ledger_sync_reads.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Reads for the expense -> ledger sync, as SPs (no raw SQL in modules/)
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, BEFORE deploying the
-- backend that calls these SPs (modules/journalEntries.py).
--
-- WHY: modules/journalEntries.py::_fetch_expense and
-- ::_fetch_posted_expense_entries (expense edit/delete -> ledger, "expenses
-- module v7") read dbo.expenses / dbo.journalEntries with raw SELECTs.
-- Backend rule: modules never issue raw SQL — only EXEC [dbo].[sp_*].
-- scripts/check_raw_sql.py flags both, which fails the deploy build on main.
--
-- SCOPE: two new read-only SPs, no table/column changes. Same convention as
-- sp_journalEntries / sp_journalEntries_one: @pjsonfile NVARCHAR(MAX), fields
-- via JSON_VALUE on $.<root>[0], one [jsonResult] column, FOR JSON PATH.
--
--   sp_expense_one  {"expenses":[{"expenseId":N,"companyId":N}]}
--     -> {"expenseId","companyId","total","paymentMethod","expenseType"}
--        or '{}' when the expense no longer exists (deleted) or belongs to
--        another company.
--
--   sp_journalEntries_byReference
--        {"journalEntries":[{"companyId":N,"referenceType":"expense",
--                            "referenceId":N,"status":"POSTED"}]}  (status optional)
--     -> [{"entryId","companyId","entryDate":"YYYY-MM-DD","amount",
--          "debitCode","creditCode"}, ...] ordered by entryId, or '[]'.
--        debitCode/creditCode = the account code of the first debit / credit
--        line — the 2-line shape the auto-post writes.
--
-- companyId is REQUIRED and filters both reads (multi-tenancy rule: never
-- return cross-company data). The backend passes the companyId of the
-- expense request being synced. Consequence, accepted 2026-10-02: an expense
-- moved to another company (sp_expense action 2 can still overwrite
-- companyId) is not followed across companies — its old company's entry is
-- left as-is. Closing that hole belongs in sp_expense (scope action 2/3 by
-- companyId and stop it changing companyId), not in these reads.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_expense_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @expenseId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].expenseId'));
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.expenses[0].companyId'));

        IF @expenseId IS NULL OR @companyId IS NULL
        BEGIN
            SELECT '{"error":"expenseId and companyId are required"}' AS [jsonResult];
            RETURN;
        END

        SELECT ISNULL(
            (SELECT expenseId, companyId, total, paymentMethod, expenseType
               FROM dbo.expenses
              WHERE expenseId = @expenseId
                AND companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES),
            '{}'
        ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_byReference]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId     INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId'));
        DECLARE @referenceType NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceType');
        DECLARE @referenceId   INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.journalEntries[0].referenceId'));
        DECLARE @status        NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].status');

        IF @companyId IS NULL OR @referenceType IS NULL OR @referenceId IS NULL
        BEGIN
            SELECT '{"error":"companyId, referenceType and referenceId are required"}' AS [jsonResult];
            RETURN;
        END

        SELECT ISNULL(
            (SELECT e.entryId,
                    e.companyId,
                    CONVERT(VARCHAR(10), e.entryDate, 23) AS entryDate,
                    e.totalDebit AS amount,
                    (SELECT TOP 1 c.code
                       FROM dbo.journalEntryLines l
                       JOIN dbo.chartOfAccounts c ON c.accountId = l.accountId
                      WHERE l.journalEntryId = e.entryId AND l.debit > 0
                      ORDER BY l.journalEntryLineId) AS debitCode,
                    (SELECT TOP 1 c.code
                       FROM dbo.journalEntryLines l
                       JOIN dbo.chartOfAccounts c ON c.accountId = l.accountId
                      WHERE l.journalEntryId = e.entryId AND l.credit > 0
                      ORDER BY l.journalEntryLineId) AS creditCode
               FROM dbo.journalEntries e
              WHERE e.companyId     = @companyId
                AND e.referenceType = @referenceType
                AND e.referenceId   = @referenceId
                AND (@status IS NULL OR e.status = @status)
              ORDER BY e.entryId
             FOR JSON PATH, INCLUDE_NULL_VALUES),
            '[]'
        ) AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO

-- #############################################################################
-- [58/67] 2026-10-06_backfill_client_companyId_from_sales.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [58/67] 2026-10-06_backfill_client_companyId_from_sales.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Backfill dbo.clients.companyId from the store where the client buys
-- =============================================================================
-- Forward-only data migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB. Run step 1 alone first
-- and review it; step 2 changes data.
--
-- WHY: the POS "register client" form in the cart
-- (POSVending src/components/pos/ClientSelector.tsx) never sent companyId,
-- so every client registered at the counter was saved with companyId NULL.
-- Found 2026-10-06 with clientId 2260 (Carlos Corral): 2 sales in company 1
-- (gmoLavanderia) but no company, so he was missing from the store's client
-- list and every company-scoped rewards/report query. Frontend fixed the
-- same day (the form now sends companyId); this repairs existing rows.
--
-- RULE: a NULL-company client gets the company of their sales ONLY when all
-- of their sales are in exactly one company. Clients with no sales, or with
-- sales in more than one company, are listed in step 3 and left alone — that
-- needs a person to decide, not a guess.
-- Idempotent: only rows with companyId IS NULL are touched.
-- =============================================================================

-- ── 1. Preview: who would be fixed, and to which company ─────────────────────
SELECT c.clientId, c.first_name, c.last_name, c.cellphone, c.clientType, c.created_At,
       MIN(i.companyId) AS newCompanyId, COUNT(*) AS sales
FROM dbo.clients c
JOIN dbo.income i ON i.clientId = c.clientId
WHERE c.companyId IS NULL
  AND c.clientId <> 1                       -- walk-in "mostrador" placeholder
GROUP BY c.clientId, c.first_name, c.last_name, c.cellphone, c.clientType, c.created_At
HAVING COUNT(DISTINCT i.companyId) = 1
ORDER BY c.clientId;
GO

-- ── 2. Apply ─────────────────────────────────────────────────────────────────
;WITH single AS (
    SELECT i.clientId, MIN(i.companyId) AS companyId
    FROM dbo.income i
    GROUP BY i.clientId
    HAVING COUNT(DISTINCT i.companyId) = 1
)
UPDATE c
   SET c.companyId  = s.companyId,
       c.updated_at = GETDATE()
FROM dbo.clients c
JOIN single s ON s.clientId = c.clientId
WHERE c.companyId IS NULL
  AND c.clientId <> 1;

SELECT @@ROWCOUNT AS clientsFixed;
GO

-- ── 3. Left alone: still NULL — decide these by hand ─────────────────────────
SELECT c.clientId, c.first_name, c.last_name, c.cellphone, c.clientType, c.created_At,
       COUNT(i.incomeId)          AS sales,
       COUNT(DISTINCT i.companyId) AS companies
FROM dbo.clients c
LEFT JOIN dbo.income i ON i.clientId = c.clientId
WHERE c.companyId IS NULL
  AND c.clientId <> 1
GROUP BY c.clientId, c.first_name, c.last_name, c.cellphone, c.clientType, c.created_At
ORDER BY c.created_At DESC;
GO

-- #############################################################################
-- [59/67] 2026-10-07_products_net_content_no_expire.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [59/67] 2026-10-07_products_net_content_no_expire.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Products: net content + unit of measure, and explicit "no expiration"
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB, BEFORE deploying the
-- frontend that sends netContent/unitOfMeasure/noExpire (old frontend is safe
-- against the new SP: missing keys keep current behavior except see NOTE).
--
-- WHY: products need their content (200 g, 1.5 L, 6 pz) and a way to say
-- "this product does not expire". Today an empty date was inserted as
-- 1900-01-01 (implicit '' -> DATE), and on update a null date was COALESCEd
-- to the old one, so an expiry date could never be removed.
--
-- WHAT:
--   * dbo.products: + netContent DECIMAL(10,3) NULL, + unitOfMeasure VARCHAR(10) NULL
--     (g | kg | ml | L | pz; existing rows NULL = not captured).
--   * dbo.products: + referencePrice DECIMAL(10,2) NULL — competitor/market shelf
--     price (e.g. OXXO), reference only for the 30% margin check in the wizard.
--   * sp_products_save: insert/update netContent + unitOfMeasure; '' date -> NULL;
--     products[].noExpire = true clears dateOfExpire on update.
--   * sp_products_all: also returns netContent, unitOfMeasure, referencePrice.
-- Bodies are the 2026-10-02b definitions (read live that day) with only those
-- lines changed. CREATE OR ALTER, so re-runnable.
-- NOTE: on update, netContent/unitOfMeasure/referencePrice are overwritten with whatever is
--   sent (absent = NULL). Only ProductWizard updates products today, and it always
--   sends both. Any other caller doing action=2 would clear them.
-- TODO (not visible from the repo, live def has drifted): sp_products_by_company
--   — the list the Products page loads — must also SELECT p.netContent,
--   p.unitOfMeasure, p.referencePrice, or edit mode won't show the saved unit (the fallback via
--   sp_products_all will).
-- ROLLBACK: 2026-10-07_products_net_content_no_expire_ROLLBACK.sql
-- =============================================================================

IF COL_LENGTH('dbo.products','netContent') IS NULL
    ALTER TABLE dbo.products ADD netContent DECIMAL(10,3) NULL;
GO
IF COL_LENGTH('dbo.products','unitOfMeasure') IS NULL
    ALTER TABLE dbo.products ADD unitOfMeasure VARCHAR(10) NULL;
GO
IF COL_LENGTH('dbo.products','referencePrice') IS NULL
    ALTER TABLE dbo.products ADD referencePrice DECIMAL(10,2) NULL;
GO
-- Optional cleanup: legacy "no date" rows stored as 1900-01-01
UPDATE dbo.products SET dateOfExpire = NULL WHERE dateOfExpire = '1900-01-01';
GO
-- [run-all] skipped once products.categoryId is renamed (superseded by 2026-10-15)
IF COL_LENGTH('dbo.products', 'categoryId') IS NOT NULL
    EXEC (N'CREATE OR ALTER PROC [dbo].[sp_products_save]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = ''{"result":[{ "value":"", "msg":"", "error":"" }]}'',
        @Error NVARCHAR(500) = '''',
        @action INT,
        @companyId INT,
        @productId INT;

    BEGIN TRY
        -- 1. Extract Root Context
        SELECT TOP (1)
            @action = TRY_CAST(JSON_VALUE(value, ''$.action'') AS INT),
            @companyId = TRY_CAST(JSON_VALUE(value, ''$.companyId'') AS INT),
            @productId = TRY_CAST(JSON_VALUE(value, ''$.productId'') AS INT)
        FROM OPENJSON(@pjsonfile, ''$.products'');

        -- Validations
        IF @action IS NULL RAISERROR(''action is required (1=insert, 2=update, 3=delete).'', 16, 1);
        IF @companyId IS NULL RAISERROR(''companyId is required.'', 16, 1);
        IF @companyId <> 1 RAISERROR(''Invalid companyId.'', 16, 1);

        BEGIN TRANSACTION;

        /* ============================================================
           STEP 1: BASE PRODUCTS
           ============================================================ */
        IF @action = 1
        BEGIN
            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, categoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice)
            SELECT 
                JSON_VALUE(value, ''$.name''), JSON_VALUE(value, ''$.barCode''), JSON_VALUE(value, ''$.code''),
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, ''$.dateOfExpire''), '''')), TRY_CAST(JSON_VALUE(value, ''$.productFormId'') AS INT),
                TRY_CAST(JSON_VALUE(value, ''$.manufactureId'') AS INT), JSON_VALUE(value, ''$.description''),
                GETDATE(), TRY_CAST(JSON_VALUE(value, ''$.categoryId'') AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, ''$.isSupply'') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, ''$.netContent'') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, ''$.unitOfMeasure''), ''''),
                TRY_CAST(JSON_VALUE(value, ''$.referencePrice'') AS DECIMAL(10,2))
            FROM OPENJSON(@pjsonfile, ''$.products'');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR(''productId is required for update.'', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, ''$.name''), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, ''$.barCode''), p.barCode),
                p.code = COALESCE(JSON_VALUE(j.value, ''$.code''), p.code),
                p.dateOfExpire = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, ''$.noExpire'') AS BIT) = 1 THEN NULL
                    ELSE COALESCE(TRY_CONVERT(DATE, NULLIF(JSON_VALUE(j.value, ''$.dateOfExpire''), '''')), p.dateOfExpire)
                END,
                -- netContent/unitOfMeasure/referencePrice: the wizard always sends all three (null = cleared)
                p.netContent = TRY_CAST(JSON_VALUE(j.value, ''$.netContent'') AS DECIMAL(10,3)),
                p.unitOfMeasure = NULLIF(JSON_VALUE(j.value, ''$.unitOfMeasure''), ''''),
                p.referencePrice = TRY_CAST(JSON_VALUE(j.value, ''$.referencePrice'') AS DECIMAL(10,2)),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.productFormId'') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.manufactureId'') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, ''$.description''), p.description),
                p.updatedAt = GETDATE(),
                p.categoryId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.categoryId'') AS INT), p.categoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.isSupply'') AS BIT), p.isSupply)
            FROM dbo.products p
            CROSS APPLY OPENJSON(@pjsonfile, ''$.products'') j
            WHERE p.productId = @productId AND p.companyId = @companyId;
        END
        ELSE IF @action = 3
        BEGIN
            -- Clean up everything associated with this product (Cascade Delete)
            DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
            DELETE FROM dbo.productOptions WHERE productId = @productId;
            DELETE FROM dbo.productDetails WHERE productId = @productId;
            IF OBJECT_ID(''dbo.productsDescription'', ''U'') IS NOT NULL DELETE FROM dbo.productsDescription WHERE productId = @productId;
            DELETE FROM dbo.products WHERE productId = @productId AND companyId = @companyId;

            COMMIT TRANSACTION;
            
            -- Early return on successful delete
            SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].value'', CAST(@productId AS NVARCHAR(50))), ''$.result[0].msg'', ''Deleted Successfully'');
            SELECT JSON_VALUE(value, ''$.value'') AS [value], JSON_VALUE(value, ''$.msg'') AS [msg], JSON_VALUE(value, ''$.error'') AS [error] FROM OPENJSON(@Outputmessage, ''$.result'');
            RETURN;
        END

        /* ============================================================
           STEP 2: PRODUCT DETAILS (Simple IF EXISTS Check)
           ============================================================ */
        DECLARE @stock INT, @uPrice DECIMAL(10,2), @sPrice DECIMAL(10,2);
        
        SELECT 
            @stock = TRY_CAST(JSON_VALUE(value, ''$.stockQuantity'') AS INT),
            @uPrice = TRY_CAST(JSON_VALUE(value, ''$.unitPrice'') AS DECIMAL(10,2)),
            @sPrice = TRY_CAST(JSON_VALUE(value, ''$.salePrice'') AS DECIMAL(10,2))
        FROM OPENJSON(@pjsonfile, ''$.productDetails'');

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
        IF OBJECT_ID(''dbo.productsDescription'', ''U'') IS NOT NULL
        BEGIN
            DELETE FROM dbo.productsDescription WHERE productId = @productId;

            INSERT INTO dbo.productsDescription (productId, Dosage, measurementId, is_principal, activeIngredientId)
            SELECT 
                @productId, JSON_VALUE(value, ''$.Dosage''), 
                TRY_CAST(JSON_VALUE(value, ''$.measurementId'') AS INT), 
                JSON_VALUE(value, ''$.is_principal''), 
                TRY_CAST(JSON_VALUE(value, ''$.activeIngredientId'') AS INT)
            FROM OPENJSON(@pjsonfile, ''$.productDescriptions'');
        END

        /* ============================================================
           STEP 4: OPTIONS AND CHOICES (Simple Loop/Insert Pattern)
           ============================================================ */
        -- Clear old configurations to avoid messy updates
        DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
        DELETE FROM dbo.productOptions WHERE productId = @productId;

        -- We use a cursor or simple loop over the array index to keep identities synchronized
        DECLARE @index INT = 0, @maxOptions INT;
        SET @maxOptions = (SELECT COUNT(*) FROM OPENJSON(@pjsonfile, ''$.productOptions''));

        WHILE @index < @maxOptions
        BEGIN
            DECLARE @optPath NVARCHAR(100) = ''$.productOptions['' + CAST(@index AS NVARCHAR(10)) + '']'';
            DECLARE @newOptId INT;

            -- Insert the Option Node
            INSERT INTO dbo.productOptions (productId, optionKey, name, type, createdAt, updatedAt)
            SELECT @productId, JSON_VALUE(@pjsonfile, @optPath + ''.optionKey''), JSON_VALUE(@pjsonfile, @optPath + ''.name''), JSON_VALUE(@pjsonfile, @optPath + ''.type''), GETDATE(), GETDATE();
            
            SET @newOptId = SCOPE_IDENTITY();

            -- Insert Nested Choices matching this exact option index
            INSERT INTO dbo.productOptionChoices (productOptionId, choiceKey, name, price, description, createdAt, updatedAt)
            SELECT 
                @newOptId,
                JSON_VALUE(value, ''$.choiceKey''),
                JSON_VALUE(value, ''$.name''),
                COALESCE(TRY_CAST(JSON_VALUE(value, ''$.price'') AS DECIMAL(10,2)), 0.00),
                COALESCE(JSON_VALUE(value, ''$.description''), ''''),
                GETDATE(),
                GETDATE()
            FROM OPENJSON(@pjsonfile, @optPath + ''.optionChoices'');

            SET @index = @index + 1;
        END

        COMMIT TRANSACTION;

        -- Success Output Compilation
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].value'', CAST(@productId AS NVARCHAR(50))), ''$.result[0].msg'', CASE WHEN @action = 1 THEN ''Inserted Successfully'' ELSE ''Updated Successfully'' END);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].error'', ''1''), ''$.result[0].msg'', @Error);
    END CATCH;

    -- Return Status Response
    SELECT JSON_VALUE(value, ''$.value'') AS [value], JSON_VALUE(value, ''$.msg'') AS [msg], JSON_VALUE(value, ''$.error'') AS [error] FROM OPENJSON(@Outputmessage, ''$.result'');
END');
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
        ,netContent
        ,unitOfMeasure
        ,referencePrice
    FROM [montanogilberto_smartloans].[dbo].[products]
    FOR JSON AUTO, ROOT('products');

END
GO


-- #############################################################################
-- [60/67] 2026-10-11_products_auto_code.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [60/67] 2026-10-11_products_auto_code.sql', 0, 1) WITH NOWAIT;
GO

-- [run-all] skipped once products.categoryId is renamed (superseded by 2026-10-15)
IF COL_LENGTH('dbo.products', 'categoryId') IS NOT NULL
    EXEC (N'-- =============================================================================
-- Products: auto-assigned product code (next = MAX numeric code + 1)
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-07_products_net_content_no_expire.sql, and BEFORE deploying the
-- frontend that no longer asks for "Código" (it sends code '''' on create).
--
-- WHY: "Código" was typed by hand (duplicates, "1", "PROD001"…). It must behave
-- like an identity: the next number after the highest one in dbo.products.
--
-- WHAT (sp_products_save only):
--   * action 1: code = MAX(TRY_CAST(code AS BIGINT)) + 1 for the company,
--     ignoring whatever the client sends. Non-numeric legacy codes are skipped
--     by TRY_CAST; first product of a company gets 1.
--   * action 2: code is no longer updatable.
-- Scope: per companyId (each company has its own sequence).
-- Body is the 2026-10-07 definition with only those lines changed.
-- Product images: NOT here — new table dbo.productImages via the factory
-- (posgmo-factory/tests/prd_productImage.json).
-- ROLLBACK: 2026-10-11_products_auto_code_ROLLBACK.sql
-- =============================================================================

CREATE OR ALTER PROC [dbo].[sp_products_save]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = ''{"result":[{ "value":"", "msg":"", "error":"" }]}'',
        @Error NVARCHAR(500) = '''',
        @action INT,
        @companyId INT,
        @productId INT;

    BEGIN TRY
        -- 1. Extract Root Context
        SELECT TOP (1)
            @action = TRY_CAST(JSON_VALUE(value, ''$.action'') AS INT),
            @companyId = TRY_CAST(JSON_VALUE(value, ''$.companyId'') AS INT),
            @productId = TRY_CAST(JSON_VALUE(value, ''$.productId'') AS INT)
        FROM OPENJSON(@pjsonfile, ''$.products'');

        -- Validations
        IF @action IS NULL RAISERROR(''action is required (1=insert, 2=update, 3=delete).'', 16, 1);
        IF @companyId IS NULL RAISERROR(''companyId is required.'', 16, 1);
        IF @companyId <> 1 RAISERROR(''Invalid companyId.'', 16, 1);

        BEGIN TRANSACTION;

        /* ============================================================
           STEP 1: BASE PRODUCTS
           ============================================================ */
        IF @action = 1
        BEGIN
            -- Code is an identity-like counter per company: MAX(numeric code) + 1,
            -- never typed by the user. UPDLOCK+HOLDLOCK keeps two concurrent
            -- inserts from reading the same MAX (we are inside the transaction).
            DECLARE @nextCode VARCHAR(100) = CAST(
                ISNULL((SELECT MAX(TRY_CAST(code AS BIGINT))
                        FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
                        WHERE companyId = @companyId), 0) + 1 AS VARCHAR(100));

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, categoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice)
            SELECT 
                JSON_VALUE(value, ''$.name''), JSON_VALUE(value, ''$.barCode''), @nextCode,
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, ''$.dateOfExpire''), '''')), TRY_CAST(JSON_VALUE(value, ''$.productFormId'') AS INT),
                TRY_CAST(JSON_VALUE(value, ''$.manufactureId'') AS INT), JSON_VALUE(value, ''$.description''),
                GETDATE(), TRY_CAST(JSON_VALUE(value, ''$.categoryId'') AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, ''$.isSupply'') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, ''$.netContent'') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, ''$.unitOfMeasure''), ''''),
                TRY_CAST(JSON_VALUE(value, ''$.referencePrice'') AS DECIMAL(10,2))
            FROM OPENJSON(@pjsonfile, ''$.products'');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR(''productId is required for update.'', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, ''$.name''), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, ''$.barCode''), p.barCode),
                -- code is never changed after insert (auto-assigned identity)
                p.dateOfExpire = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, ''$.noExpire'') AS BIT) = 1 THEN NULL
                    ELSE COALESCE(TRY_CONVERT(DATE, NULLIF(JSON_VALUE(j.value, ''$.dateOfExpire''), '''')), p.dateOfExpire)
                END,
                -- netContent/unitOfMeasure/referencePrice: the wizard always sends all three (null = cleared)
                p.netContent = TRY_CAST(JSON_VALUE(j.value, ''$.netContent'') AS DECIMAL(10,3)),
                p.unitOfMeasure = NULLIF(JSON_VALUE(j.value, ''$.unitOfMeasure''), ''''),
                p.referencePrice = TRY_CAST(JSON_VALUE(j.value, ''$.referencePrice'') AS DECIMAL(10,2)),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.productFormId'') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.manufactureId'') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, ''$.description''), p.description),
                p.updatedAt = GETDATE(),
                p.categoryId = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.categoryId'') AS INT), p.categoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, ''$.isSupply'') AS BIT), p.isSupply)
            FROM dbo.products p
            CROSS APPLY OPENJSON(@pjsonfile, ''$.products'') j
            WHERE p.productId = @productId AND p.companyId = @companyId;
        END
        ELSE IF @action = 3
        BEGIN
            -- Clean up everything associated with this product (Cascade Delete)
            DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
            DELETE FROM dbo.productOptions WHERE productId = @productId;
            DELETE FROM dbo.productDetails WHERE productId = @productId;
            IF OBJECT_ID(''dbo.productsDescription'', ''U'') IS NOT NULL DELETE FROM dbo.productsDescription WHERE productId = @productId;
            DELETE FROM dbo.products WHERE productId = @productId AND companyId = @companyId;

            COMMIT TRANSACTION;
            
            -- Early return on successful delete
            SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].value'', CAST(@productId AS NVARCHAR(50))), ''$.result[0].msg'', ''Deleted Successfully'');
            SELECT JSON_VALUE(value, ''$.value'') AS [value], JSON_VALUE(value, ''$.msg'') AS [msg], JSON_VALUE(value, ''$.error'') AS [error] FROM OPENJSON(@Outputmessage, ''$.result'');
            RETURN;
        END

        /* ============================================================
           STEP 2: PRODUCT DETAILS (Simple IF EXISTS Check)
           ============================================================ */
        DECLARE @stock INT, @uPrice DECIMAL(10,2), @sPrice DECIMAL(10,2);
        
        SELECT 
            @stock = TRY_CAST(JSON_VALUE(value, ''$.stockQuantity'') AS INT),
            @uPrice = TRY_CAST(JSON_VALUE(value, ''$.unitPrice'') AS DECIMAL(10,2)),
            @sPrice = TRY_CAST(JSON_VALUE(value, ''$.salePrice'') AS DECIMAL(10,2))
        FROM OPENJSON(@pjsonfile, ''$.productDetails'');

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
        IF OBJECT_ID(''dbo.productsDescription'', ''U'') IS NOT NULL
        BEGIN
            DELETE FROM dbo.productsDescription WHERE productId = @productId;

            INSERT INTO dbo.productsDescription (productId, Dosage, measurementId, is_principal, activeIngredientId)
            SELECT 
                @productId, JSON_VALUE(value, ''$.Dosage''), 
                TRY_CAST(JSON_VALUE(value, ''$.measurementId'') AS INT), 
                JSON_VALUE(value, ''$.is_principal''), 
                TRY_CAST(JSON_VALUE(value, ''$.activeIngredientId'') AS INT)
            FROM OPENJSON(@pjsonfile, ''$.productDescriptions'');
        END

        /* ============================================================
           STEP 4: OPTIONS AND CHOICES (Simple Loop/Insert Pattern)
           ============================================================ */
        -- Clear old configurations to avoid messy updates
        DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
        DELETE FROM dbo.productOptions WHERE productId = @productId;

        -- We use a cursor or simple loop over the array index to keep identities synchronized
        DECLARE @index INT = 0, @maxOptions INT;
        SET @maxOptions = (SELECT COUNT(*) FROM OPENJSON(@pjsonfile, ''$.productOptions''));

        WHILE @index < @maxOptions
        BEGIN
            DECLARE @optPath NVARCHAR(100) = ''$.productOptions['' + CAST(@index AS NVARCHAR(10)) + '']'';
            DECLARE @newOptId INT;

            -- Insert the Option Node
            INSERT INTO dbo.productOptions (productId, optionKey, name, type, createdAt, updatedAt)
            SELECT @productId, JSON_VALUE(@pjsonfile, @optPath + ''.optionKey''), JSON_VALUE(@pjsonfile, @optPath + ''.name''), JSON_VALUE(@pjsonfile, @optPath + ''.type''), GETDATE(), GETDATE();
            
            SET @newOptId = SCOPE_IDENTITY();

            -- Insert Nested Choices matching this exact option index
            INSERT INTO dbo.productOptionChoices (productOptionId, choiceKey, name, price, description, createdAt, updatedAt)
            SELECT 
                @newOptId,
                JSON_VALUE(value, ''$.choiceKey''),
                JSON_VALUE(value, ''$.name''),
                COALESCE(TRY_CAST(JSON_VALUE(value, ''$.price'') AS DECIMAL(10,2)), 0.00),
                COALESCE(JSON_VALUE(value, ''$.description''), ''''),
                GETDATE(),
                GETDATE()
            FROM OPENJSON(@pjsonfile, @optPath + ''.optionChoices'');

            SET @index = @index + 1;
        END

        COMMIT TRANSACTION;

        -- Success Output Compilation
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].value'', CAST(@productId AS NVARCHAR(50))), ''$.result[0].msg'', CASE WHEN @action = 1 THEN ''Inserted Successfully'' ELSE ''Updated Successfully'' END);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, ''$.result[0].error'', ''1''), ''$.result[0].msg'', @Error);
    END CATCH;

    -- Return Status Response
    SELECT JSON_VALUE(value, ''$.value'') AS [value], JSON_VALUE(value, ''$.msg'') AS [msg], JSON_VALUE(value, ''$.error'') AS [error] FROM OPENJSON(@Outputmessage, ''$.result'');
END');
GO


-- #############################################################################
-- [61/67] 2026-10-11b_products_by_company_all_products.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [61/67] 2026-10-11b_products_by_company_all_products.sql', 0, 1) WITH NOWAIT;
GO

-- [run-all] skipped once products.categoryId is renamed (superseded by 2026-10-15)
IF COL_LENGTH('dbo.products', 'categoryId') IS NOT NULL
    EXEC (N'-- =============================================================================
-- sp_products_by_company: list every sellable product (not only ones with
-- options) and return the fields the product wizard edits
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-07_products_net_content_no_expire.sql (needs netContent /
-- unitOfMeasure / referencePrice) and 2026-10-11_products_auto_code.sql.
--
-- WHY:
--   1. The WHERE EXISTS(productOptions) filter hid every product without
--      options. Drinks/snacks are now plain products (barcode, stock, price),
--      so a new "Electrolit 1000 ml" saved fine but never appeared in the POS
--      menu nor in the admin Products page (both read this SP).
--      Supplies (isSupply=1) relied on that filter to stay out of the POS
--      menu — they are now excluded explicitly instead.
--   2. "Ver/Editar producto" showed precio $0, no code, no barcode: the wizard
--      reads details[0].salePrice/unitPrice/stockQuantity, code, barCode,
--      dateOfExpire, category, descriptions — this SP only returned `price`.
--
-- WHAT: same output shape as before (id, name, description, price, image,
-- categoryId, options[] with choices[]) — the POS menu keeps working — plus:
--   productId, code, barCode, dateOfExpire, netContent, unitOfMeasure,
--   referencePrice, companyId, details[] {productDetailId, stockQuantity,
--   unitPrice, salePrice}, category {productCategoryId, name},
--   descriptions[] {productDescriptionId, Dosage, measurementId, is_principal,
--   activeIngredientId}.
--   Filter: companyId + ISNULL(isSupply,0)=0. productDetails is now LEFT JOIN
--   (a product without a details row shows at price 0 instead of vanishing).
-- Base: live definition pasted by the user 2026-10-11 (identical to the repo copy).
-- ROLLBACK: 2026-10-11b_products_by_company_all_products_ROLLBACK.sql
-- =============================================================================

CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = ''{ "products": [ { "companyId": "1" } ] }''
    */

    DECLARE @companyId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, ''$.companyId'')
         FROM OPENJSON(@pjsonfile, ''$.products'')) AS INT
    );

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.categoryId,
        ISNULL(p.code, '''') AS code,
        ISNULL(p.barCode, '''') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        (
            SELECT d.productDetailId, d.stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name
            FROM productCategories c
            WHERE c.productCategoryId = p.categoryId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS category,
        (
            SELECT ds.productDescriptionId, ds.Dosage, ds.measurementId, ds.is_principal, ds.activeIngredientId
            FROM productsDescription ds
            WHERE ds.productId = p.productId
            FOR JSON PATH
        ) AS descriptions,
        (
            SELECT
                o.productOptionId AS [productOptionId],
                o.name,
                o.type,
                (
                    SELECT
                        c.productOptionChoiceId AS [productOptionChoiceId],
                        c.name,
                        c.price
                    FROM productOptionChoices c
                    WHERE c.productOptionId = o.productOptionId
                    FOR JSON PATH
                ) AS choices
            FROM productOptions o
            WHERE o.productId = p.productId
            FOR JSON PATH
        ) AS options
    FROM products p
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
    ORDER BY p.name
    FOR JSON PATH, ROOT(''products'');
END');
GO


-- #############################################################################
-- [62/67] 2026-10-15_products_productCategoryId.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [62/67] 2026-10-15_products_productCategoryId.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- products.categoryId  ->  products.productCategoryId  (+ FK to productCategories)
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-07_products_net_content_no_expire.sql, 2026-10-11_products_auto_code.sql
-- and 2026-10-11b_products_by_company_all_products.sql (this script redeploys
-- sp_products_save / sp_products_by_company from those versions).
--
-- WHY: products.categoryId always held dbo.productCategories.productCategoryId
--   (1002 Lavanderia, 1004 Productos, 1..6 Percherones..Bebidas, 2005 Piezas),
--   but the name suggested the legacy dbo.categories table (pharmacy ids 1..7),
--   whose ids only collide by accident. No FK enforced either relationship.
--   Verified against live 2026-10-15: every products.categoryId exists in
--   productCategories (0 orphans).
--
-- WHAT:
--   1. Abort if any products row points to a missing productCategoryId.
--   2. Rename column categoryId -> productCategoryId, add
--      FK_products_productCategories (WITH CHECK) and an index on it.
--   3. Redeploy every SP that read/wrote products.categoryId.
--      API contract unchanged: outputs still expose the key "categoryId";
--      inputs accept "productCategoryId" and fall back to "categoryId".
--   4. Final check: lists any other module still mentioning categoryId on
--      products (should return 0 rows).
-- ROLLBACK: 2026-10-15_products_productCategoryId_ROLLBACK.sql
-- =============================================================================

-- 1) Pre-check -----------------------------------------------------------------
-- Dynamic SQL: once the column is renamed, a static "p.categoryId" fails to compile
-- (Msg 207) even inside a false IF, so re-running this file would error here.
IF COL_LENGTH('dbo.products', 'categoryId') IS NOT NULL
BEGIN
    DECLARE @orphans INT;
    EXEC sp_executesql N'
        SELECT @n = COUNT(*)
        FROM dbo.products p
        WHERE p.categoryId IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM dbo.productCategories pc
                          WHERE pc.productCategoryId = p.categoryId);',
        N'@n INT OUTPUT', @n = @orphans OUTPUT;

    IF @orphans > 0
    BEGIN RAISERROR('products.categoryId has values missing in productCategories. Fix them before running this migration.', 16, 1); SET NOEXEC ON; RETURN; END
END
GO

-- 2) Rename + FK + index ---------------------------------------------------------
-- Each piece is its own batch, and the FK/index go through dynamic SQL: in one
-- batch SQL Server binds "productCategoryId" before sp_rename has run, the
-- batch fails and (with XACT_ABORT) the rename is rolled back with it.

-- 2a) Rename
IF COL_LENGTH('dbo.products', 'categoryId') IS NOT NULL
   AND COL_LENGTH('dbo.products', 'productCategoryId') IS NULL
BEGIN
    -- sp_rename refuses columns used by schema-bound views/functions or computed columns.
    IF EXISTS (
        SELECT 1 FROM sys.sql_expression_dependencies d
        WHERE d.referenced_id = OBJECT_ID('dbo.products')
          AND d.referenced_minor_id = COLUMNPROPERTY(OBJECT_ID('dbo.products'), 'categoryId', 'ColumnId')
          AND d.is_schema_bound_reference = 1)
    BEGIN
        SELECT OBJECT_SCHEMA_NAME(d.referencing_id) + '.' + OBJECT_NAME(d.referencing_id) AS schemaBoundObject
        FROM sys.sql_expression_dependencies d
        WHERE d.referenced_id = OBJECT_ID('dbo.products')
          AND d.referenced_minor_id = COLUMNPROPERTY(OBJECT_ID('dbo.products'), 'categoryId', 'ColumnId')
          AND d.is_schema_bound_reference = 1;
        BEGIN RAISERROR('products.categoryId is used by a schema-bound object (listed above). Drop/alter it first.', 16, 1); SET NOEXEC ON; RETURN; END
    END

    EXEC sp_rename N'dbo.products.categoryId', N'productCategoryId', N'COLUMN';
END

IF COL_LENGTH('dbo.products', 'productCategoryId') IS NULL
    BEGIN RAISERROR('products.productCategoryId still missing after rename — see the error above.', 16, 1); SET NOEXEC ON; RETURN; END

RAISERROR('OK: dbo.products.productCategoryId exists.', 0, 1) WITH NOWAIT;
GO

-- 2b) Foreign key
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_products_productCategories')
    EXEC (N'ALTER TABLE dbo.products WITH CHECK
            ADD CONSTRAINT FK_products_productCategories
            FOREIGN KEY (productCategoryId) REFERENCES dbo.productCategories (productCategoryId);');
RAISERROR('OK: FK_products_productCategories exists.', 0, 1) WITH NOWAIT;
GO

-- 2c) Index
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_products_productCategoryId'
               AND object_id = OBJECT_ID('dbo.products'))
    EXEC (N'CREATE NONCLUSTERED INDEX IX_products_productCategoryId ON dbo.products (productCategoryId);');
RAISERROR('OK: IX_products_productCategoryId exists.', 0, 1) WITH NOWAIT;
GO

-- 3) Stored procedures -----------------------------------------------------------

-- dbo.one_products
CREATE OR ALTER PROC dbo.one_products
    @productId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.productId,
        p.name,
        ISNULL(p.barCode, '') AS barCode,
        ISNULL(p.code, '') AS code,
        CONVERT(varchar(10), p.dateOfExpire, 23) AS dateOfExpire, -- yyyy-mm-dd
        ISNULL(p.productFormId, 0) AS productFormId,
        ISNULL(p.manufactureId, 0) AS manufactureId,
        ISNULL(p.description, '') AS description,
        p.productCategoryId AS categoryId,
        p.companyId,
        p.createdAt,
        p.updatedAt,

        -- productDetails (array)
        JSON_QUERY(
            ISNULL((
                SELECT
                    pd.stockQuantity,
                    pd.unitPrice,
                    pd.salePrice
                FROM dbo.product_details pd
                WHERE pd.productId = p.productId
                FOR JSON PATH
            ), '[]')
        ) AS productDetails,

        -- productOptions (array), each with optionChoices (array)
        JSON_QUERY(
            ISNULL((
                SELECT
                    po.optionKey,
                    po.name,
                    po.[type],

                    JSON_QUERY(
                        ISNULL((
                            SELECT
                                poc.choiceKey,
                                poc.name,
                                poc.price,
                                ISNULL(poc.description, '') AS description
                            FROM dbo.product_option_choices poc
                            WHERE poc.productOptionId = po.productOptionId
                            ORDER BY poc.productOptionChoiceId
                            FOR JSON PATH
                        ), '[]')
                    ) AS optionChoices

                FROM dbo.product_options po
                WHERE po.productId = p.productId
                ORDER BY po.productOptionId
                FOR JSON PATH
            ), '[]')
        ) AS productOptions

    FROM dbo.products p
    WHERE p.productId = @productId
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_inventory_list
CREATE OR ALTER PROC dbo.sp_inventory_list
(
    @companyId INT
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.productId,
        p.name AS productName,

        ISNULL(s.stockQuantity, 0) AS stockQuantity,
        ISNULL(s.minStockQty, 0)   AS minStockQty,

        pd.unitPrice,
        pd.salePrice,

        p.barCode,
        p.code,
        p.productCategoryId AS categoryId
    FROM dbo.products p
    LEFT JOIN dbo.productDetails pd
        ON pd.productId = p.productId
    LEFT JOIN dbo.inventoryStock s
        ON s.companyId = @companyId
       AND s.productId = p.productId
    WHERE p.companyId = @companyId
    ORDER BY p.name
    FOR JSON PATH, ROOT('result');
END
GO

-- dbo.sp_orders_all
CREATE OR ALTER PROC [dbo].[sp_orders_all]
AS
BEGIN
    SET NOCOUNT ON;

        SELECT
        o_main.orderId,
        o_main.clientId,
        o_main.total,
        o_main.paymentMethod,
        o_main.comments,
        o_main.createdAt,
        (
            SELECT 
                p.productId AS [id],
                p.name,
                p.description,
                --pd.saleprice AS price,
                NULL AS [image],
                p.productCategoryId AS categoryId,
                (
                    SELECT 
                        po.productOptionId AS [id],
                        po.name,
                        po.type,
                        (
                            SELECT 
                                poc.choiceKey AS [id],
                                poc.name,
                                poc.price
                            FROM productOptionChoices poc
                            WHERE poc.productOptionId = po.productOptionId
                            FOR JSON PATH
                        ) AS choices
                    FROM productOptions po
                    WHERE po.productId = p.productId
                    FOR JSON PATH
                ) AS options
            FROM orders o
            INNER JOIN products p ON o.productId = p.productId
            LEFT JOIN productsDescription pd ON pd.productId = p.productId
            WHERE o.orderId = o_main.orderId
            GROUP BY p.productId, p.name, p.description,  p.productCategoryId
            FOR JSON PATH
        ) AS products_food
    FROM orders o_main
    GROUP BY o_main.orderId, o_main.clientId, o_main.total, o_main.paymentMethod, o_main.comments, o_main.createdAt
    FOR JSON PATH;


END
GO

-- dbo.sp_orders_one
CREATE OR ALTER PROC [dbo].[sp_orders_one] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /* 
    DECLARE @pjsonfile NVARCHAR(MAX) = N'{
      "orders": [
        {
          "orderId": 1
        }
      ]
    }'
   */

    DECLARE @OutputMessage NVARCHAR(MAX) = '{
    "result": [
        { "value": "", "msg": "", "error": "" }
    ]
    }',
    @orderId INT;

    -- Extract orderId from JSON input
    SET @orderId = CAST((
        SELECT JSON_VALUE(value, '$.orderId') 
        FROM OPENJSON(@pjsonfile, '$.orders')
    ) AS INT);

    SELECT
        o_main.orderId,
        o_main.clientId,
        o_main.total,
        o_main.paymentMethod,
        o_main.comments,
        o_main.createdAt,
        (
            SELECT 
                p.productId AS [id],
                p.name,
                p.description,
                --pd.saleprice AS price,
                NULL AS [image],
                p.productCategoryId AS categoryId,
                (
                    SELECT 
                        po.productOptionId AS [id],
                        po.name,
                        po.type,
                        (
                            SELECT 
                                poc.choiceKey AS [id],
                                poc.name,
                                poc.price
                            FROM productOptionChoices poc
                            WHERE poc.productOptionId = po.productOptionId
                            FOR JSON PATH
                        ) AS choices
                    FROM productOptions po
                    WHERE po.productId = p.productId
                    FOR JSON PATH
                ) AS options
            FROM orders o
            INNER JOIN products p ON o.productId = p.productId
            LEFT JOIN productsDescription pd ON pd.productId = p.productId
            WHERE o.orderId = o_main.orderId
            GROUP BY p.productId, p.name, p.description,  p.productCategoryId
            FOR JSON PATH
        ) AS products_food
    FROM orders o_main
    WHERE o_main.orderId = @orderId
    GROUP BY o_main.orderId, o_main.clientId, o_main.total, o_main.paymentMethod, o_main.comments, o_main.createdAt
    FOR JSON PATH;



END
GO

-- dbo.sp_products
CREATE OR ALTER PROC [dbo].[sp_products] (@pjsonfile VARCHAR(MAX))
-- INSERT --> 1
-- UPDATE --> 2
-- DELETE --> 3
AS
SET NOCOUNT ON;

/*
DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
            "productId": 1,
            "name": "exaliv",
            "barCode": "",
            "code": "",
            "dateOfExpire": "2024-03-12",
            "productFormId": 1,
            "manufactureId": 1,
            "description": "",
            "createdAt": "2024-03-12T20:31:06.490",
            "updatedAt": "1900-01-01T00:00:00",
            "companyId": 1,
            "action": 1
            
        }
    ]
}'
*/

DECLARE @Outputmessage NVARCHAR(MAX) = '
{
  "result": [
  {
     "value": "",
     "msg": "",
     "error": ""
   }
  ]
}',
@Error NVARCHAR(500) = '',
@action INT,
@product_id INT,
@companyId INT;

BEGIN
    -- Read action and companyId from the JSON payload
    SET @action = (
        SELECT TOP 1 JSON_VALUE(value, '$.action')
        FROM OPENJSON(@pjsonfile, '$.products')
    );

    SET @companyId = (
        SELECT TOP 1 TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.products')
    );

    BEGIN TRY
        -- Validate companyId is present and equals 1
        IF @companyId IS NULL
        BEGIN
            RAISERROR('companyId is required.', 16, 1);
        END;

        IF @companyId <> 1
        BEGIN
            RAISERROR('Invalid companyId. ', 16, 1);
        END;

        -- Validate company exists
        IF NOT EXISTS (SELECT 1 FROM [dbo].[companies] WHERE [companyId] = @companyId)
        BEGIN
            RAISERROR('The specified companyId does not exist.', 16, 1);
        END;

        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- INSERT (scoped to companyId)
            INSERT INTO [dbo].[products] (
                [name],
                [barCode],
                [code],
                [dateOfExpire],
                [productFormId],
                [manufactureId],
                [description],
                [createdAt],
                [updatedAt],
                [productCategoryId],
                [companyId]
            )
            SELECT
                JSON_VALUE(value, '$.name'),
                JSON_VALUE(value, '$.barCode'),
                JSON_VALUE(value, '$.code'),
                JSON_VALUE(value, '$.dateOfExpire'),
                JSON_VALUE(value, '$.productFormId'),
                JSON_VALUE(value, '$.manufactureId'),
                JSON_VALUE(value, '$.description'),
                GETDATE(),
                NULL,
                TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'), JSON_VALUE(value, '$.categoryId')) AS INT),
                @companyId
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @product_id = SCOPE_IDENTITY();
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@product_id AS NVARCHAR(50)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- UPDATE (only update rows that belong to companyId)
            UPDATE p
            SET 
                p.[name]          = JSON_VALUE(j.value, '$.name'),
                p.[barCode]       = JSON_VALUE(j.value, '$.barCode'),
                p.[code]          = JSON_VALUE(j.value, '$.code'),
                p.[dateOfExpire]  = JSON_VALUE(j.value, '$.dateOfExpire'),
                p.[productFormId] = JSON_VALUE(j.value, '$.productFormId'),
                p.[manufactureId] = JSON_VALUE(j.value, '$.manufactureId'),
                p.[description]   = JSON_VALUE(j.value, '$.description'),
                p.[createdAt]     = COALESCE(JSON_VALUE(j.value, '$.createdAt'), p.[createdAt]),
                p.[updatedAt]     = COALESCE(JSON_VALUE(j.value, '$.updatedAt'), GETDATE()),
                p.[productCategoryId] = COALESCE(TRY_CAST(COALESCE(JSON_VALUE(j.value, '$.productCategoryId'), JSON_VALUE(j.value, '$.categoryId')) AS INT), p.[productCategoryId]),
                p.[companyId]     = @companyId -- keep product scoped to this company
            FROM [dbo].[products] p
            INNER JOIN OPENJSON(@pjsonfile, '$.products') j
                ON p.[productId] = TRY_CAST(JSON_VALUE(j.value, '$.productId') AS INT)
               AND p.[companyId] = @companyId;  -- scope by company

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- DELETE (only delete rows that belong to companyId)
            DELETE p
            FROM [dbo].[products] p
            INNER JOIN OPENJSON(@pjsonfile, '$.products') j
                ON p.[productId] = TRY_CAST(JSON_VALUE(j.value, '$.productId') AS INT)
               AND p.[companyId] = @companyId; -- scope by company

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            RAISERROR('Invalid action. Use 1=INSERT, 2=UPDATE, 3=DELETE.', 16, 1);
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg')   AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_products_by_company
CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'
    */

    DECLARE @companyId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.productCategoryId AS categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        (
            SELECT d.productDetailId, d.stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name
            FROM productCategories c
            WHERE c.productCategoryId = p.productCategoryId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS category,
        (
            SELECT ds.productDescriptionId, ds.Dosage, ds.measurementId, ds.is_principal, ds.activeIngredientId
            FROM productsDescription ds
            WHERE ds.productId = p.productId
            FOR JSON PATH
        ) AS descriptions,
        (
            SELECT
                o.productOptionId AS [productOptionId],
                o.name,
                o.type,
                (
                    SELECT
                        c.productOptionChoiceId AS [productOptionChoiceId],
                        c.name,
                        c.price
                    FROM productOptionChoices c
                    WHERE c.productOptionId = o.productOptionId
                    FOR JSON PATH
                ) AS choices
            FROM productOptions o
            WHERE o.productId = p.productId
            FOR JSON PATH
        ) AS options
    FROM products p
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_products_food
CREATE OR ALTER PROC [dbo].[sp_products_food]
  @pjsonfile NVARCHAR(MAX) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @companyId INT = NULL;
  DECLARE @categoryId INT = NULL;

    /*
    @pjsonfile NVARCHAR(MAX) =  '{
    "products": [
        {
        "companyId": "1",
        "categoryId": "3"
        }
    ]
    }'
    */


  -- Extract companyId and categoryId from JSON
  IF @pjsonfile IS NOT NULL
  BEGIN
    SELECT TOP (1)
      @companyId = TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT),
      @categoryId = TRY_CAST(COALESCE(JSON_VALUE(j.value, '$.productCategoryId'), JSON_VALUE(j.value, '$.categoryId')) AS INT)
    FROM OPENJSON(@pjsonfile, '$.products') AS j;
  END

  SELECT
      p.productId AS [id],
      p.name,
      p.description,
      pd.saleprice AS price,
      NULL AS [image],
      p.productCategoryId AS categoryId,
      (
        SELECT
            o.productOptionId AS [id],
            o.name,
            o.type,
            (
              SELECT
                  c.productOptionChoiceId AS [id],
                  c.name,
                  c.price
              FROM dbo.productOptionChoices AS c
              WHERE c.productOptionId = o.productOptionId
              FOR JSON PATH
            ) AS choices
        FROM dbo.productOptions AS o
        WHERE o.productId = p.productId
        FOR JSON PATH
      ) AS options
  FROM dbo.products AS p
  INNER JOIN dbo.productdetails AS pd
          ON pd.productId = p.productId
  WHERE EXISTS (SELECT 1 FROM dbo.productOptions o WHERE o.productId = p.productId)
    --AND (@companyId IS NULL OR p.companyId = @companyId)
    AND (@categoryId IS NULL OR p.productCategoryId = @categoryId)
  FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_products_one
CREATE OR ALTER PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
        "productId": "1"
        }
     ]   
    }'
    */

    DECLARE @productId INT;

    -- Extracting ProductId safely
    SET @productId = TRY_CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

    -- Complete JSON structure generation matching the layout used by your application
    SELECT 
        p.[productId]
        ,p.[name]
        ,ISNULL(p.[barCode],'') AS barCode
        ,ISNULL(p.[code],'') AS code
        ,ISNULL(p.[dateOfExpire],'') AS dateOfExpire
        ,p.[productFormId]
        ,p.[manufactureId]
        ,ISNULL(p.[description],'') AS description
        ,p.[productCategoryId] AS categoryId
        ,p.[companyId]
        ,p.[createdAt]
        ,ISNULL(p.[updatedAt],'') AS updatedAt
        
        -- 1. Nested Details Object (Returns as an array/object matching your save logic)
        ,(
            SELECT 
                pd.stockQuantity
                ,pd.unitPrice
                ,pd.salePrice
            FROM dbo.productDetails pd
            WHERE pd.productId = p.productId
            FOR JSON PATH
        ) AS productDetails

        -- 2. Nested Descriptions Array
        ,(
            SELECT 
                pdesc.Dosage
                ,pdesc.measurementId
                ,pdesc.is_principal
                ,pdesc.activeIngredientId
            FROM dbo.productsDescription pdesc
            WHERE pdesc.productId = p.productId
            FOR JSON PATH
        ) AS productDescriptions

        -- 3. Nested Options and nested Choices Array
        ,(
            SELECT 
                po.optionKey
                ,po.name
                ,po.type
                ,(
                    SELECT 
                        poc.choiceKey
                        ,poc.name
                        ,poc.price
                        ,poc.description
                    FROM dbo.productOptionChoices poc
                    WHERE poc.productOptionId = po.productOptionId
                    FOR JSON PATH
                ) AS optionChoices
            FROM dbo.productOptions po
            WHERE po.productId = p.productId
            FOR JSON PATH
        ) AS productOptions

    FROM 
        [dbo].[products] p
    WHERE
        p.productId = @productId
    FOR JSON PATH, ROOT('products');

END
GO

-- dbo.sp_products_save
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
            -- Code is an identity-like counter per company: MAX(numeric code) + 1,
            -- never typed by the user. UPDLOCK+HOLDLOCK keeps two concurrent
            -- inserts from reading the same MAX (we are inside the transaction).
            DECLARE @nextCode VARCHAR(100) = CAST(
                ISNULL((SELECT MAX(TRY_CAST(code AS BIGINT))
                        FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
                        WHERE companyId = @companyId), 0) + 1 AS VARCHAR(100));

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, productCategoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice)
            SELECT 
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), @nextCode,
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, '$.dateOfExpire'), '')), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'), JSON_VALUE(value, '$.categoryId')) AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, '$.netContent') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, '$.unitOfMeasure'), ''),
                TRY_CAST(JSON_VALUE(value, '$.referencePrice') AS DECIMAL(10,2))
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR('productId is required for update.', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, '$.name'), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, '$.barCode'), p.barCode),
                -- code is never changed after insert (auto-assigned identity)
                p.dateOfExpire = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, '$.noExpire') AS BIT) = 1 THEN NULL
                    ELSE COALESCE(TRY_CONVERT(DATE, NULLIF(JSON_VALUE(j.value, '$.dateOfExpire'), '')), p.dateOfExpire)
                END,
                -- netContent/unitOfMeasure/referencePrice: the wizard always sends all three (null = cleared)
                p.netContent = TRY_CAST(JSON_VALUE(j.value, '$.netContent') AS DECIMAL(10,3)),
                p.unitOfMeasure = NULLIF(JSON_VALUE(j.value, '$.unitOfMeasure'), ''),
                p.referencePrice = TRY_CAST(JSON_VALUE(j.value, '$.referencePrice') AS DECIMAL(10,2)),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.productFormId') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.manufactureId') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, '$.description'), p.description),
                p.updatedAt = GETDATE(),
                p.productCategoryId = COALESCE(TRY_CAST(COALESCE(JSON_VALUE(j.value, '$.productCategoryId'), JSON_VALUE(j.value, '$.categoryId')) AS INT), p.productCategoryId),
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

-- 4) Verify: should return 0 rows ------------------------------------------------
-- Looks for the products alias "p" reading the old column (p.categoryId /
-- p.[categoryId]). Aliases like "productCategoryId AS categoryId" are fine.
SELECT OBJECT_SCHEMA_NAME(m.object_id) + '.' + OBJECT_NAME(m.object_id) AS module_name
FROM sys.sql_modules m
WHERE m.definition LIKE '%p.categoryId%'
   OR m.definition LIKE '%p.[[]categoryId]%';

-- Column check: expect productCategoryId = 1, categoryId = 0
SELECT CASE WHEN COL_LENGTH('dbo.products', 'productCategoryId') IS NOT NULL THEN 1 ELSE 0 END AS productCategoryId,
       CASE WHEN COL_LENGTH('dbo.products', 'categoryId')        IS NOT NULL THEN 1 ELSE 0 END AS categoryId;
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO

-- #############################################################################
-- [63/67] 2026-10-15b_products_by_company_category_filter.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [63/67] 2026-10-15b_products_by_company_category_filter.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- sp_products_by_company: filter by category again (optional categoryId)
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-15_products_productCategoryId.sql (uses products.productCategoryId).
--
-- WHY: /product/:categoryId (POS ProductListPage) sends
--   { companyId, categoryId } but the SP ignored categoryId (the filter was
--   commented out, and 2026-10-11b dropped it), so every category page listed
--   ALL of the company's products.
--
-- WHAT: reads optional "productCategoryId" (falls back to "categoryId");
--   when present (and not 0) adds  AND p.productCategoryId = @categoryId.
--   Callers that send only companyId (admin Products page, getProductsByCompany)
--   still get every product. Output shape unchanged.
-- ROLLBACK: 2026-10-15b_products_by_company_category_filter_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'                         -- all
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "categoryId": "1002" } ] }'  -- one category
    */

    DECLARE @companyId INT;
    DECLARE @categoryId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    -- Optional: productCategoryId (or legacy "categoryId"); missing/0 = all categories.
    SELECT TOP (1)
        @categoryId = NULLIF(TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'),
                                               JSON_VALUE(value, '$.categoryId')) AS INT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.productCategoryId AS categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        (
            SELECT d.productDetailId, d.stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name
            FROM productCategories c
            WHERE c.productCategoryId = p.productCategoryId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS category,
        (
            SELECT ds.productDescriptionId, ds.Dosage, ds.measurementId, ds.is_principal, ds.activeIngredientId
            FROM productsDescription ds
            WHERE ds.productId = p.productId
            FOR JSON PATH
        ) AS descriptions,
        (
            SELECT
                o.productOptionId AS [productOptionId],
                o.name,
                o.type,
                (
                    SELECT
                        c.productOptionChoiceId AS [productOptionChoiceId],
                        c.name,
                        c.price
                    FROM productOptionChoices c
                    WHERE c.productOptionId = o.productOptionId
                    FOR JSON PATH
                ) AS choices
            FROM productOptions o
            WHERE o.productId = p.productId
            FOR JSON PATH
        ) AS options
    FROM products p
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
      AND (@categoryId IS NULL OR p.productCategoryId = @categoryId)
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO

-- #############################################################################
-- [64/67] 2026-10-15c_inventory_single_source.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [64/67] 2026-10-15c_inventory_single_source.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Phase 1 — inventory: dbo.inventoryStock + dbo.inventoryMovements are the ONLY stock
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-15b_products_by_company_category_filter.sql (redeploys that SP) and
-- 2026-10-02b_expense_item_quantity_cost_supplies.sql (needs expenseDetails.quantity).
--
-- WHY: stock lived in two places that never agreed — productDetails.stockQuantity
--   (typed in the product wizard) and inventoryStock/inventoryMovements (a proper
--   ledger, but sp_inventory_adjust had no caller). Neither moved on a sale or a
--   purchase, so no stock number in the app was ever right.
--
-- WHAT:
--   1. products.trackInventory BIT (default 0). First run marks as tracked every
--      physical good: isSupply = 1, has a barcode, has productDetails stock <> 0,
--      or already has an inventoryStock row. Made-to-order food stays 0 (never
--      decremented). Flip it per product with sp_products_save "trackInventory".
--   2. Opening balance: tracked products without an inventoryStock row get one,
--      with the stock of their first productDetails row, plus an 'opening'
--      movement (refType 'productDetails'). Existing inventoryStock rows are kept.
--   3. dbo.sp_inventory_post — one movement + balance update, no result set.
--   4. Triggers post movements automatically, for every code path (sp_income,
--      sp_expense, cascaded deletes, future SPs):
--        incomeDetails  insert → 'sale' (−qty)      delete → 'sale_reversal' (+qty)
--        expenseDetails insert → 'purchase' (+qty)  delete → 'purchase_reversal' (−qty)
--      An edited line posts the difference. Reversals only happen for lines this
--      ledger posted, so deleting a sale made BEFORE this migration does not add
--      phantom stock. Untracked products are ignored. Stock may go negative (the
--      sale is never blocked); the negative number is the signal to recount.
--   5. sp_products_save: productDetails keeps prices only (its stockQuantity is
--      frozen); the stock typed in the wizard is posted as 'opening'/'adjustment'
--      for the difference. sp_products_by_company / sp_products_one read stock
--      from inventoryStock (same JSON shape + top-level stockQuantity, trackInventory).
--   6. Verify result sets.
-- ROLLBACK: 2026-10-15c_inventory_single_source_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 0) Pre-checks -------------------------------------------------------------------
IF OBJECT_ID('dbo.inventoryStock', 'U') IS NULL OR OBJECT_ID('dbo.inventoryMovements', 'U') IS NULL
    BEGIN RAISERROR('dbo.inventoryStock / dbo.inventoryMovements missing.', 16, 1); SET NOEXEC ON; RETURN; END
IF COL_LENGTH('dbo.expenseDetails', 'quantity') IS NULL
    BEGIN RAISERROR('expenseDetails.quantity missing — run 2026-10-02b_expense_item_quantity_cost_supplies.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
IF COL_LENGTH('dbo.products', 'productCategoryId') IS NULL
    BEGIN RAISERROR('products.productCategoryId missing — run 2026-10-15_products_productCategoryId.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
GO

-- 1) products.trackInventory (+ first-run backfill) -----------------------------------
IF COL_LENGTH('dbo.products', 'trackInventory') IS NULL
BEGIN
    ALTER TABLE dbo.products ADD trackInventory BIT NOT NULL
        CONSTRAINT DF_products_trackInventory DEFAULT (0);

    -- Dynamic SQL: the new column is only visible once the ALTER above has run.
    EXEC (N'
        UPDATE p SET trackInventory = 1
        FROM dbo.products p
        WHERE ISNULL(p.isSupply, 0) = 1
           OR NULLIF(LTRIM(RTRIM(p.barCode)), '''') IS NOT NULL
           OR EXISTS (SELECT 1 FROM dbo.productDetails d WHERE d.productId = p.productId AND d.stockQuantity <> 0)
           OR EXISTS (SELECT 1 FROM dbo.inventoryStock s WHERE s.productId = p.productId);');
END
RAISERROR('OK: products.trackInventory', 0, 1) WITH NOWAIT;
GO

-- Lookup used by the triggers ("did this ledger post that ticket line?")
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inventoryMovements_ref'
               AND object_id = OBJECT_ID('dbo.inventoryMovements'))
    CREATE NONCLUSTERED INDEX IX_inventoryMovements_ref
        ON dbo.inventoryMovements (refType, refId, productId);
GO

-- 2) Opening balances from productDetails --------------------------------------------
IF OBJECT_ID('tempdb..#opening') IS NOT NULL DROP TABLE #opening;

;WITH firstDetail AS (
    SELECT d.productId, d.productDetailId, d.stockQuantity,
           ROW_NUMBER() OVER (PARTITION BY d.productId ORDER BY d.productDetailId) AS rn
    FROM dbo.productDetails d
)
SELECT p.companyId, p.productId, fd.productDetailId,
       CAST(fd.stockQuantity AS DECIMAL(18,3)) AS qty
INTO #opening
FROM dbo.products p
JOIN firstDetail fd ON fd.productId = p.productId AND fd.rn = 1
WHERE p.trackInventory = 1
  AND NOT EXISTS (SELECT 1 FROM dbo.inventoryStock s
                  WHERE s.companyId = p.companyId AND s.productId = p.productId);

SET XACT_ABORT ON;
BEGIN TRANSACTION;

INSERT INTO dbo.inventoryStock (companyId, productId, stockQuantity)
SELECT companyId, productId, qty FROM #opening;

INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
SELECT companyId, productId, qty, 'opening',
       N'Fase 1: saldo inicial tomado de productDetails.stockQuantity', 'productDetails', productDetailId, NULL
FROM #opening
WHERE qty <> 0;

COMMIT TRANSACTION;

SELECT COUNT(*) AS openingRowsCreated FROM #opening;
DROP TABLE #opening;
SET XACT_ABORT OFF;
GO

-- 3) dbo.sp_inventory_post -------------------------------------------------------------
CREATE OR ALTER PROC dbo.sp_inventory_post
    @companyId     INT,
    @productId     INT,
    @quantityDelta DECIMAL(18,3),
    @reason        VARCHAR(30),
    @refType       VARCHAR(30)   = NULL,
    @refId         INT           = NULL,
    @userId        INT           = NULL,
    @notes         NVARCHAR(300) = NULL
AS
BEGIN
    -- One ledger row + the balance, atomically. Returns nothing (safe to call from
    -- SPs whose caller reads the first result set).
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @companyId IS NULL OR @productId IS NULL OR @reason IS NULL
        THROW 50110, 'sp_inventory_post: companyId, productId and reason are required.', 1;
    IF ISNULL(@quantityDelta, 0) = 0 RETURN;

    BEGIN TRANSACTION;

    INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
    VALUES (@companyId, @productId, @quantityDelta, @reason, @notes, @refType, @refId, @userId);

    MERGE dbo.inventoryStock WITH (HOLDLOCK) AS t
    USING (SELECT @companyId AS companyId, @productId AS productId) AS s
       ON t.companyId = s.companyId AND t.productId = s.productId
    WHEN MATCHED THEN
        UPDATE SET stockQuantity = t.stockQuantity + @quantityDelta, updatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (companyId, productId, stockQuantity) VALUES (s.companyId, s.productId, @quantityDelta);

    COMMIT TRANSACTION;
END
GO

-- 4a) Sales trigger --------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_incomeDetails_inventory
ON dbo.incomeDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- Posts sales to the inventory ledger. See the header of
    -- 2026-10-15c_inventory_single_source.sql for the rules.
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @m TABLE (
        companyId     INT           NOT NULL,
        productId     INT           NOT NULL,
        refId         INT           NOT NULL,
        quantityDelta DECIMAL(18,3) NOT NULL,
        userId        INT           NULL
    );

    ;WITH lines AS (
        -- New line: needs a tracked product.
        SELECT i.incomeId AS refId, i.productId, -CAST(i.quantity AS DECIMAL(18,3)) AS q, 1 AS needsTracking
        FROM inserted i
        WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.incomeDetailId = i.incomeDetailId)

        UNION ALL
        -- Deleted or edited line: undo only what this ledger posted for it.
        SELECT d.incomeId, d.productId, CAST(d.quantity AS DECIMAL(18,3)), 0
        FROM deleted d
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'income' AND m.refId = d.incomeId AND m.productId = d.productId)

        UNION ALL
        -- Edited line that was posted: post its new quantity.
        SELECT i.incomeId, i.productId, -CAST(i.quantity AS DECIMAL(18,3)), 0
        FROM inserted i
        JOIN deleted d ON d.incomeDetailId = i.incomeDetailId
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'income' AND m.refId = d.incomeId AND m.productId = d.productId)
    )
    INSERT INTO @m (companyId, productId, refId, quantityDelta, userId)
    SELECT COALESCE(h.companyId, p.companyId), l.productId, l.refId, SUM(l.q), MAX(h.userId)
    FROM lines l
    JOIN dbo.products p ON p.productId = l.productId
    LEFT JOIN dbo.income h ON h.incomeId = l.refId
    WHERE l.needsTracking = 0 OR p.trackInventory = 1
    GROUP BY COALESCE(h.companyId, p.companyId), l.productId, l.refId
    HAVING SUM(l.q) <> 0;

    IF NOT EXISTS (SELECT 1 FROM @m) RETURN;

    INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
    SELECT companyId, productId, quantityDelta,
           CASE WHEN quantityDelta < 0 THEN 'sale' ELSE 'sale_reversal' END,
           NULL, 'income', refId, userId
    FROM @m;

    MERGE dbo.inventoryStock WITH (HOLDLOCK) AS t
    USING (SELECT companyId, productId, SUM(quantityDelta) AS delta
           FROM @m GROUP BY companyId, productId) AS s
       ON t.companyId = s.companyId AND t.productId = s.productId
    WHEN MATCHED THEN
        UPDATE SET stockQuantity = t.stockQuantity + s.delta, updatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (companyId, productId, stockQuantity) VALUES (s.companyId, s.productId, s.delta);
END
GO

-- 4b) Purchases trigger --------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_expenseDetails_inventory
ON dbo.expenseDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- Posts purchases to the inventory ledger. See the header of
    -- 2026-10-15c_inventory_single_source.sql for the rules.
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @m TABLE (
        companyId     INT           NOT NULL,
        productId     INT           NOT NULL,
        refId         INT           NOT NULL,
        quantityDelta DECIMAL(18,3) NOT NULL,
        userId        INT           NULL
    );

    ;WITH lines AS (
        -- New line: needs a tracked product.
        SELECT i.expenseId AS refId, i.productId, CAST(i.quantity AS DECIMAL(18,3)) AS q, 1 AS needsTracking
        FROM inserted i
        WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.expenseDetailId = i.expenseDetailId)

        UNION ALL
        -- Deleted or edited line: undo only what this ledger posted for it.
        SELECT d.expenseId, d.productId, -CAST(d.quantity AS DECIMAL(18,3)), 0
        FROM deleted d
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'expense' AND m.refId = d.expenseId AND m.productId = d.productId)

        UNION ALL
        -- Edited line that was posted: post its new quantity.
        SELECT i.expenseId, i.productId, CAST(i.quantity AS DECIMAL(18,3)), 0
        FROM inserted i
        JOIN deleted d ON d.expenseDetailId = i.expenseDetailId
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'expense' AND m.refId = d.expenseId AND m.productId = d.productId)
    )
    INSERT INTO @m (companyId, productId, refId, quantityDelta, userId)
    SELECT COALESCE(h.companyId, p.companyId), l.productId, l.refId, SUM(l.q), MAX(h.userId)
    FROM lines l
    JOIN dbo.products p ON p.productId = l.productId
    LEFT JOIN dbo.expenses h ON h.expenseId = l.refId
    WHERE l.needsTracking = 0 OR p.trackInventory = 1
    GROUP BY COALESCE(h.companyId, p.companyId), l.productId, l.refId
    HAVING SUM(l.q) <> 0;

    IF NOT EXISTS (SELECT 1 FROM @m) RETURN;

    INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
    SELECT companyId, productId, quantityDelta,
           CASE WHEN quantityDelta > 0 THEN 'purchase' ELSE 'purchase_reversal' END,
           NULL, 'expense', refId, userId
    FROM @m;

    MERGE dbo.inventoryStock WITH (HOLDLOCK) AS t
    USING (SELECT companyId, productId, SUM(quantityDelta) AS delta
           FROM @m GROUP BY companyId, productId) AS s
       ON t.companyId = s.companyId AND t.productId = s.productId
    WHEN MATCHED THEN
        UPDATE SET stockQuantity = t.stockQuantity + s.delta, updatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (companyId, productId, stockQuantity) VALUES (s.companyId, s.productId, s.delta);
END
GO

-- 5) Product SPs (stock from inventoryStock) -------------------------------------------

-- dbo.sp_products_by_company
CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'                         -- all
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "categoryId": "1002" } ] }'  -- one category
    */

    DECLARE @companyId INT;
    DECLARE @categoryId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    -- Optional: productCategoryId (or legacy "categoryId"); missing/0 = all categories.
    SELECT TOP (1)
        @categoryId = NULLIF(TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'),
                                               JSON_VALUE(value, '$.categoryId')) AS INT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.productCategoryId AS categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        p.trackInventory,
        -- Stock lives only in inventoryStock (phase 1); details[] keeps its shape.
        ISNULL(inv.stockQuantity, 0) AS stockQuantity,
        (
            SELECT d.productDetailId, ISNULL(inv.stockQuantity, 0) AS stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name
            FROM productCategories c
            WHERE c.productCategoryId = p.productCategoryId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS category,
        (
            SELECT ds.productDescriptionId, ds.Dosage, ds.measurementId, ds.is_principal, ds.activeIngredientId
            FROM productsDescription ds
            WHERE ds.productId = p.productId
            FOR JSON PATH
        ) AS descriptions,
        (
            SELECT
                o.productOptionId AS [productOptionId],
                o.name,
                o.type,
                (
                    SELECT
                        c.productOptionChoiceId AS [productOptionChoiceId],
                        c.name,
                        c.price
                    FROM productOptionChoices c
                    WHERE c.productOptionId = o.productOptionId
                    FOR JSON PATH
                ) AS choices
            FROM productOptions o
            WHERE o.productId = p.productId
            FOR JSON PATH
        ) AS options
    FROM products p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
      AND (@categoryId IS NULL OR p.productCategoryId = @categoryId)
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_products_one
CREATE OR ALTER PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
        "productId": "1"
        }
     ]   
    }'
    */

    DECLARE @productId INT;

    -- Extracting ProductId safely
    SET @productId = TRY_CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

    -- Complete JSON structure generation matching the layout used by your application
    SELECT 
        p.[productId]
        ,p.[name]
        ,ISNULL(p.[barCode],'') AS barCode
        ,ISNULL(p.[code],'') AS code
        ,ISNULL(p.[dateOfExpire],'') AS dateOfExpire
        ,p.[productFormId]
        ,p.[manufactureId]
        ,ISNULL(p.[description],'') AS description
        ,p.[productCategoryId] AS categoryId
        ,p.[companyId]
        ,p.[trackInventory]
        ,ISNULL(inv.stockQuantity, 0) AS stockQuantity
        ,p.[createdAt]
        ,ISNULL(p.[updatedAt],'') AS updatedAt
        
        -- 1. Nested Details Object (Returns as an array/object matching your save logic)
        ,(
            SELECT 
                ISNULL(inv.stockQuantity, 0) AS stockQuantity
                ,pd.unitPrice
                ,pd.salePrice
            FROM dbo.productDetails pd
            WHERE pd.productId = p.productId
            FOR JSON PATH
        ) AS productDetails

        -- 2. Nested Descriptions Array
        ,(
            SELECT 
                pdesc.Dosage
                ,pdesc.measurementId
                ,pdesc.is_principal
                ,pdesc.activeIngredientId
            FROM dbo.productsDescription pdesc
            WHERE pdesc.productId = p.productId
            FOR JSON PATH
        ) AS productDescriptions

        -- 3. Nested Options and nested Choices Array
        ,(
            SELECT 
                po.optionKey
                ,po.name
                ,po.type
                ,(
                    SELECT 
                        poc.choiceKey
                        ,poc.name
                        ,poc.price
                        ,poc.description
                    FROM dbo.productOptionChoices poc
                    WHERE poc.productOptionId = po.productOptionId
                    FOR JSON PATH
                ) AS optionChoices
            FROM dbo.productOptions po
            WHERE po.productId = p.productId
            FOR JSON PATH
        ) AS productOptions

    FROM 
        [dbo].[products] p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    WHERE
        p.productId = @productId
    FOR JSON PATH, ROOT('products');

END
GO

-- dbo.sp_products_save
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
            -- Code is an identity-like counter per company: MAX(numeric code) + 1,
            -- never typed by the user. UPDLOCK+HOLDLOCK keeps two concurrent
            -- inserts from reading the same MAX (we are inside the transaction).
            DECLARE @nextCode VARCHAR(100) = CAST(
                ISNULL((SELECT MAX(TRY_CAST(code AS BIGINT))
                        FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
                        WHERE companyId = @companyId), 0) + 1 AS VARCHAR(100));

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, productCategoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice, trackInventory)
            SELECT 
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), @nextCode,
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, '$.dateOfExpire'), '')), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'), JSON_VALUE(value, '$.categoryId')) AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, '$.netContent') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, '$.unitOfMeasure'), ''),
                TRY_CAST(JSON_VALUE(value, '$.referencePrice') AS DECIMAL(10,2)),
                -- trackInventory: explicit value wins; otherwise physical goods (barcode / supply) are tracked.
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.trackInventory') AS BIT),
                         CASE WHEN NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.barCode'))), '') IS NOT NULL
                                OR TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT) = 1 THEN 1 ELSE 0 END)
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR('productId is required for update.', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, '$.name'), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, '$.barCode'), p.barCode),
                -- code is never changed after insert (auto-assigned identity)
                p.dateOfExpire = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, '$.noExpire') AS BIT) = 1 THEN NULL
                    ELSE COALESCE(TRY_CONVERT(DATE, NULLIF(JSON_VALUE(j.value, '$.dateOfExpire'), '')), p.dateOfExpire)
                END,
                -- netContent/unitOfMeasure/referencePrice: the wizard always sends all three (null = cleared)
                p.netContent = TRY_CAST(JSON_VALUE(j.value, '$.netContent') AS DECIMAL(10,3)),
                p.unitOfMeasure = NULLIF(JSON_VALUE(j.value, '$.unitOfMeasure'), ''),
                p.referencePrice = TRY_CAST(JSON_VALUE(j.value, '$.referencePrice') AS DECIMAL(10,2)),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.productFormId') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.manufactureId') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, '$.description'), p.description),
                p.updatedAt = GETDATE(),
                p.productCategoryId = COALESCE(TRY_CAST(COALESCE(JSON_VALUE(j.value, '$.productCategoryId'), JSON_VALUE(j.value, '$.categoryId')) AS INT), p.productCategoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isSupply') AS BIT), p.isSupply),
                p.trackInventory = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.trackInventory') AS BIT), p.trackInventory)
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
            DELETE FROM dbo.inventoryStock WHERE productId = @productId AND companyId = @companyId;
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

        -- productDetails keeps prices only. stockQuantity there is frozen since phase 1
        -- (2026-10-15c): the only stock is dbo.inventoryStock + dbo.inventoryMovements.
        IF EXISTS (SELECT 1 FROM dbo.productDetails WHERE productId = @productId)
        BEGIN
            UPDATE dbo.productDetails
            SET unitPrice = COALESCE(@uPrice, unitPrice),
                salePrice = COALESCE(@sPrice, salePrice),
                updatedAt = GETDATE()
            WHERE productId = @productId;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
            VALUES (@productId, 0, COALESCE(@uPrice, 0), COALESCE(@sPrice, 0), GETDATE(), GETDATE());
        END

        -- The stock typed in the wizard is a target count: post the difference as
        -- 'opening' (first count) or 'adjustment' (recount). A non-zero stock turns
        -- tracking on; a 0 on an untracked product (e.g. made-to-order food) is ignored.
        IF @stock IS NOT NULL
           AND (@stock <> 0 OR EXISTS (SELECT 1 FROM dbo.products
                                       WHERE productId = @productId AND trackInventory = 1))
        BEGIN
            DECLARE @current DECIMAL(18,3), @hasStockRow BIT = 0, @stockUserId INT,
                    @stockDelta DECIMAL(18,3), @stockReason VARCHAR(30);

            SELECT @current = stockQuantity, @hasStockRow = 1
            FROM dbo.inventoryStock WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND productId = @productId;

            SELECT TOP (1) @stockUserId = TRY_CAST(JSON_VALUE(value, '$.userId') AS INT)
            FROM OPENJSON(@pjsonfile, '$.products');

            UPDATE dbo.products SET trackInventory = 1
            WHERE productId = @productId AND trackInventory = 0;

            SET @stockDelta  = @stock - ISNULL(@current, 0);
            SET @stockReason = CASE WHEN @hasStockRow = 1 THEN 'adjustment' ELSE 'opening' END;

            IF @stockDelta <> 0
                EXEC dbo.sp_inventory_post
                    @companyId = @companyId,
                    @productId = @productId,
                    @quantityDelta = @stockDelta,
                    @reason = @stockReason,
                    @refType = 'product_save',
                    @refId = @productId,
                    @userId = @stockUserId,
                    @notes = N'Stock capturado en el asistente de producto';
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

-- 6) Verify ------------------------------------------------------------------------------
-- a) both triggers exist (expect 2 rows)
SELECT name AS triggerName, OBJECT_NAME(parent_id) AS tableName, is_disabled
FROM sys.triggers
WHERE name IN ('trg_incomeDetails_inventory', 'trg_expenseDetails_inventory');

-- b) tracked products: ledger stock vs the frozen productDetails number (equal right after the migration)
SELECT p.companyId, p.productId, p.name, p.trackInventory,
       s.stockQuantity AS inventoryStock,
       (SELECT TOP 1 d.stockQuantity FROM dbo.productDetails d
        WHERE d.productId = p.productId ORDER BY d.productDetailId) AS productDetailsStock_frozen
FROM dbo.products p
LEFT JOIN dbo.inventoryStock s ON s.companyId = p.companyId AND s.productId = p.productId
ORDER BY p.trackInventory DESC, p.companyId, p.name;

-- c) balance = sum of movements (expect 0 rows; rows that existed before this
--    migration without movements show up here and only need one 'adjustment')
SELECT s.companyId, s.productId, s.stockQuantity, ISNULL(m.total, 0) AS movementsTotal
FROM dbo.inventoryStock s
LEFT JOIN (SELECT companyId, productId, SUM(quantityDelta) AS total
           FROM dbo.inventoryMovements GROUP BY companyId, productId) m
       ON m.companyId = s.companyId AND m.productId = s.productId
WHERE s.stockQuantity <> ISNULL(m.total, 0);
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO

-- #############################################################################
-- [65/67] 2026-10-15d_catalog_hierarchy.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [65/67] 2026-10-15d_catalog_hierarchy.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Catalog hierarchy: Categoría → Subcategoría → Producto (+ required options, inactive products)
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-15c_inventory_single_source.sql (redeploys the product SPs from it).
--
-- WHY (GMO Lavandería catalog): products need a 3-level catalog — Servicios › Lavado
--   › Servicio de lavado — and options such as "Ciclo" must be mandatory, otherwise
--   a wash can be sold at the $0 base price. Old pseudo-products ("Bebidas",
--   "Productos Limpieza", whose options were the real items) must disappear from
--   the POS without deleting them (past sales point to them).
--
-- WHAT:
--   1. productCategories.parentCategoryId (NULL = top-level). Two levels only: the
--      parent must be a top-level category of the same company. FK to itself.
--      products.productCategoryId keeps pointing to ONE category (normally the
--      subcategory), so existing products and categories keep working as top-level.
--   2. productOptions.isRequired BIT (default 0). Price model unchanged:
--      line = base salePrice + Σ chosen choices ("base $0 + Básico $40 = $40").
--   3. products.isActive BIT (default 1). Inactive products are hidden from the POS.
--   4. SPs:
--      sp_products_categories      insert/update parentCategoryId (validated); insert
--                                  returns the new id in result[0].value.
--      sp_products_categories_all  returns parentCategoryId (top-level first).
--      sp_products_by_company      hides isActive = 0 (unless "includeInactive": 1);
--                                  categoryId of a top-level category also returns its
--                                  subcategories' products; returns isActive,
--                                  category.parentCategoryId, options[].isRequired.
--      sp_products_one             returns isActive and productOptions[].isRequired.
--      sp_products_save            accepts isActive and productOptions[].isRequired.
--   NOTE: sp_products_save re-creates options on every save — a client that does
--   not send isRequired yet resets it to 0. Ship the frontend toggle with this.
-- ROLLBACK: 2026-10-15d_catalog_hierarchy_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.products', 'trackInventory') IS NULL
    BEGIN RAISERROR('products.trackInventory missing — run 2026-10-15c_inventory_single_source.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
GO

-- 1) productCategories.parentCategoryId ------------------------------------------------
IF COL_LENGTH('dbo.productCategories', 'parentCategoryId') IS NULL
    ALTER TABLE dbo.productCategories ADD parentCategoryId INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_productCategories_parent')
    EXEC (N'ALTER TABLE dbo.productCategories WITH CHECK
            ADD CONSTRAINT FK_productCategories_parent
            FOREIGN KEY (parentCategoryId) REFERENCES dbo.productCategories (productCategoryId);');
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_productCategories_parent'
               AND object_id = OBJECT_ID('dbo.productCategories'))
    EXEC (N'CREATE NONCLUSTERED INDEX IX_productCategories_parent ON dbo.productCategories (companyId, parentCategoryId);');
RAISERROR('OK: productCategories.parentCategoryId', 0, 1) WITH NOWAIT;
GO

-- 2) productOptions.isRequired ---------------------------------------------------------
IF COL_LENGTH('dbo.productOptions', 'isRequired') IS NULL
    ALTER TABLE dbo.productOptions ADD isRequired BIT NOT NULL
        CONSTRAINT DF_productOptions_isRequired DEFAULT (0);
RAISERROR('OK: productOptions.isRequired', 0, 1) WITH NOWAIT;
GO

-- 3) products.isActive -----------------------------------------------------------------
IF COL_LENGTH('dbo.products', 'isActive') IS NULL
    ALTER TABLE dbo.products ADD isActive BIT NOT NULL
        CONSTRAINT DF_products_isActive DEFAULT (1);
RAISERROR('OK: products.isActive', 0, 1) WITH NOWAIT;
GO

-- 4) Stored procedures -----------------------------------------------------------------

-- dbo.sp_products_categories
CREATE OR ALTER PROC [dbo].[sp_products_categories]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- EXAMPLES --

    

    -- 1) INSERT (one or many)
    DECLARE @pjsonfile NVARCHAR(MAX) = '{
      "productCategories": [
        { "action": 1, "name": "Detergentes", "image": "detergentes.png", "companyId": 3 },
        { "action": 1, "name": "Suavizantes", "image": "suavizantes.png", "companyId": 3 }
      ]
    }';

    */

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '{
          "result":[{ "value":"", "msg":"", "error":"" }]
        }',
        @Error NVARCHAR(500) = '',
        @action INT,
        @filterCompanyId INT = NULL,
        @filterCategoryId INT = NULL;

    -- Read action and optional filters from the first element
    SELECT TOP (1)
        @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
        @filterCompanyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        @filterCategoryId = TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.productCategories');

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Subcategories: parentCategoryId must be a TOP-LEVEL category of the same
        -- company (two levels: Categoría → Subcategoría). 0 on update = make it top-level.
        IF EXISTS (
            SELECT 1
            FROM OPENJSON(@pjsonfile, '$.productCategories') j
            CROSS APPLY (SELECT NULLIF(TRY_CAST(JSON_VALUE(j.value, '$.parentCategoryId') AS INT), 0) AS parentId,
                                TRY_CAST(JSON_VALUE(j.value, '$.productCategoryId') AS INT) AS selfId,
                                TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT) AS companyId) x
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) IN (1, 2)
              AND x.parentId IS NOT NULL
              AND (x.parentId = x.selfId
                   OR NOT EXISTS (SELECT 1 FROM dbo.productCategories pc
                                  WHERE pc.productCategoryId = x.parentId
                                    AND pc.parentCategoryId IS NULL
                                    AND (x.companyId IS NULL OR pc.companyId = x.companyId))
                   OR EXISTS (SELECT 1 FROM dbo.productCategories ch WHERE ch.parentCategoryId = x.selfId))
        )
            THROW 50201, 'parentCategoryId inválido: debe ser una categoría principal de la misma empresa (y una categoría con subcategorías no puede ser subcategoría).', 1;

        IF @action = 1
        BEGIN
            -- INSERT (supports multiple rows)
            DECLARE @Inserted TABLE (productCategoryId INT);

            INSERT INTO [dbo].[productCategories] ([name], [image], [companyId], [parentCategoryId])
            OUTPUT inserted.productCategoryId INTO @Inserted(productCategoryId)
            SELECT
                JSON_VALUE(j.value, '$.name'),
                JSON_VALUE(j.value, '$.image'),
                TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT),
                NULLIF(TRY_CAST(JSON_VALUE(j.value, '$.parentCategoryId') AS INT), 0)
            FROM OPENJSON(@pjsonfile, '$.productCategories') AS j
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 1;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST((SELECT MAX(productCategoryId) FROM @Inserted) AS NVARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', CONCAT('Inserted Successfully (', (SELECT COUNT(*) FROM @Inserted), ' row(s))'));
        END
        ELSE IF @action = 2
        BEGIN
            -- UPDATE (supports multiple rows)
            UPDATE pc
            SET
                pc.[name]  = COALESCE(JSON_VALUE(j.value, '$.name'), pc.[name]),
                pc.[image] = COALESCE(JSON_VALUE(j.value, '$.image'), pc.[image]),
                pc.[companyId] = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT), pc.[companyId]),
                -- missing/null = keep, 0 = top-level, n = subcategory of n
                pc.[parentCategoryId] = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, '$.parentCategoryId') AS INT) IS NULL THEN pc.[parentCategoryId]
                    ELSE NULLIF(TRY_CAST(JSON_VALUE(j.value, '$.parentCategoryId') AS INT), 0)
                END
            FROM [dbo].[productCategories] pc
            INNER JOIN OPENJSON(@pjsonfile, '$.productCategories') j
                ON pc.productCategoryId = TRY_CAST(JSON_VALUE(j.value, '$.productCategoryId') AS INT)
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 2;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- DELETE (supports multiple ids)
            DELETE pc
            FROM [dbo].[productCategories] pc
            INNER JOIN OPENJSON(@pjsonfile, '$.productCategories') j
                ON pc.productCategoryId = TRY_CAST(JSON_VALUE(j.value, '$.productCategoryId') AS INT)
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 3;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            -- Unknown action
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid or missing action (use 0=list, 1=insert, 2=update, 3=delete)');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Unified status response for non-list actions
    -- Unified status response for non-list actions
SELECT 
    (
        SELECT
            JSON_VALUE(value, '$.value') AS [value],
            JSON_VALUE(value, '$.msg')   AS [msg],
            JSON_VALUE(value, '$.error') AS [error]
        FROM OPENJSON(@Outputmessage, '$.result')
        FOR JSON PATH, ROOT('result')
    ) AS json_output;

END
GO

-- dbo.sp_products_categories_all
CREATE OR ALTER PROC [dbo].[sp_products_categories_all]
    @pjsonfile NVARCHAR(MAX)
AS

BEGIN
    SET NOCOUNT ON;

   /*
    DECLARE @pjsonfile NVARCHAR(MAX) = '{
      "productCategories": [
        { "companyId": 1, "categoryId": null }
      ]
    }';
    */

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '{
          "result":[{ "value":"", "msg":"", "error":"" }]
        }',
        @Error NVARCHAR(500) = '',
        @action INT,
        @filterCompanyId INT = NULL,
        @filterCategoryId INT = NULL;

    -- Read action and optional filters from the first element
    SELECT TOP (1)
        @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
        @filterCompanyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        @filterCategoryId = TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.productCategories');

    
    -- LIST
    SELECT
        [productCategoryId] AS [categoryId],
        [name],
        [image],
        [companyId],
        [parentCategoryId]          -- NULL = top-level category; otherwise a subcategory of it
    FROM [dbo].[productCategories]
    WHERE (@filterCompanyId IS NULL OR companyId = @filterCompanyId)
        AND (@filterCategoryId IS NULL OR productCategoryId = @filterCategoryId)
    ORDER BY CASE WHEN [parentCategoryId] IS NULL THEN 0 ELSE 1 END, [name]
    FOR JSON PATH, ROOT('productCategories');

END
GO

-- dbo.sp_products_by_company
CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'                         -- all
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "categoryId": "1002" } ] }'  -- one category
    */

    DECLARE @companyId INT;
    DECLARE @categoryId INT;
    DECLARE @includeInactive BIT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    -- Optional: productCategoryId (or legacy "categoryId"); missing/0 = all categories.
    SELECT TOP (1)
        @categoryId = NULLIF(TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'),
                                               JSON_VALUE(value, '$.categoryId')) AS INT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    -- Admin screens send includeInactive = 1 to see (and reactivate) hidden products; the POS never does.
    SELECT TOP (1) @includeInactive = ISNULL(TRY_CAST(JSON_VALUE(value, '$.includeInactive') AS BIT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.productCategoryId AS categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        p.trackInventory,
        p.isActive,
        -- Stock lives only in inventoryStock (phase 1); details[] keeps its shape.
        ISNULL(inv.stockQuantity, 0) AS stockQuantity,
        (
            SELECT d.productDetailId, ISNULL(inv.stockQuantity, 0) AS stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name, c.parentCategoryId
            FROM productCategories c
            WHERE c.productCategoryId = p.productCategoryId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS category,
        (
            SELECT ds.productDescriptionId, ds.Dosage, ds.measurementId, ds.is_principal, ds.activeIngredientId
            FROM productsDescription ds
            WHERE ds.productId = p.productId
            FOR JSON PATH
        ) AS descriptions,
        (
            SELECT
                o.productOptionId AS [productOptionId],
                o.name,
                o.type,
                o.isRequired,
                (
                    SELECT
                        c.productOptionChoiceId AS [productOptionChoiceId],
                        c.name,
                        c.price
                    FROM productOptionChoices c
                    WHERE c.productOptionId = o.productOptionId
                    FOR JSON PATH
                ) AS choices
            FROM productOptions o
            WHERE o.productId = p.productId
            FOR JSON PATH
        ) AS options
    FROM products p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
      AND (p.isActive = 1 OR @includeInactive = 1)
      -- A category also matches the products of its subcategories.
      AND (@categoryId IS NULL
           OR p.productCategoryId = @categoryId
           OR p.productCategoryId IN (SELECT sc.productCategoryId FROM dbo.productCategories sc
                                      WHERE sc.parentCategoryId = @categoryId))
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_products_one
CREATE OR ALTER PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
        "productId": "1"
        }
     ]   
    }'
    */

    DECLARE @productId INT;

    -- Extracting ProductId safely
    SET @productId = TRY_CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

    -- Complete JSON structure generation matching the layout used by your application
    SELECT 
        p.[productId]
        ,p.[name]
        ,ISNULL(p.[barCode],'') AS barCode
        ,ISNULL(p.[code],'') AS code
        ,ISNULL(p.[dateOfExpire],'') AS dateOfExpire
        ,p.[productFormId]
        ,p.[manufactureId]
        ,ISNULL(p.[description],'') AS description
        ,p.[productCategoryId] AS categoryId
        ,p.[companyId]
        ,p.[trackInventory]
        ,p.[isActive]
        ,ISNULL(inv.stockQuantity, 0) AS stockQuantity
        ,p.[createdAt]
        ,ISNULL(p.[updatedAt],'') AS updatedAt
        
        -- 1. Nested Details Object (Returns as an array/object matching your save logic)
        ,(
            SELECT 
                ISNULL(inv.stockQuantity, 0) AS stockQuantity
                ,pd.unitPrice
                ,pd.salePrice
            FROM dbo.productDetails pd
            WHERE pd.productId = p.productId
            FOR JSON PATH
        ) AS productDetails

        -- 2. Nested Descriptions Array
        ,(
            SELECT 
                pdesc.Dosage
                ,pdesc.measurementId
                ,pdesc.is_principal
                ,pdesc.activeIngredientId
            FROM dbo.productsDescription pdesc
            WHERE pdesc.productId = p.productId
            FOR JSON PATH
        ) AS productDescriptions

        -- 3. Nested Options and nested Choices Array
        ,(
            SELECT 
                po.optionKey
                ,po.name
                ,po.type
                ,po.isRequired
                ,(
                    SELECT 
                        poc.choiceKey
                        ,poc.name
                        ,poc.price
                        ,poc.description
                    FROM dbo.productOptionChoices poc
                    WHERE poc.productOptionId = po.productOptionId
                    FOR JSON PATH
                ) AS optionChoices
            FROM dbo.productOptions po
            WHERE po.productId = p.productId
            FOR JSON PATH
        ) AS productOptions

    FROM 
        [dbo].[products] p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    WHERE
        p.productId = @productId
    FOR JSON PATH, ROOT('products');

END
GO

-- dbo.sp_products_save
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
            -- Code is an identity-like counter per company: MAX(numeric code) + 1,
            -- never typed by the user. UPDLOCK+HOLDLOCK keeps two concurrent
            -- inserts from reading the same MAX (we are inside the transaction).
            DECLARE @nextCode VARCHAR(100) = CAST(
                ISNULL((SELECT MAX(TRY_CAST(code AS BIGINT))
                        FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
                        WHERE companyId = @companyId), 0) + 1 AS VARCHAR(100));

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, productCategoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice, trackInventory, isActive)
            SELECT 
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), @nextCode,
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, '$.dateOfExpire'), '')), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'), JSON_VALUE(value, '$.categoryId')) AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, '$.netContent') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, '$.unitOfMeasure'), ''),
                TRY_CAST(JSON_VALUE(value, '$.referencePrice') AS DECIMAL(10,2)),
                -- trackInventory: explicit value wins; otherwise physical goods (barcode / supply) are tracked.
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.trackInventory') AS BIT),
                         CASE WHEN NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.barCode'))), '') IS NOT NULL
                                OR TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT) = 1 THEN 1 ELSE 0 END),
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isActive') AS BIT), 1)
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR('productId is required for update.', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, '$.name'), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, '$.barCode'), p.barCode),
                -- code is never changed after insert (auto-assigned identity)
                p.dateOfExpire = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, '$.noExpire') AS BIT) = 1 THEN NULL
                    ELSE COALESCE(TRY_CONVERT(DATE, NULLIF(JSON_VALUE(j.value, '$.dateOfExpire'), '')), p.dateOfExpire)
                END,
                -- netContent/unitOfMeasure/referencePrice: the wizard always sends all three (null = cleared)
                p.netContent = TRY_CAST(JSON_VALUE(j.value, '$.netContent') AS DECIMAL(10,3)),
                p.unitOfMeasure = NULLIF(JSON_VALUE(j.value, '$.unitOfMeasure'), ''),
                p.referencePrice = TRY_CAST(JSON_VALUE(j.value, '$.referencePrice') AS DECIMAL(10,2)),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.productFormId') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.manufactureId') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, '$.description'), p.description),
                p.updatedAt = GETDATE(),
                p.productCategoryId = COALESCE(TRY_CAST(COALESCE(JSON_VALUE(j.value, '$.productCategoryId'), JSON_VALUE(j.value, '$.categoryId')) AS INT), p.productCategoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isSupply') AS BIT), p.isSupply),
                p.trackInventory = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.trackInventory') AS BIT), p.trackInventory),
                p.isActive = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isActive') AS BIT), p.isActive)
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
            DELETE FROM dbo.inventoryStock WHERE productId = @productId AND companyId = @companyId;
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

        -- productDetails keeps prices only. stockQuantity there is frozen since phase 1
        -- (2026-10-15c): the only stock is dbo.inventoryStock + dbo.inventoryMovements.
        IF EXISTS (SELECT 1 FROM dbo.productDetails WHERE productId = @productId)
        BEGIN
            UPDATE dbo.productDetails
            SET unitPrice = COALESCE(@uPrice, unitPrice),
                salePrice = COALESCE(@sPrice, salePrice),
                updatedAt = GETDATE()
            WHERE productId = @productId;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
            VALUES (@productId, 0, COALESCE(@uPrice, 0), COALESCE(@sPrice, 0), GETDATE(), GETDATE());
        END

        -- The stock typed in the wizard is a target count: post the difference as
        -- 'opening' (first count) or 'adjustment' (recount). A non-zero stock turns
        -- tracking on; a 0 on an untracked product (e.g. made-to-order food) is ignored.
        IF @stock IS NOT NULL
           AND (@stock <> 0 OR EXISTS (SELECT 1 FROM dbo.products
                                       WHERE productId = @productId AND trackInventory = 1))
        BEGIN
            DECLARE @current DECIMAL(18,3), @hasStockRow BIT = 0, @stockUserId INT,
                    @stockDelta DECIMAL(18,3), @stockReason VARCHAR(30);

            SELECT @current = stockQuantity, @hasStockRow = 1
            FROM dbo.inventoryStock WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND productId = @productId;

            SELECT TOP (1) @stockUserId = TRY_CAST(JSON_VALUE(value, '$.userId') AS INT)
            FROM OPENJSON(@pjsonfile, '$.products');

            UPDATE dbo.products SET trackInventory = 1
            WHERE productId = @productId AND trackInventory = 0;

            SET @stockDelta  = @stock - ISNULL(@current, 0);
            SET @stockReason = CASE WHEN @hasStockRow = 1 THEN 'adjustment' ELSE 'opening' END;

            IF @stockDelta <> 0
                EXEC dbo.sp_inventory_post
                    @companyId = @companyId,
                    @productId = @productId,
                    @quantityDelta = @stockDelta,
                    @reason = @stockReason,
                    @refType = 'product_save',
                    @refId = @productId,
                    @userId = @stockUserId,
                    @notes = N'Stock capturado en el asistente de producto';
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
            INSERT INTO dbo.productOptions (productId, optionKey, name, type, isRequired, createdAt, updatedAt)
            SELECT @productId, JSON_VALUE(@pjsonfile, @optPath + '.optionKey'), JSON_VALUE(@pjsonfile, @optPath + '.name'), JSON_VALUE(@pjsonfile, @optPath + '.type'),
                   ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, @optPath + '.isRequired') AS BIT), 0), GETDATE(), GETDATE();
            
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

-- 5) Verify ------------------------------------------------------------------------------
SELECT
    CASE WHEN COL_LENGTH('dbo.productCategories', 'parentCategoryId') IS NOT NULL THEN 1 ELSE 0 END AS parentCategoryId,
    CASE WHEN COL_LENGTH('dbo.productOptions', 'isRequired')          IS NOT NULL THEN 1 ELSE 0 END AS isRequired,
    CASE WHEN COL_LENGTH('dbo.products', 'isActive')                  IS NOT NULL THEN 1 ELSE 0 END AS isActive;

EXEC dbo.sp_products_categories_all '{ "productCategories": [ { "companyId": 1 } ] }';
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO

-- #############################################################################
-- [66/67] 2026-10-15e_option_choice_measurements.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [66/67] 2026-10-15e_option_choice_measurements.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- Option choices carry their own quantity + unit (19 L, 600 ml, 100 ml)
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-15d_catalog_hierarchy.sql (redeploys the product SPs from it).
--
-- WHY: a single option offers choices of different sizes — Garrafón › Tamaño:
--   19 L / 10 L / 3 L; Té Arizona › Sabor: Negro 600 ml / Mango 450 ml. The size
--   belongs to the CHOICE, not to the product, and the unit must be a reusable
--   catalog value instead of free text repeated in every name.
--
-- WHAT:
--   1. dbo.measurements gets the units the POS wizard already uses (prefix = code):
--      g, kg, ml, L, pz (mg already exists). Unique index on prefix.
--   2. productOptionChoices.quantity DECIMAL(10,3) NULL + measurementId INT NULL
--      (FK → measurements). Both optional: services ("Básico", "40 Min") have none.
--   3. SPs:
--      sp_products_save        choices accept "quantity" and "measurementId" or the
--                              unit code "unit" ("ml", "L"…, resolved by prefix).
--      sp_products_by_company  options[].choices[] return quantity, measurementId, unit.
--      sp_products_one         productOptions[].optionChoices[] return the same.
--   Prices unchanged: line = productDetails.salePrice + Σ chosen choice prices.
--   NOT changed on purpose: products.netContent / unitOfMeasure (the size of the
--   base product itself, used by the wizard's price-per-unit hint) and
--   products.productFormId → productForms (legacy pharmacy packing).
--   A choice is a variant WITHOUT its own stock or barcode: if a size must be
--   counted in inventory or scanned, make it its own product.
-- ROLLBACK: 2026-10-15e_option_choice_measurements_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.productOptions', 'isRequired') IS NULL
    BEGIN RAISERROR('productOptions.isRequired missing — run 2026-10-15d_catalog_hierarchy.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
GO

-- 1) Units --------------------------------------------------------------------------------
INSERT INTO dbo.measurements (name, prefix)
SELECT u.name, u.prefix
FROM (VALUES ('grams', 'g'), ('kilograms', 'kg'), ('milliliters', 'ml'),
             ('liters', 'L'), ('pieces', 'pz'), ('milligrams', 'mg')) AS u(name, prefix)
WHERE NOT EXISTS (SELECT 1 FROM dbo.measurements m WHERE m.prefix = u.prefix);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_measurements_prefix'
               AND object_id = OBJECT_ID('dbo.measurements'))
   AND NOT EXISTS (SELECT prefix FROM dbo.measurements GROUP BY prefix HAVING COUNT(*) > 1)
    CREATE UNIQUE NONCLUSTERED INDEX UQ_measurements_prefix ON dbo.measurements (prefix);

SELECT measurementId, name, prefix FROM dbo.measurements ORDER BY measurementId;
GO

-- 2) productOptionChoices.quantity + measurementId ----------------------------------------
IF COL_LENGTH('dbo.productOptionChoices', 'quantity') IS NULL
    ALTER TABLE dbo.productOptionChoices ADD quantity DECIMAL(10,3) NULL;
IF COL_LENGTH('dbo.productOptionChoices', 'measurementId') IS NULL
    ALTER TABLE dbo.productOptionChoices ADD measurementId INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_productOptionChoices_measurements')
    EXEC (N'ALTER TABLE dbo.productOptionChoices WITH CHECK
            ADD CONSTRAINT FK_productOptionChoices_measurements
            FOREIGN KEY (measurementId) REFERENCES dbo.measurements (measurementId);');
RAISERROR('OK: productOptionChoices.quantity / measurementId', 0, 1) WITH NOWAIT;
GO

-- 3) Stored procedures ---------------------------------------------------------------------

-- dbo.sp_products_by_company
CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'                         -- all
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "categoryId": "1002" } ] }'  -- one category
    */

    DECLARE @companyId INT;
    DECLARE @categoryId INT;
    DECLARE @includeInactive BIT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    -- Optional: productCategoryId (or legacy "categoryId"); missing/0 = all categories.
    SELECT TOP (1)
        @categoryId = NULLIF(TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'),
                                               JSON_VALUE(value, '$.categoryId')) AS INT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    -- Admin screens send includeInactive = 1 to see (and reactivate) hidden products; the POS never does.
    SELECT TOP (1) @includeInactive = ISNULL(TRY_CAST(JSON_VALUE(value, '$.includeInactive') AS BIT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.productCategoryId AS categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        p.trackInventory,
        p.isActive,
        -- Stock lives only in inventoryStock (phase 1); details[] keeps its shape.
        ISNULL(inv.stockQuantity, 0) AS stockQuantity,
        (
            SELECT d.productDetailId, ISNULL(inv.stockQuantity, 0) AS stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name, c.parentCategoryId
            FROM productCategories c
            WHERE c.productCategoryId = p.productCategoryId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS category,
        (
            SELECT ds.productDescriptionId, ds.Dosage, ds.measurementId, ds.is_principal, ds.activeIngredientId
            FROM productsDescription ds
            WHERE ds.productId = p.productId
            FOR JSON PATH
        ) AS descriptions,
        (
            SELECT
                o.productOptionId AS [productOptionId],
                o.name,
                o.type,
                o.isRequired,
                (
                    SELECT
                        c.productOptionChoiceId AS [productOptionChoiceId],
                        c.name,
                        c.price,
                        c.quantity,                -- e.g. 19
                        c.measurementId,
                        m.prefix AS unit           -- e.g. 'L'
                    FROM productOptionChoices c
                    LEFT JOIN dbo.measurements m ON m.measurementId = c.measurementId
                    WHERE c.productOptionId = o.productOptionId
                    FOR JSON PATH
                ) AS choices
            FROM productOptions o
            WHERE o.productId = p.productId
            FOR JSON PATH
        ) AS options
    FROM products p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
      AND (p.isActive = 1 OR @includeInactive = 1)
      -- A category also matches the products of its subcategories.
      AND (@categoryId IS NULL
           OR p.productCategoryId = @categoryId
           OR p.productCategoryId IN (SELECT sc.productCategoryId FROM dbo.productCategories sc
                                      WHERE sc.parentCategoryId = @categoryId))
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_products_one
CREATE OR ALTER PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
        "productId": "1"
        }
     ]   
    }'
    */

    DECLARE @productId INT;

    -- Extracting ProductId safely
    SET @productId = TRY_CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

    -- Complete JSON structure generation matching the layout used by your application
    SELECT 
        p.[productId]
        ,p.[name]
        ,ISNULL(p.[barCode],'') AS barCode
        ,ISNULL(p.[code],'') AS code
        ,ISNULL(p.[dateOfExpire],'') AS dateOfExpire
        ,p.[productFormId]
        ,p.[manufactureId]
        ,ISNULL(p.[description],'') AS description
        ,p.[productCategoryId] AS categoryId
        ,p.[companyId]
        ,p.[trackInventory]
        ,p.[isActive]
        ,ISNULL(inv.stockQuantity, 0) AS stockQuantity
        ,p.[createdAt]
        ,ISNULL(p.[updatedAt],'') AS updatedAt
        
        -- 1. Nested Details Object (Returns as an array/object matching your save logic)
        ,(
            SELECT 
                ISNULL(inv.stockQuantity, 0) AS stockQuantity
                ,pd.unitPrice
                ,pd.salePrice
            FROM dbo.productDetails pd
            WHERE pd.productId = p.productId
            FOR JSON PATH
        ) AS productDetails

        -- 2. Nested Descriptions Array
        ,(
            SELECT 
                pdesc.Dosage
                ,pdesc.measurementId
                ,pdesc.is_principal
                ,pdesc.activeIngredientId
            FROM dbo.productsDescription pdesc
            WHERE pdesc.productId = p.productId
            FOR JSON PATH
        ) AS productDescriptions

        -- 3. Nested Options and nested Choices Array
        ,(
            SELECT 
                po.optionKey
                ,po.name
                ,po.type
                ,po.isRequired
                ,(
                    SELECT 
                        poc.choiceKey
                        ,poc.name
                        ,poc.price
                        ,poc.description
                        ,poc.quantity
                        ,poc.measurementId
                        ,m.prefix AS unit
                    FROM dbo.productOptionChoices poc
                    LEFT JOIN dbo.measurements m ON m.measurementId = poc.measurementId
                    WHERE poc.productOptionId = po.productOptionId
                    FOR JSON PATH
                ) AS optionChoices
            FROM dbo.productOptions po
            WHERE po.productId = p.productId
            FOR JSON PATH
        ) AS productOptions

    FROM 
        [dbo].[products] p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    WHERE
        p.productId = @productId
    FOR JSON PATH, ROOT('products');

END
GO

-- dbo.sp_products_save
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
            -- Code is an identity-like counter per company: MAX(numeric code) + 1,
            -- never typed by the user. UPDLOCK+HOLDLOCK keeps two concurrent
            -- inserts from reading the same MAX (we are inside the transaction).
            DECLARE @nextCode VARCHAR(100) = CAST(
                ISNULL((SELECT MAX(TRY_CAST(code AS BIGINT))
                        FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
                        WHERE companyId = @companyId), 0) + 1 AS VARCHAR(100));

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, productCategoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice, trackInventory, isActive)
            SELECT 
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), @nextCode,
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, '$.dateOfExpire'), '')), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'), JSON_VALUE(value, '$.categoryId')) AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, '$.netContent') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, '$.unitOfMeasure'), ''),
                TRY_CAST(JSON_VALUE(value, '$.referencePrice') AS DECIMAL(10,2)),
                -- trackInventory: explicit value wins; otherwise physical goods (barcode / supply) are tracked.
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.trackInventory') AS BIT),
                         CASE WHEN NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.barCode'))), '') IS NOT NULL
                                OR TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT) = 1 THEN 1 ELSE 0 END),
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isActive') AS BIT), 1)
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR('productId is required for update.', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, '$.name'), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, '$.barCode'), p.barCode),
                -- code is never changed after insert (auto-assigned identity)
                p.dateOfExpire = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, '$.noExpire') AS BIT) = 1 THEN NULL
                    ELSE COALESCE(TRY_CONVERT(DATE, NULLIF(JSON_VALUE(j.value, '$.dateOfExpire'), '')), p.dateOfExpire)
                END,
                -- netContent/unitOfMeasure/referencePrice: the wizard always sends all three (null = cleared)
                p.netContent = TRY_CAST(JSON_VALUE(j.value, '$.netContent') AS DECIMAL(10,3)),
                p.unitOfMeasure = NULLIF(JSON_VALUE(j.value, '$.unitOfMeasure'), ''),
                p.referencePrice = TRY_CAST(JSON_VALUE(j.value, '$.referencePrice') AS DECIMAL(10,2)),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.productFormId') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.manufactureId') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, '$.description'), p.description),
                p.updatedAt = GETDATE(),
                p.productCategoryId = COALESCE(TRY_CAST(COALESCE(JSON_VALUE(j.value, '$.productCategoryId'), JSON_VALUE(j.value, '$.categoryId')) AS INT), p.productCategoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isSupply') AS BIT), p.isSupply),
                p.trackInventory = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.trackInventory') AS BIT), p.trackInventory),
                p.isActive = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isActive') AS BIT), p.isActive)
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
            DELETE FROM dbo.inventoryStock WHERE productId = @productId AND companyId = @companyId;
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

        -- productDetails keeps prices only. stockQuantity there is frozen since phase 1
        -- (2026-10-15c): the only stock is dbo.inventoryStock + dbo.inventoryMovements.
        IF EXISTS (SELECT 1 FROM dbo.productDetails WHERE productId = @productId)
        BEGIN
            UPDATE dbo.productDetails
            SET unitPrice = COALESCE(@uPrice, unitPrice),
                salePrice = COALESCE(@sPrice, salePrice),
                updatedAt = GETDATE()
            WHERE productId = @productId;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
            VALUES (@productId, 0, COALESCE(@uPrice, 0), COALESCE(@sPrice, 0), GETDATE(), GETDATE());
        END

        -- The stock typed in the wizard is a target count: post the difference as
        -- 'opening' (first count) or 'adjustment' (recount). A non-zero stock turns
        -- tracking on; a 0 on an untracked product (e.g. made-to-order food) is ignored.
        IF @stock IS NOT NULL
           AND (@stock <> 0 OR EXISTS (SELECT 1 FROM dbo.products
                                       WHERE productId = @productId AND trackInventory = 1))
        BEGIN
            DECLARE @current DECIMAL(18,3), @hasStockRow BIT = 0, @stockUserId INT,
                    @stockDelta DECIMAL(18,3), @stockReason VARCHAR(30);

            SELECT @current = stockQuantity, @hasStockRow = 1
            FROM dbo.inventoryStock WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND productId = @productId;

            SELECT TOP (1) @stockUserId = TRY_CAST(JSON_VALUE(value, '$.userId') AS INT)
            FROM OPENJSON(@pjsonfile, '$.products');

            UPDATE dbo.products SET trackInventory = 1
            WHERE productId = @productId AND trackInventory = 0;

            SET @stockDelta  = @stock - ISNULL(@current, 0);
            SET @stockReason = CASE WHEN @hasStockRow = 1 THEN 'adjustment' ELSE 'opening' END;

            IF @stockDelta <> 0
                EXEC dbo.sp_inventory_post
                    @companyId = @companyId,
                    @productId = @productId,
                    @quantityDelta = @stockDelta,
                    @reason = @stockReason,
                    @refType = 'product_save',
                    @refId = @productId,
                    @userId = @stockUserId,
                    @notes = N'Stock capturado en el asistente de producto';
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
            INSERT INTO dbo.productOptions (productId, optionKey, name, type, isRequired, createdAt, updatedAt)
            SELECT @productId, JSON_VALUE(@pjsonfile, @optPath + '.optionKey'), JSON_VALUE(@pjsonfile, @optPath + '.name'), JSON_VALUE(@pjsonfile, @optPath + '.type'),
                   ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, @optPath + '.isRequired') AS BIT), 0), GETDATE(), GETDATE();
            
            SET @newOptId = SCOPE_IDENTITY();

            -- Insert Nested Choices matching this exact option index
            -- quantity + unit per choice (19 L, 600 ml): measurementId, or the unit code
            -- ("ml", "L", "kg"…) resolved against dbo.measurements.prefix.
            INSERT INTO dbo.productOptionChoices (productOptionId, choiceKey, name, price, description, quantity, measurementId, createdAt, updatedAt)
            SELECT 
                @newOptId,
                JSON_VALUE(value, '$.choiceKey'),
                JSON_VALUE(value, '$.name'),
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.price') AS DECIMAL(10,2)), 0.00),
                COALESCE(JSON_VALUE(value, '$.description'), ''),
                TRY_CAST(JSON_VALUE(value, '$.quantity') AS DECIMAL(10,3)),
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.measurementId') AS INT),
                         (SELECT TOP (1) m.measurementId FROM dbo.measurements m
                          WHERE m.prefix = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.unit'))), ''))),
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

-- 4) Verify --------------------------------------------------------------------------------
SELECT
    CASE WHEN COL_LENGTH('dbo.productOptionChoices', 'quantity')      IS NOT NULL THEN 1 ELSE 0 END AS choiceQuantity,
    CASE WHEN COL_LENGTH('dbo.productOptionChoices', 'measurementId') IS NOT NULL THEN 1 ELSE 0 END AS choiceMeasurementId,
    (SELECT COUNT(*) FROM dbo.measurements) AS units;
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO

-- #############################################################################
-- [67/67] 2026-10-16_gmo_catalog.sql
-- #############################################################################
SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> [67/67] 2026-10-16_gmo_catalog.sql', 0, 1) WITH NOWAIT;
GO

-- =============================================================================
-- GMO Lavandería (companyId 1) — catalog: Categoría → Subcategoría → Producto
-- =============================================================================
-- NOT YET EXECUTED. Data script. Run manually against the live DB AFTER
-- 2026-10-15d_catalog_hierarchy.sql and 2026-10-15e_option_choice_measurements.sql.
-- Idempotent: categories are found-or-created by name, products by name; a
-- second run changes nothing.
--
-- WHAT (company 1 only):
--   1. Top-level categories: Servicios (reuses 1002 "Lavanderia" if not renamed
--      yet), Bebidas, Frituras, Limpieza. 1004 "Productos" is left as is (it keeps
--      the old pseudo-products; delete it from the app once empty).
--   2. Subcategories:
--        Servicios › Lavado, Secado, Servicio completo
--        Bebidas   › Agua purificada, Agua embotellada
--        Limpieza  › Bolsas, Detergentes y limpiadores, Suavizantes
--        Frituras  › (none yet)
--   3. Existing products moved: 1002 Servicio de lavado › Lavado, 1003 Servicio de
--      secado › Secado, 1004 + 2004 › Servicio completo, 3018 Garrafón › Agua
--      purificada. Their "Ciclo" / "Tamaño" options become radio + required; the
--      garrafón sizes get quantity + unit (19 / 10 / 3 L).
--   4. The choices of 1006 "Productos Limpieza" (Jabón, Suavisantes, Limpiadores)
--      become real products at the same price (sold per load: not inventory-
--      tracked), and 1006 is deactivated (kept: past sales point to it).
--   5. 3021 "Bolsas para empaque de ropa" → Limpieza › Bolsas as "Bolsa empaque
--      grande", sellable — ONLY when @bolsaPrecio is set below.
--   NOT TOUCHED: 1005 "Bebidas" (its options are still unknown) — Agua 1 litro /
--   Agua 500 ml come from it in a follow-up.
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.productCategories', 'parentCategoryId') IS NULL
   OR COL_LENGTH('dbo.productOptionChoices', 'measurementId') IS NULL
    BEGIN RAISERROR('Run 2026-10-15d_catalog_hierarchy.sql and 2026-10-15e_option_choice_measurements.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ▼▼▼ Fill in, then run. NULL = step 5 is skipped (the bag stays a supply). ▼▼▼
DECLARE @bolsaPrecio DECIMAL(10,2) = NULL;   -- e.g. 15.00
-- ▲▲▲

DECLARE @companyId INT = 1;

BEGIN TRANSACTION;

-- 1) + 2) Categories ------------------------------------------------------------------------
DECLARE @cat TABLE (name VARCHAR(50) PRIMARY KEY, parentName VARCHAR(50) NULL, ord INT);
INSERT INTO @cat (name, parentName, ord) VALUES
    ('Servicios', NULL, 1), ('Bebidas', NULL, 2), ('Frituras', NULL, 3), ('Limpieza', NULL, 4),
    ('Lavado', 'Servicios', 11), ('Secado', 'Servicios', 12), ('Servicio completo', 'Servicios', 13),
    ('Agua purificada', 'Bebidas', 21), ('Agua embotellada', 'Bebidas', 22),
    ('Bolsas', 'Limpieza', 41), ('Detergentes y limpiadores', 'Limpieza', 42), ('Suavizantes', 'Limpieza', 43);

-- Servicios = the existing laundry category (1002) when it still has its old name.
IF NOT EXISTS (SELECT 1 FROM dbo.productCategories WHERE companyId = @companyId AND name = 'Servicios' AND parentCategoryId IS NULL)
   AND EXISTS (SELECT 1 FROM dbo.productCategories WHERE productCategoryId = 1002 AND companyId = @companyId AND name = 'Lavanderia')
    UPDATE dbo.productCategories SET name = 'Servicios' WHERE productCategoryId = 1002;

INSERT INTO dbo.productCategories (name, image, companyId, parentCategoryId)
SELECT c.name, NULL, @companyId, NULL
FROM @cat c
WHERE c.parentName IS NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.productCategories pc
                  WHERE pc.companyId = @companyId AND pc.name = c.name AND pc.parentCategoryId IS NULL);

INSERT INTO dbo.productCategories (name, image, companyId, parentCategoryId)
SELECT c.name, NULL, @companyId, p.productCategoryId
FROM @cat c
JOIN dbo.productCategories p
  ON p.companyId = @companyId AND p.name = c.parentName AND p.parentCategoryId IS NULL
WHERE c.parentName IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.productCategories pc
                  WHERE pc.companyId = @companyId AND pc.name = c.name AND pc.parentCategoryId = p.productCategoryId);

-- id of a subcategory by (parent, name)
DECLARE @sub TABLE (name VARCHAR(50) PRIMARY KEY, id INT NOT NULL);
INSERT INTO @sub (name, id)
SELECT s.name, s.productCategoryId
FROM dbo.productCategories s
JOIN dbo.productCategories p ON p.productCategoryId = s.parentCategoryId
JOIN @cat c ON c.name = s.name AND c.parentName = p.name
WHERE s.companyId = @companyId;

-- 3) Existing products → subcategories; options radio + required --------------------------
UPDATE p SET p.productCategoryId = s.id, p.updatedAt = GETDATE()
FROM dbo.products p
JOIN (VALUES (1002, 'Lavado'), (1003, 'Secado'), (1004, 'Servicio completo'),
             (2004, 'Servicio completo'), (3018, 'Agua purificada')) AS m(productId, subName)
  ON m.productId = p.productId
JOIN @sub s ON s.name = m.subName
WHERE p.companyId = @companyId
  AND ISNULL(p.productCategoryId, 0) <> s.id;

UPDATE o SET o.type = 'radio', o.isRequired = 1, o.updatedAt = GETDATE()
FROM dbo.productOptions o
JOIN dbo.products p ON p.productId = o.productId
WHERE p.companyId = @companyId
  AND p.productId IN (1002, 1003, 1004, 2004, 3018)
  AND o.name IN (N'Ciclo', N'Tamaño', N'Tamano')
  AND (o.type <> 'radio' OR o.isRequired = 0);

-- Garrafón sizes: "19 lts" → 19 L
UPDATE c SET c.quantity = TRY_CAST(LEFT(c.name, CHARINDEX(' ', c.name + ' ') - 1) AS DECIMAL(10,3)),
             c.measurementId = m.measurementId,
             c.updatedAt = GETDATE()
FROM dbo.productOptionChoices c
JOIN dbo.productOptions o ON o.productOptionId = c.productOptionId
JOIN dbo.measurements m ON m.prefix = 'L'
WHERE o.productId = 3018
  AND (c.name LIKE '% lts' OR c.name LIKE '% lt' OR c.name LIKE '% L')
  AND TRY_CAST(LEFT(c.name, CHARINDEX(' ', c.name + ' ') - 1) AS DECIMAL(10,3)) > 0
  AND (c.quantity IS NULL OR c.measurementId IS NULL);

-- 4) 1006 "Productos Limpieza" choices → real products ------------------------------------
DECLARE @new TABLE (name NVARCHAR(255) PRIMARY KEY, subName VARCHAR(50), price DECIMAL(10,2));
INSERT INTO @new (name, subName, price)
SELECT DISTINCT
    CASE
        WHEN o.name LIKE N'Jab%n' THEN N'Jabón ' + c.name
        -- "Suavisante Generico" → "Suavizante Generico"; brands (Suavitel, Ensueño) keep their name
        WHEN o.name LIKE N'Suavi%' AND c.name LIKE N'Suavi_ante %'
            THEN N'Suavizante ' + LTRIM(SUBSTRING(c.name, CHARINDEX(' ', c.name) + 1, 200))
        ELSE c.name
    END,
    CASE WHEN o.name LIKE N'Suavi%' THEN 'Suavizantes' ELSE 'Detergentes y limpiadores' END,
    c.price
FROM dbo.productOptions o
JOIN dbo.productOptionChoices c ON c.productOptionId = o.productOptionId
WHERE o.productId = 1006;

DECLARE @nextCode BIGINT = ISNULL((SELECT MAX(TRY_CAST(code AS BIGINT)) FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
                                   WHERE companyId = @companyId), 0);
DECLARE @created TABLE (productId INT);

INSERT INTO dbo.products (name, code, description, createdAt, productCategoryId, companyId,
                          isSupply, trackInventory, isActive)
OUTPUT inserted.productId INTO @created (productId)
SELECT n.name,
       CAST(@nextCode + ROW_NUMBER() OVER (ORDER BY n.subName, n.name) AS VARCHAR(100)),
       N'Por carga', GETDATE(), s.id, @companyId,
       0, 0, 1          -- sold per load from bulk: not inventory-tracked
FROM @new n
JOIN @sub s ON s.name = n.subName
WHERE NOT EXISTS (SELECT 1 FROM dbo.products p WHERE p.companyId = @companyId AND p.name = n.name);

INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
SELECT p.productId, 0, 0, n.price, GETDATE(), GETDATE()
FROM @created c
JOIN dbo.products p ON p.productId = c.productId
JOIN @new n ON n.name = p.name;

UPDATE dbo.products SET isActive = 0, updatedAt = GETDATE()
WHERE productId = 1006 AND companyId = @companyId AND isActive = 1
  AND (SELECT COUNT(*) FROM @new) > 0;

-- 5) Bag → sellable product (only with a price) ---------------------------------------------
IF @bolsaPrecio IS NOT NULL
BEGIN
    UPDATE p SET p.name = N'Bolsa empaque grande', p.productCategoryId = s.id,
                 p.isSupply = 0, p.isActive = 1, p.updatedAt = GETDATE()
    FROM dbo.products p
    JOIN @sub s ON s.name = 'Bolsas'
    WHERE p.productId = 3021 AND p.companyId = @companyId;

    IF EXISTS (SELECT 1 FROM dbo.productDetails WHERE productId = 3021)
        UPDATE dbo.productDetails SET salePrice = @bolsaPrecio, updatedAt = GETDATE() WHERE productId = 3021;
    ELSE
        INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
        VALUES (3021, 0, 0, @bolsaPrecio, GETDATE(), GETDATE());
END
ELSE
    RAISERROR('Bolsa empaque grande skipped: set @bolsaPrecio and run again.', 0, 1) WITH NOWAIT;

COMMIT TRANSACTION;
SET XACT_ABORT OFF;

-- Verify --------------------------------------------------------------------------------------
SELECT ISNULL(parent.name + N' › ', N'') + c.name AS category, c.productCategoryId,
       (SELECT COUNT(*) FROM dbo.products p WHERE p.productCategoryId = c.productCategoryId AND p.isActive = 1) AS activeProducts
FROM dbo.productCategories c
LEFT JOIN dbo.productCategories parent ON parent.productCategoryId = c.parentCategoryId
WHERE c.companyId = 1
ORDER BY ISNULL(parent.name, c.name), CASE WHEN c.parentCategoryId IS NULL THEN 0 ELSE 1 END, c.name;

SELECT p.productId, p.name, cat.name AS subcategory, d.salePrice, p.isActive, p.isSupply, p.trackInventory
FROM dbo.products p
LEFT JOIN dbo.productCategories cat ON cat.productCategoryId = p.productCategoryId
OUTER APPLY (SELECT TOP 1 salePrice FROM dbo.productDetails WHERE productId = p.productId ORDER BY productDetailId) d
WHERE p.companyId = 1
ORDER BY cat.name, p.name;
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO

SET NOEXEC OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT OFF;
IF OBJECT_ID('tempdb..#rec') IS NOT NULL DROP TABLE #rec;
IF @@TRANCOUNT > 0
BEGIN
    ROLLBACK TRANSACTION;
    RAISERROR('Previous step left an open transaction — rolled back.', 16, 1);
END
GO
RAISERROR('>>> DONE: 67/67 migration files executed.', 0, 1) WITH NOWAIT;
GO
