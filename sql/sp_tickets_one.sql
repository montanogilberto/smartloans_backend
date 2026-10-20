-- sp_tickets_one — ticket JSON for one sale.
-- 2026-10-20: line subtotal multiplies option prices by the line quantity
-- unless the option quantities already add up to it; IVA is always 0.
CREATE OR ALTER PROC [dbo].[sp_tickets_one]
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
      ), 0) AS DECIMAL(10,2)) AS optionsTotal,

      -- Sum of option quantities. When it equals the line quantity the
      -- options already carry the count (Garrafon: 60x19L + 16x10L + 2x3L
      -- on a qty-78 line); otherwise one choice prices one unit of the line
      -- (2 x Servicio Completo / Basico = 2 x 160).
      ISNULL((
        SELECT SUM(ISNULL(ido.quantity, 1))
        FROM dbo.incomeDetailOptions ido
        WHERE ido.incomeDetailId = id.incomeDetailId
      ), 0) AS optionsQty
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
    CAST((unitPrice * quantity) +
         CASE WHEN optionsQty = 0 OR optionsQty = quantity
              THEN optionsTotal
              ELSE optionsTotal * quantity
         END AS DECIMAL(10,2)) AS lineSubtotal
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

  -- POS prices are final: no IVA is charged on top. (It used to be
  -- total - subtotal, which turned any line-pricing gap into fake IVA.)
  SET @iva = 0;

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
