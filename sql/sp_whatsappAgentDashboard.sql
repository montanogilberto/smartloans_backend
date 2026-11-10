-- ─────────────────────────────────────────────────────────────────────────────
-- sp_whatsappAgentDashboard — how the WhatsApp agent is doing for one company,
-- read-only (POS "Agente WhatsApp"). One call, one JSON:
--   kpis      messages the agent answered, failed calls, latency, customers
--             who wrote, handoffs to a person, booking proposals, WhatsApp
--             bookings, and customers who bought within the attribution window
--             after their first message (a sale AFTER talking, not caused BY it)
--   funnel    customers → got a proposal → booked → bought
--   daily     per Hermosillo day: messages, customers, failures, handoffs, bookings
--   topics    what customers asked: the topic agent's tag per message (LoanAgents
--             agents/whatsapp_topic TOPICS, in responseSummary.topic since it was deployed)
--   hours     when: messages per Hermosillo weekday (0 = lunes) × hour
--   branches  where: per business number / branch the customer wrote to
--   quality   did each chat END correctly: per conversation (customer×day) an outcome —
--             cerrada / le_sirvio (finalized) · no_le_sirvio / falla_agente / pidio_persona /
--             sin_cierre — from the agent's closing flow ("¿Te funcionó la respuesta?",
--             "¿Hay algo más…?", answered 1/2 or sí/no), plus the list of unfinished chats,
--             re-asked topics, complaints and new customers.
--             "finalized" = the chat ENDED (a goodbye or a booking) — not that it helped.
--             Whether it helped is "resolution" (LoanAgents responseSummary.outcome,
--             since 2026-11-09): resolved_explicit / resolved_implicit / not_helped /
--             escalated / agent_failure / ended_no_result / no_result
--   dataSince first day each source has data — earlier days can't be measured
--             (outcomes: before it, only answers to "¿Te funcionó?" count for resolution)
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
-- Output: { "result": [{ "period", "kpis", "funnel", "daily", "topics", "hours", "branches",
--                        "quality", "dataSince" }] }
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
                              localAt DATETIME2, day DATE, topic NVARCHAR(30),
                              branchId INT, branchName NVARCHAR(100), logId BIGINT,
                              customerName NVARCHAR(120), message NVARCHAR(300),
                              askedHelpful BIT, askedMore BIT, answer NVARCHAR(3),
                              stage NVARCHAR(30), feedback NVARCHAR(3), outcome NVARCHAR(20));
        INSERT INTO @calls
        SELECT RIGHT(REPLACE(REPLACE(REPLACE(JSON_VALUE(q.j, '$.phone'), '+', ''), ' ', ''), '-', ''), 10),
               CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END,
               latencyMs,
               JSON_VALUE(r.j, '$.pendingAction.capability'),
               DATEADD(HOUR, -7, created_At),
               CONVERT(DATE, DATEADD(HOUR, -7, created_At)),
               JSON_VALUE(r.j, '$.topic'),
               TRY_CONVERT(INT, JSON_VALUE(q.j, '$.branchId')),
               JSON_VALUE(q.j, '$.branchName'),
               integrationLogId,
               LEFT(JSON_VALUE(q.j, '$.customerName'), 120),
               LEFT(JSON_VALUE(q.j, '$.message'), 300),
               -- The agent's closing flow. Since LoanAgents#14 the route returns conversationStage
               -- (computed by code, not the model); older rows fall back to its fixed questions.
               CASE WHEN JSON_VALUE(r.j, '$.conversationStage') = 'feedback_asked'
                      OR JSON_VALUE(r.j, '$.reply') LIKE N'%¿Te funcionó la respuesta?%' THEN 1 ELSE 0 END,
               CASE WHEN JSON_VALUE(r.j, '$.conversationStage') = 'more_asked'
                      OR JSON_VALUE(r.j, '$.reply') LIKE N'%¿Hay algo más en lo que te pueda ayudar?%' THEN 1 ELSE 0 END,
               -- The customer's short yes / no (or the menu number).
               CASE WHEN n.t IN (N'1', N'si', N'sí', N'sii', N'sip', N'claro', N'ok', N'okay', N'va', N'gracias',
                                 N'si gracias', N'sí gracias', N'muchas gracias', N'perfecto', N'listo', N'excelente')
                         OR n.t LIKE N'si %' OR n.t LIKE N'sí %' OR n.t LIKE N'1 %' THEN 'yes'
                    WHEN n.t IN (N'2', N'no', N'nop', N'nel', N'no gracias', N'ninguna', N'nada', N'es todo',
                                 N'eso es todo', N'nada mas', N'nada más')
                         OR n.t LIKE N'no %' OR n.t LIKE N'2 %' THEN 'no' END,
               JSON_VALUE(r.j, '$.conversationStage'),
               -- The customer's answer to "¿Te funcionó?", set by the route on the answering turn.
               JSON_VALUE(r.j, '$.feedback'),
               -- How the customer took the previous reply (route, since 2026-11-09):
               -- explicit_positive / implicit_positive / explicit_negative / escalated / NULL.
               JSON_VALUE(r.j, '$.outcome')
        FROM [dbo].[integrationLogs]
        CROSS APPLY (SELECT CASE WHEN ISJSON(requestSummary) = 1 THEN requestSummary END AS j) q
        CROSS APPLY (SELECT CASE WHEN ISJSON(responseSummary) = 1 THEN responseSummary END AS j) r
        CROSS APPLY (SELECT LOWER(LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                         ISNULL(JSON_VALUE(q.j, '$.message'), ''), '.', ''), '!', ''), N'¡', ''), ',', ''), '?', ''), N'¿', '')))) AS t) n
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

        -- ── What: the topic agent's tag per customer message (responseSummary.topic) ──
        DECLARE @topics NVARCHAR(MAX) = (
            SELECT topic, COUNT(*) AS messages, COUNT(DISTINCT phone10) AS customers
            FROM @calls WHERE topic IS NOT NULL
            GROUP BY topic
            ORDER BY COUNT(*) DESC
            FOR JSON PATH
        );

        -- ── When: messages per Hermosillo weekday (0 = lunes) × hour ──
        DECLARE @hours NVARCHAR(MAX) = (
            SELECT (DATEDIFF(DAY, '19000101', day) % 7) AS weekday,   -- 1900-01-01 was a Monday
                   DATEPART(HOUR, localAt) AS hour,
                   COUNT(*) AS messages
            FROM @calls
            GROUP BY (DATEDIFF(DAY, '19000101', day) % 7), DATEPART(HOUR, localAt)
            ORDER BY weekday, hour
            FOR JSON PATH
        );

        -- ── Where: the business number (branch) the customer wrote to ──
        DECLARE @branches NVARCHAR(MAX) = (
            SELECT branchId, MAX(branchName) AS branchName,
                   COUNT(*) AS messages, COUNT(DISTINCT phone10) AS customers,
                   SUM(1 - CAST(ok AS INT)) AS failures
            FROM @calls
            GROUP BY branchId
            ORDER BY COUNT(*) DESC
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );

        -- ── Did each chat end correctly? ──
        --   conversation = one customer on one Hermosillo day. outcome, first match wins:
        --     cerrada       conversationStage 'closed' (goodbye after "no" to "¿Hay algo más…?") or booked;
        --                   rows before LoanAgents#14: "no" answered to that question
        --     no_le_sirvio  their last answer to "¿Te funcionó la respuesta?" was no
        --     falla_agente  an agent call failed, or conversationStage 'error' (the agent's own fallback)
        --     pidio_persona handed off and nobody from the team wrote after (whatsappMessages staff rows)
        --     le_sirvio     their last answer to "¿Te funcionó?" was yes (no formal goodbye)
        --     sin_cierre    they left mid-conversation
        --   Finalized correctly = cerrada + le_sirvio.
        --   reasked = the same topic asked again within 15 min of the agent's answer.
        DECLARE @ordered TABLE (phone10 NVARCHAR(10), day DATE, localAt DATETIME2, logId BIGINT, topic NVARCHAR(30),
                                prevTopic NVARCHAR(30), prevAt DATETIME2,
                                prevAskedHelpful BIT, prevAskedMore BIT, answer NVARCHAR(3),
                                stage NVARCHAR(30), helpfulAnswer NVARCHAR(3));
        INSERT INTO @ordered
        SELECT phone10, day, localAt, logId, topic,
               LAG(topic)        OVER (PARTITION BY phone10 ORDER BY localAt, logId),
               LAG(localAt)      OVER (PARTITION BY phone10 ORDER BY localAt, logId),
               LAG(askedHelpful) OVER (PARTITION BY phone10, day ORDER BY localAt, logId),
               LAG(askedMore)    OVER (PARTITION BY phone10, day ORDER BY localAt, logId),
               answer, stage,
               -- yes/no to "¿Te funcionó?": the route's feedback field, else our own classification.
               COALESCE(feedback, CASE WHEN LAG(askedHelpful) OVER (PARTITION BY phone10, day
                                                                    ORDER BY localAt, logId) = 1 THEN answer END)
        FROM @calls WHERE ISNULL(phone10, '') <> '';

        DECLARE @convs TABLE (phone10 NVARCHAR(10), day DATE, failed BIT, handedOff BIT, firstHandoffAt DATETIME2,
                              booked BIT, goodbye BIT, lastHelpful NVARCHAR(3), staffReplied BIT,
                              lastAt DATETIME2, outcome NVARCHAR(20),
                              lastOutcome NVARCHAR(20), resolution NVARCHAR(20));
        INSERT INTO @convs (phone10, day, failed, handedOff, firstHandoffAt, booked, goodbye, lastHelpful, lastAt)
        SELECT c.phone10, c.day,
               -- A failed call, or the agent's own "se me complicó responderte" fallback (stage error).
               MAX(CASE WHEN c.ok = 0 OR c.stage = 'error' THEN 1 ELSE 0 END),
               MAX(CASE WHEN c.capability = 'REQUEST_HUMAN' THEN 1 ELSE 0 END),
               MIN(CASE WHEN c.capability = 'REQUEST_HUMAN' THEN c.localAt END),
               CASE WHEN EXISTS (SELECT 1 FROM @bookings b WHERE b.phone10 = c.phone10 AND b.day = c.day
                                   AND b.status <> 'cancelled') THEN 1 ELSE 0 END,
               -- Goodbye: the route says closed, or (older rows) "no" to "¿Hay algo más…?".
               CASE WHEN EXISTS (SELECT 1 FROM @ordered o WHERE o.phone10 = c.phone10 AND o.day = c.day
                                   AND (o.stage = 'closed' OR (o.prevAskedMore = 1 AND o.answer = 'no'))) THEN 1 ELSE 0 END,
               (SELECT TOP 1 o.helpfulAnswer FROM @ordered o
                 WHERE o.phone10 = c.phone10 AND o.day = c.day AND o.helpfulAnswer IS NOT NULL
                 ORDER BY o.localAt DESC, o.logId DESC),
               MAX(c.localAt)
        FROM @calls c
        WHERE ISNULL(c.phone10, '') <> ''
        GROUP BY c.phone10, c.day;

        -- Did someone from the team write after the handoff? whatsappMessages is stamped on the
        -- server clock (US Eastern, see sp_whatsappAgentConversations); localAt is Hermosillo.
        UPDATE v SET staffReplied = CASE WHEN EXISTS (
                SELECT 1 FROM [dbo].[whatsappMessages] m
                WHERE m.status IN ('staff_sent', 'staff_app')
                  AND m.phoneNumber LIKE '%' + RIGHT(v.phone10, 4)
                  AND RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(m.phoneNumber, 'whatsapp:', ''), '+', ''), ' ', ''), '-', ''), 10) = v.phone10
                  AND CONVERT(DATETIME2, (m.createdAt AT TIME ZONE 'Eastern Standard Time') AT TIME ZONE 'UTC')
                      >= DATEADD(HOUR, 7, v.firstHandoffAt)) THEN 1 ELSE 0 END
        FROM @convs v WHERE v.handedOff = 1;

        UPDATE @convs SET outcome = CASE
            WHEN goodbye = 1 OR booked = 1                 THEN 'cerrada'
            WHEN lastHelpful = 'no'                        THEN 'no_le_sirvio'
            WHEN failed = 1                                THEN 'falla_agente'
            WHEN handedOff = 1 AND ISNULL(staffReplied, 0) = 0 THEN 'pidio_persona'
            WHEN lastHelpful = 'yes'                       THEN 'le_sirvio'
            ELSE 'sin_cierre' END;

        -- ── Did it HELP? (separate from whether it ended) ──
        --   lastOutcome = the conversation's last non-null outcome; rows from before the route
        --   returned one fall back to the answer to "¿Te funcionó?". resolution, first match wins:
        --     agent_failure      an agent call failed / stage 'error' (nothing else is trustworthy)
        --     resolved_explicit  booked, or last outcome explicit_positive
        --     not_helped         last outcome explicit_negative
        --     resolved_implicit  last outcome implicit_positive ("en un rato paso")
        --     escalated          last outcome escalated (handed to a person)
        --     ended_no_result    a goodbye with no outcome — a bare "gracias" is politeness, not success
        --     no_result          open and no outcome: they stopped answering. Never a success.
        UPDATE v SET lastOutcome = (
                SELECT TOP 1 COALESCE(c.outcome, CASE o.helpfulAnswer WHEN 'yes' THEN 'explicit_positive'
                                                                     WHEN 'no'  THEN 'explicit_negative' END)
                FROM @calls c JOIN @ordered o ON o.logId = c.logId
                WHERE c.phone10 = v.phone10 AND c.day = v.day
                  AND COALESCE(c.outcome, o.helpfulAnswer) IS NOT NULL
                ORDER BY c.localAt DESC, c.logId DESC)
        FROM @convs v;

        UPDATE @convs SET resolution = CASE
            WHEN failed = 1                                THEN 'agent_failure'
            WHEN booked = 1 OR lastOutcome = 'explicit_positive' THEN 'resolved_explicit'
            WHEN lastOutcome = 'explicit_negative'         THEN 'not_helped'
            WHEN lastOutcome = 'implicit_positive'         THEN 'resolved_implicit'
            WHEN lastOutcome = 'escalated'                 THEN 'escalated'
            WHEN goodbye = 1                               THEN 'ended_no_result'
            ELSE 'no_result' END;
        DECLARE @nResolved INT = (SELECT COUNT(*) FROM @convs WHERE resolution IN ('resolved_explicit', 'resolved_implicit'));

        DECLARE @nTagged INT = (SELECT COUNT(*) FROM @ordered WHERE topic IS NOT NULL);
        DECLARE @nReasked INT = (
            SELECT COUNT(*) FROM @ordered
            WHERE topic IS NOT NULL AND topic = prevTopic
              AND topic NOT IN ('confirmacion', 'saludo', 'otro', 'baja_alta')
              AND DATEDIFF(MINUTE, prevAt, localAt) <= 15);
        DECLARE @nConvs INT = (SELECT COUNT(*) FROM @convs);
        DECLARE @nFinal INT = (SELECT COUNT(*) FROM @convs WHERE outcome IN ('cerrada', 'le_sirvio'));

        -- The chats that did NOT end correctly, newest first, to open and fix.
        DECLARE @unfinished NVARCHAR(MAX) = (
            SELECT TOP (30) v.phone10,
                   (SELECT TOP 1 c.customerName FROM @calls c WHERE c.phone10 = v.phone10
                      AND ISNULL(c.customerName, '') <> '' ORDER BY c.localAt DESC)            AS customerName,
                   CONVERT(NVARCHAR(10), v.day, 23)                                             AS date,
                   CONVERT(NVARCHAR(19), DATEADD(HOUR, 7, v.lastAt), 126)                       AS lastAtUtc,
                   v.outcome,
                   v.resolution,
                   (SELECT TOP 1 c.message FROM @calls c WHERE c.phone10 = v.phone10 AND c.day = v.day
                      ORDER BY c.localAt DESC, c.logId DESC)                                    AS lastMessage
            FROM @convs v
            WHERE v.outcome NOT IN ('cerrada', 'le_sirvio')
            ORDER BY v.lastAt DESC
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );

        DECLARE @quality NVARCHAR(MAX) = (
            SELECT
                @nConvs                                                                              AS conversations,
                @nFinal                                                                              AS finalized,
                CASE WHEN @nConvs > 0 THEN CAST(100.0 * @nFinal / @nConvs AS DECIMAL(5,1)) END       AS finalizedRatePct,
                (SELECT COUNT(*) FROM @convs WHERE outcome = 'cerrada')                              AS closed,
                (SELECT COUNT(*) FROM @convs WHERE outcome = 'le_sirvio')                            AS helped,
                (SELECT COUNT(*) FROM @convs WHERE outcome = 'no_le_sirvio')                         AS notHelped,
                (SELECT COUNT(*) FROM @convs WHERE outcome = 'falla_agente')                         AS withFailure,
                (SELECT COUNT(*) FROM @convs WHERE outcome = 'pidio_persona')                        AS handedOff,
                (SELECT COUNT(*) FROM @convs WHERE outcome = 'sin_cierre')                           AS noClosure,
                (SELECT COUNT(*) FROM @ordered WHERE helpfulAnswer = 'yes')                          AS helpfulYes,
                (SELECT COUNT(*) FROM @ordered WHERE helpfulAnswer = 'no')                           AS helpfulNo,
                @nFinal                                                                              AS resolved,
                @nReasked                                                                            AS reasked,
                CASE WHEN @nTagged > 0 THEN CAST(100.0 * @nReasked / @nTagged AS DECIMAL(5,1)) END   AS reaskedRatePct,
                (SELECT COUNT(DISTINCT phone10) FROM @calls WHERE topic = 'queja')                   AS complaints,
                (SELECT COUNT(*) FROM @customers cu
                  WHERE NOT EXISTS (SELECT 1 FROM [dbo].[integrationLogs] l
                                    WHERE l.service = 'loanagents_smartloans' AND l.operation = 'whatsapp_reservations'
                                      AND l.companyId = @companyId AND l.created_At < @fromUtc
                                      AND l.requestSummary LIKE '%' + cu.phone10 + '%'))             AS newCustomers,
                @nResolved                                                                           AS [resolution.resolved],
                CASE WHEN @nConvs > 0 THEN CAST(100.0 * @nResolved / @nConvs AS DECIMAL(5,1)) END    AS [resolution.resolvedRatePct],
                (SELECT COUNT(*) FROM @convs WHERE resolution = 'resolved_explicit')                 AS [resolution.resolvedExplicit],
                (SELECT COUNT(*) FROM @convs WHERE resolution = 'resolved_implicit')                 AS [resolution.resolvedImplicit],
                (SELECT COUNT(*) FROM @convs WHERE resolution = 'not_helped')                        AS [resolution.notHelped],
                (SELECT COUNT(*) FROM @convs WHERE resolution = 'escalated')                         AS [resolution.escalated],
                (SELECT COUNT(*) FROM @convs WHERE resolution = 'agent_failure')                     AS [resolution.agentFailure],
                (SELECT COUNT(*) FROM @convs WHERE resolution = 'ended_no_result')                   AS [resolution.endedNoResult],
                (SELECT COUNT(*) FROM @convs WHERE resolution = 'no_result')                         AS [resolution.noResult],
                JSON_QUERY(ISNULL(@unfinished, '[]'))                                                AS unfinished
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );

        DECLARE @dataSince NVARCHAR(MAX) = (
            SELECT
                (SELECT CONVERT(NVARCHAR(10), CONVERT(DATE, DATEADD(HOUR, -7, MIN(created_At))), 23)
                 FROM [dbo].[integrationLogs]
                 WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
                   AND companyId = @companyId)                                            AS agentCalls,
                (SELECT CONVERT(NVARCHAR(10), CONVERT(DATE, DATEADD(HOUR, -7, MIN(created_At))), 23)
                 FROM [dbo].[reservations]
                 WHERE companyId = @companyId AND source IS NOT NULL)                     AS bookings,
                (SELECT CONVERT(NVARCHAR(10), CONVERT(DATE, DATEADD(HOUR, -7, MIN(created_At))), 23)
                 FROM [dbo].[integrationLogs]
                 WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
                   AND companyId = @companyId AND responseSummary LIKE '%"topic":"%')     AS topics,
                (SELECT CONVERT(NVARCHAR(10), CONVERT(DATE, DATEADD(HOUR, -7, MIN(created_At))), 23)
                 FROM [dbo].[integrationLogs]
                 WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
                   AND companyId = @companyId AND responseSummary LIKE '%"outcome":"%')   AS outcomes
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
        );

        SELECT ('{"result":[{'
              + '"period":{"startDate":"' + CONVERT(NVARCHAR(10), @startDate, 23)
              + '","endDate":"' + CONVERT(NVARCHAR(10), @endDate, 23) + '"}'
              + ',"kpis":' + @kpis
              + ',"funnel":' + @funnel
              + ',"daily":' + ISNULL(@daily, '[]')
              + ',"topics":' + ISNULL(@topics, '[]')
              + ',"hours":' + ISNULL(@hours, '[]')
              + ',"branches":' + ISNULL(@branches, '[]')
              + ',"quality":' + @quality
              + ',"dataSince":' + @dataSince
              + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS jsonResult;
    END CATCH
END
GO
