-- ─────────────────────────────────────────────────────────────────────────────
-- sp_whatsappAgentConversations — what each customer wrote to the WhatsApp
-- agent and what it answered, read-only (POS "Agente WhatsApp" › Conversaciones).
-- Sources (nothing new is written), same as sp_whatsappAgentDashboard:
--   dbo.integrationLogs  service 'loanagents_smartloans', operation
--                        'whatsapp_reservations' — one row per agent turn:
--                        requestSummary {phone, customerName, message, ...},
--                        responseSummary {reply, pendingAction{capability, fields}}.
--                        companyId set since 2026-10-20.
--   dbo.reservations     source = 'whatsapp' — the bookings the "sí" created.
-- Not in these sources: the customer's plain "sí"/"no" to a proposal (the
-- backend answers it without the agent — the booking shows instead), messages
-- while a person has the chat, BAJA/ALTA. A failed turn has no reply logged
-- (the customer got the generic fallback text).
-- A customer = last 10 digits of the phone (same key as reservations/clients).
-- Days are Hermosillo days (UTC-7, no DST); timestamps returned are UTC.
--
-- action "list"   { companyId, startDate?, endDate?, search? }   (default: last 30 days)
--   → { result: [{ period, conversations: [{ phone10, customerName, turns, failures,
--        firstAtUtc, lastAtUtc, lastMessage, lastReply, handedOff, proposed, bookings }] }] }
--   search matches name, phone or message text. Newest conversation first, max 200.
-- action "thread" { companyId, phone10, startDate?, endDate? }   (default: last 90 days)
--   → { result: [{ phone10, customerName, turns: [{ atUtc, message, reply, ok, latencyMs,
--        capability, actionNote }], bookings: [{ reservationId, atUtc, status,
--        reservationDate, timeSlot, serviceType }] }] }   (oldest first, max 500 turns)
-- Input envelope: { "whatsappAgentConversations": [{ "action": "list"|"thread", ... }] }
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_whatsappAgentConversations', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_whatsappAgentConversations;
GO
CREATE PROCEDURE [dbo].[sp_whatsappAgentConversations]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    NVARCHAR(10) = JSON_VALUE(@pjsonfile, '$.whatsappAgentConversations[0].action');
        DECLARE @companyId INT  = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.whatsappAgentConversations[0].companyId'));
        DECLARE @phone10   NVARCHAR(10) = RIGHT(JSON_VALUE(@pjsonfile, '$.whatsappAgentConversations[0].phone10'), 10);
        DECLARE @search    NVARCHAR(100) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@pjsonfile, '$.whatsappAgentConversations[0].search'))), '');
        DECLARE @today     DATE = CONVERT(DATE, DATEADD(HOUR, -7, SYSUTCDATETIME()));
        DECLARE @endDate   DATE = ISNULL(TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.whatsappAgentConversations[0].endDate')), @today);
        DECLARE @startDate DATE = ISNULL(TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.whatsappAgentConversations[0].startDate')),
                                         DATEADD(DAY, CASE WHEN @action = 'thread' THEN -89 ELSE -29 END, @endDate));

        IF @companyId IS NULL OR @action NOT IN ('list', 'thread')
           OR (@action = 'thread' AND (ISNULL(@phone10, '') = '' OR @phone10 LIKE '%[^0-9]%'))
        BEGIN
            SELECT '{"error":"companyId and action (list|thread) are required; thread needs phone10 (digits)"}' AS jsonResult;
            RETURN;
        END

        DECLARE @fromUtc DATETIME2 = DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2));
        DECLARE @toUtc   DATETIME2 = DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2));

        -- One row per agent turn in the window.
        DECLARE @turns TABLE (integrationLogId BIGINT, phone10 NVARCHAR(10), customerName NVARCHAR(200),
                              message NVARCHAR(MAX), reply NVARCHAR(MAX), ok BIT, latencyMs INT,
                              capability NVARCHAR(40), actionNote NVARCHAR(400), atUtc DATETIME2);
        INSERT INTO @turns
        SELECT l.integrationLogId,
               RIGHT(REPLACE(REPLACE(REPLACE(JSON_VALUE(q.j, '$.phone'), '+', ''), ' ', ''), '-', ''), 10),
               JSON_VALUE(q.j, '$.customerName'),
               JSON_VALUE(q.j, '$.message'),
               JSON_VALUE(r.j, '$.reply'),
               CASE WHEN l.status = 'SUCCESS' THEN 1 ELSE 0 END,
               l.latencyMs,
               JSON_VALUE(r.j, '$.pendingAction.capability'),
               COALESCE(JSON_VALUE(r.j, '$.pendingAction.confirmationSummary'),
                        JSON_VALUE(r.j, '$.pendingAction.fields.reason')),
               l.created_At
        FROM [dbo].[integrationLogs] l
        CROSS APPLY (SELECT CASE WHEN ISJSON(l.requestSummary) = 1 THEN l.requestSummary END AS j) q
        CROSS APPLY (SELECT CASE WHEN ISJSON(l.responseSummary) = 1 THEN l.responseSummary END AS j) r
        WHERE l.service = 'loanagents_smartloans' AND l.operation = 'whatsapp_reservations'
          AND l.companyId = @companyId
          AND l.created_At >= @fromUtc AND l.created_At < @toUtc;

        DELETE FROM @turns WHERE ISNULL(phone10, '') = '';
        IF @action = 'thread' DELETE FROM @turns WHERE phone10 <> @phone10;

        DECLARE @bookings TABLE (reservationId INT, phone10 NVARCHAR(10), status NVARCHAR(20), atUtc DATETIME2,
                                 reservationDate DATE, timeSlot NVARCHAR(20), serviceType NVARCHAR(200));
        INSERT INTO @bookings
        SELECT reservationId,
               RIGHT(REPLACE(REPLACE(REPLACE(phone, '+', ''), ' ', ''), '-', ''), 10),
               status, created_At, reservationDate, timeSlot, serviceType
        FROM [dbo].[reservations]
        WHERE companyId = @companyId AND source = 'whatsapp'
          AND created_At >= @fromUtc AND created_At < @toUtc;

        IF @action = 'list'
        BEGIN
            DECLARE @list NVARCHAR(MAX) = (
                SELECT TOP (200)
                       c.phone10,
                       (SELECT TOP 1 t.customerName FROM @turns t
                         WHERE t.phone10 = c.phone10 AND ISNULL(t.customerName, '') <> ''
                         ORDER BY t.atUtc DESC)                                            AS customerName,
                       c.turns, c.failures,
                       CONVERT(NVARCHAR(19), c.firstAtUtc, 126)                            AS firstAtUtc,
                       CONVERT(NVARCHAR(19), c.lastAtUtc, 126)                             AS lastAtUtc,
                       (SELECT TOP 1 LEFT(t.message, 160) FROM @turns t
                         WHERE t.phone10 = c.phone10 ORDER BY t.atUtc DESC)                AS lastMessage,
                       (SELECT TOP 1 LEFT(t.reply, 160) FROM @turns t
                         WHERE t.phone10 = c.phone10 ORDER BY t.atUtc DESC)                AS lastReply,
                       c.handedOff, c.proposed,
                       (SELECT COUNT(*) FROM @bookings b
                         WHERE b.phone10 = c.phone10 AND b.status <> 'cancelled')          AS bookings
                FROM (SELECT phone10, COUNT(*) AS turns, SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END) AS failures,
                             MIN(atUtc) AS firstAtUtc, MAX(atUtc) AS lastAtUtc,
                             MAX(CASE WHEN capability = 'REQUEST_HUMAN' THEN 1 ELSE 0 END) AS handedOff,
                             MAX(CASE WHEN capability = 'CREATE_RESERVATION' THEN 1 ELSE 0 END) AS proposed
                      FROM @turns GROUP BY phone10) c
                WHERE @search IS NULL
                   OR c.phone10 LIKE '%' + @search + '%'
                   OR EXISTS (SELECT 1 FROM @turns t WHERE t.phone10 = c.phone10
                                AND (t.customerName LIKE '%' + @search + '%' OR t.message LIKE '%' + @search + '%'))
                ORDER BY c.lastAtUtc DESC
                FOR JSON PATH, INCLUDE_NULL_VALUES
            );
            SELECT ('{"result":[{'
                  + '"period":{"startDate":"' + CONVERT(NVARCHAR(10), @startDate, 23)
                  + '","endDate":"' + CONVERT(NVARCHAR(10), @endDate, 23) + '"}'
                  + ',"conversations":' + ISNULL(@list, '[]')
                  + '}]}') AS jsonResult;
            RETURN;
        END

        DECLARE @thread NVARCHAR(MAX) = (
            SELECT TOP (500)
                   CONVERT(NVARCHAR(19), atUtc, 126) AS atUtc, message, reply, ok, latencyMs, capability, actionNote
            FROM @turns ORDER BY atUtc, integrationLogId
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        DECLARE @threadBookings NVARCHAR(MAX) = (
            SELECT reservationId, CONVERT(NVARCHAR(19), atUtc, 126) AS atUtc, status,
                   CONVERT(NVARCHAR(10), reservationDate, 23) AS reservationDate, timeSlot, serviceType
            FROM @bookings WHERE phone10 = @phone10 ORDER BY atUtc
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        DECLARE @name NVARCHAR(200) = (SELECT TOP 1 customerName FROM @turns
                                       WHERE ISNULL(customerName, '') <> '' ORDER BY atUtc DESC);
        SELECT ('{"result":[{'
              + '"phone10":"' + @phone10 + '"'
              + ',"customerName":' + ISNULL('"' + STRING_ESCAPE(@name, 'json') + '"', 'null')
              + ',"turns":' + ISNULL(@thread, '[]')
              + ',"bookings":' + ISNULL(@threadBookings, '[]')
              + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS jsonResult;
    END CATCH
END
GO
