-- ROLLBACK for 2026-09-23_ticket_discount_fields.sql

-- ── Remove the seeded 2X1 promotion row ──
DELETE FROM dbo.promotions WHERE companyId = 1 AND code = '2X1';
GO

-- ── Restore sp_tickets_one to its pre-2026-09-23 definition ──
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
    @paymentMethod  NVARCHAR(50),
    @paymentDate    DATETIME,
    @userId         INT,
    @clientId       INT,
    @companyId      INT,
    @incomeTotal    DECIMAL(10,2),
    @cashPaid       DECIMAL(10,2),
    @cashReturn     DECIMAL(10,2);

  SELECT
    @paymentMethod = i.paymentMethod,
    @paymentDate   = DATEADD(HOUR, -7, i.paymentDate),  -- FIX: UTC -> Hermosillo (UTC-7)
    @userId        = i.userId,
    @clientId      = i.clientId,
    @companyId     = i.companyId,
    @incomeTotal   = i.total,
    @cashPaid      = i.cashPaid,
    @cashReturn    = i.cashReturn
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
    @total    DECIMAL(10,2);

  SET @subtotal = ISNULL((SELECT SUM(lineSubtotal) FROM #TicketProducts), 0);

  -- Prefer stored income total if present
  SET @total = COALESCE(@incomeTotal, @subtotal);

  -- IVA derived from stored total - subtotal (if included)
  SET @iva = CASE
    WHEN @total >= @subtotal THEN ROUND(@total - @subtotal, 2)
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
