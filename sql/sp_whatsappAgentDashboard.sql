-- ─────────────────────────────────────────────────────────────────────────────
-- sp_whatsappAgentDashboard — how the WhatsApp agent is doing for one company,
-- read-only (POS "Agente WhatsApp"). One call, one JSON:
--   kpis      messages the agent answered, failed calls, latency, customers
--             who wrote, handoffs to a person, booking proposals, WhatsApp
--             bookings, and customers who bought within the attribution window
--             after their first message (a sale AFTER talking, not caused BY it)
--   funnel    customers → got a proposal → booked → bought
--   daily     per Hermosillo day: messages, customers, failures, handoffs, bookings
--   dataSince first day each source has data — earlier days can't be measured
-- Sources (nothing new is written):
--   dbo.integrationLogs  service 'loanagents_smartloans', operation
--                        'whatsapp_reservations' — one row per agent call; companyId
--                        set since 2026-10-20 (rows before have NULL and are not counted)
--   dbo.reservations     source = 'whatsapp' (column added 2026-10-20)
--   dbo.clients/income   phone (last 10 digits) → client → sales; same match as
--                        sp_whatsappCustomerRewards
-- Days are Hermosillo days (UTC-7, no DST): log/reservation timestamps are UTC,
-- income.paymentDate is already local.
-- Input:  { "whatsappAgentDashboard": [{ "companyId": int,
--           "startDate"?: "YYYY-MM-DD", "endDate"?: "YYYY-MM-DD",
--           "attributionDays"?: int (default 14) }] }   (default: last 30 days)
-- Output: { "result": [{ "period", "kpis", "funnel", "daily", "dataSince" }] }
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_whatsappAgentDashboard', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_whatsappAgentDashboard;
GO
CREATE PROCEDURE [dbo].[sp_whatsappAgentDashboard]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT  = TRY_CONVERT(INT,  JSON_VALUE(@pjsonfile, '$.whatsappAgentDashboard[0].companyId'));
        DECLARE @today     DATE = CONVERT(DATE, DATEADD(HOUR, -7, SYSUTCDATETIME()));
        DECLARE @endDate   DATE = ISNULL(TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.whatsappAgentDashboard[0].endDate')), @today);
        DECLARE @startDate DATE = ISNULL(TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.whatsappAgentDashboard[0].startDate')),
                                         DATEADD(DAY, -29, @endDate));
        DECLARE @window    INT  = ISNULL(TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.whatsappAgentDashboard[0].attributionDays')), 14);
        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END
        IF @window < 1 OR @window > 90 SET @window = 14;

        DECLARE @fromUtc DATETIME2 = DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2));
        DECLARE @toUtc   DATETIME2 = DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2));

        -- One row per agent call. phone10 = last 10 digits, the key shared with
        -- reservations and clients.
        DECLARE @calls TABLE (phone10 NVARCHAR(10), ok BIT, latencyMs INT, capability NVARCHAR(40),
                              localAt DATETIME2, day DATE);
        INSERT INTO @calls
        SELECT RIGHT(REPLACE(REPLACE(REPLACE(
                   CASE WHEN ISJSON(requestSummary) = 1 THEN JSON_VALUE(requestSummary, '$.phone') END,
                   '+', ''), ' ', ''), '-', ''), 10),
               CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END,
               latencyMs,
               CASE WHEN ISJSON(responseSummary) = 1 THEN JSON_VALUE(responseSummary, '$.pendingAction.capability') END,
               DATEADD(HOUR, -7, created_At),
               CONVERT(DATE, DATEADD(HOUR, -7, created_At))
        FROM [dbo].[integrationLogs]
        WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
          AND companyId = @companyId
          AND created_At >= @fromUtc AND created_At < @toUtc;

        DECLARE @bookings TABLE (reservationId INT, phone10 NVARCHAR(10), status NVARCHAR(20), day DATE);
        INSERT INTO @bookings
        SELECT reservationId,
               RIGHT(REPLACE(REPLACE(REPLACE(phone, '+', ''), ' ', ''), '-', ''), 10),
               status,
               CONVERT(DATE, DATEADD(HOUR, -7, created_At))
        FROM [dbo].[reservations]
        WHERE companyId = @companyId AND source = 'whatsapp'
          AND created_At >= @fromUtc AND created_At < @toUtc;

        -- Customers who wrote, with their first message of the period.
        DECLARE @customers TABLE (phone10 NVARCHAR(10) PRIMARY KEY, firstAt DATETIME2,
                                  proposed BIT, handedOff BIT);
        INSERT INTO @customers
        SELECT phone10, MIN(localAt),
               MAX(CASE WHEN capability = 'CREATE_RESERVATION' THEN 1 ELSE 0 END),
               MAX(CASE WHEN capability = 'REQUEST_HUMAN' THEN 1 ELSE 0 END)
        FROM @calls WHERE phone10 IS NOT NULL AND phone10 <> ''
        GROUP BY phone10;

        -- Sales by those customers within the window after their first message.
        -- Walk-in placeholder "Desconocido" excluded (may carry a staff phone).
        DECLARE @sales TABLE (phone10 NVARCHAR(10), incomeId INT, total DECIMAL(12,2));
        INSERT INTO @sales
        SELECT DISTINCT cu.phone10, i.incomeId, i.total
        FROM @customers cu
        JOIN [dbo].[clients] c
          ON c.companyId = @companyId AND c.isActive = 1 AND c.first_name <> N'Desconocido'
         AND RIGHT(REPLACE(REPLACE(REPLACE(c.cellphone, '+', ''), ' ', ''), '-', ''), 10) = cu.phone10
        JOIN [dbo].[income] i
          ON i.companyId = @companyId AND i.clientId = c.clientId
         AND i.paymentDate >= cu.firstAt
         AND i.paymentDate <  DATEADD(DAY, @window, cu.firstAt);

        DECLARE @nCalls INT = (SELECT COUNT(*) FROM @calls);
        DECLARE @nFailed INT = (SELECT COUNT(*) FROM @calls WHERE ok = 0);

        DECLARE @p95 INT = (
            SELECT TOP 1 CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latencyMs) OVER () AS INT)
            FROM @calls WHERE ok = 1 AND latencyMs IS NOT NULL);

        DECLARE @kpis NVARCHAR(MAX) = (
            SELECT
                @nCalls - @nFailed                                                        AS messagesAnswered,
                @nFailed                                                                  AS failedCalls,
                CASE WHEN @nCalls > 0 THEN CAST(100.0 * @nFailed / @nCalls AS DECIMAL(5,1)) END AS failureRatePct,
                (SELECT AVG(latencyMs) FROM @calls WHERE ok = 1)                          AS avgLatencyMs,
                @p95                                                                      AS p95LatencyMs,
                (SELECT COUNT(*) FROM @customers)                                         AS customers,
                (SELECT COUNT(*) FROM @customers WHERE handedOff = 1)                     AS handoffs,
                (SELECT COUNT(*) FROM @calls WHERE capability = 'CREATE_RESERVATION')     AS proposals,
                (SELECT COUNT(*) FROM @bookings WHERE status <> 'cancelled')              AS bookings,
                (SELECT COUNT(*) FROM @bookings WHERE status = 'cancelled')               AS bookingsCancelled,
                (SELECT COUNT(DISTINCT phone10) FROM @sales)                              AS customersWhoBought,
                ISNULL((SELECT SUM(total) FROM @sales), 0)                                AS salesAfterChat,
                @window                                                                   AS attributionDays
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );

        DECLARE @funnel NVARCHAR(MAX) = (
            SELECT
                (SELECT COUNT(*) FROM @customers)                                         AS customers,
                (SELECT COUNT(*) FROM @customers WHERE proposed = 1)                      AS gotProposal,
                (SELECT COUNT(DISTINCT b.phone10) FROM @bookings b
                  JOIN @customers cu ON cu.phone10 = b.phone10 WHERE b.status <> 'cancelled') AS booked,
                (SELECT COUNT(DISTINCT phone10) FROM @sales)                              AS bought
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        DECLARE @daily NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(10), d.day, 23) AS date,
                   ISNULL(c.messages, 0) AS messages, ISNULL(c.customers, 0) AS customers,
                   ISNULL(c.failures, 0) AS failures, ISNULL(c.handoffs, 0) AS handoffs,
                   ISNULL(b.bookings, 0) AS bookings
            FROM (SELECT day FROM @calls UNION SELECT day FROM @bookings) d
            LEFT JOIN (SELECT day, SUM(CAST(ok AS INT)) AS messages, COUNT(DISTINCT phone10) AS customers,
                              SUM(1 - CAST(ok AS INT)) AS failures,
                              SUM(CASE WHEN capability = 'REQUEST_HUMAN' THEN 1 ELSE 0 END) AS handoffs
                       FROM @calls GROUP BY day) c ON c.day = d.day
            LEFT JOIN (SELECT day, SUM(CASE WHEN status <> 'cancelled' THEN 1 ELSE 0 END) AS bookings
                       FROM @bookings GROUP BY day) b ON b.day = d.day
            ORDER BY d.day
            FOR JSON PATH
        );

        DECLARE @dataSince NVARCHAR(MAX) = (
            SELECT
                (SELECT CONVERT(NVARCHAR(10), CONVERT(DATE, DATEADD(HOUR, -7, MIN(created_At))), 23)
                 FROM [dbo].[integrationLogs]
                 WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
                   AND companyId = @companyId)                                            AS agentCalls,
                (SELECT CONVERT(NVARCHAR(10), CONVERT(DATE, DATEADD(HOUR, -7, MIN(created_At))), 23)
                 FROM [dbo].[reservations]
                 WHERE companyId = @companyId AND source IS NOT NULL)                     AS bookings
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );

        SELECT ('{"result":[{'
              + '"period":{"startDate":"' + CONVERT(NVARCHAR(10), @startDate, 23)
              + '","endDate":"' + CONVERT(NVARCHAR(10), @endDate, 23) + '"}'
              + ',"kpis":' + @kpis
              + ',"funnel":' + @funnel
              + ',"daily":' + ISNULL(@daily, '[]')
              + ',"dataSince":' + @dataSince
              + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS jsonResult;
    END CATCH
END
GO
