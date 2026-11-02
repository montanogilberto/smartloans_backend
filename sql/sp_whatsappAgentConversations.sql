-- ─────────────────────────────────────────────────────────────────────────────
-- sp_whatsappAgentConversations — a business's WhatsApp customers: what they
-- wrote, what the agent / staff answered, and the notifications sent to them.
-- Read-only (POS "Agente WhatsApp" › Conversaciones). Nothing is written here.
--
-- Sources:
--   dbo.integrationLogs   service 'loanagents_smartloans', operation 'whatsapp_reservations'
--                         — one row per agent turn, WITH companyId: requestSummary {phone,
--                         customerName, message, branchId}, responseSummary {reply,
--                         pendingAction{capability, confirmationSummary, fields}}.
--   dbo.whatsappMessages  every inbound/outbound WhatsApp text (incl. the plain "sí"/"no",
--                         messages while staff has the chat, staff replies: status
--                         'staff_sent' = from the POS, 'staff_app' = from the WhatsApp
--                         Business app). It has NO company column, so it is used only for
--                         a phone that belongs to this company alone (it wrote to this
--                         company's agent/numbers and to no other company's). Otherwise the
--                         thread falls back to the agent turns (source 'agent_log').
--   dbo.whatsappConversations / whatsappChannels  which number the customer wrote to,
--                         and whether the bot is paused for staff.
--   dbo.reservations      source = 'whatsapp'.
--   dbo.notificationDispatches  push / WhatsApp template / SMS sent to the client
--                         (recipientType 'client' = clientId, 'user' = userId).
--   dbo.pushNotifications direct pushes to the client's app user (targetUserId).
--   Client = the company's active clients whose cellphone ends in the same 10 digits
--   (same match as sp_whatsappCustomerRewards); app user = users.clientId.
-- A customer = last 10 digits of the phone. Days are Hermosillo days (UTC-7, no DST);
-- timestamps returned are UTC.
--
-- action "list"    { companyId, startDate?, endDate?, search? }   (default: last 30 days)
--   → { result: [{ period, conversations: [{ phone10, customerName, turns, failures,
--        firstAtUtc, lastAtUtc, lastMessage, lastReply, handedOff, proposed, bookings }] }] }
--   Customers who talked to the agent in the period; newest first, max 200.
-- action "thread"  { companyId, phone10, startDate?, endDate? }   (default: last 90 days)
--   → { result: [{ phone10, customerName, source: "messages"|"agent_log",
--        lastInboundUtc, staffPausedUntilUtc,
--        items: [{ atUtc, kind, text, detail, channel, status, error }] }] }
--   kind: client | bot | staff | staff_app | agent_failed | action | booking | notification
--   (oldest first, max 800 items)
-- action "channel" { companyId, phone10 }
--   → { result: [{ channelId, phoneNumberId, customerPhone, lastInboundUtc }] } — the number to reply
--   from: the latest chat on one of the company's numbers, else the branch of the last
--   agent turn, else the company's only active number. Empty result = none.
-- Input envelope: { "whatsappAgentConversations": [{ "action": ..., ... }] }
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
                                         DATEADD(DAY, CASE WHEN @action = 'list' THEN -29 ELSE -89 END, @endDate));

        IF @companyId IS NULL OR @action NOT IN ('list', 'thread', 'channel')
           OR (@action IN ('thread', 'channel') AND (ISNULL(@phone10, '') = '' OR @phone10 LIKE '%[^0-9]%'))
        BEGIN
            SELECT '{"error":"companyId and action (list|thread|channel) are required; thread/channel need phone10 (digits)"}' AS jsonResult;
            RETURN;
        END

        DECLARE @fromUtc DATETIME2 = DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2));
        DECLARE @toUtc   DATETIME2 = DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2));

        -- ── channel: which of the company's numbers to reply from ──────────────
        IF @action = 'channel'
        BEGIN
            DECLARE @ch TABLE (channelId INT, phoneNumberId NVARCHAR(50), customerPhone NVARCHAR(20));
            INSERT INTO @ch
            SELECT TOP 1 ch.channelId, ch.phoneNumberId, wc.customerPhone
            FROM [dbo].[whatsappConversations] wc
            JOIN [dbo].[whatsappChannels] ch ON ch.channelId = wc.channelId
            WHERE ch.companyId = @companyId AND ch.isActive = 1
              AND RIGHT(REPLACE(REPLACE(REPLACE(wc.customerPhone, '+', ''), ' ', ''), '-', ''), 10) = @phone10
            ORDER BY wc.updatedAt DESC;

            IF NOT EXISTS (SELECT 1 FROM @ch)
            BEGIN
                DECLARE @lastReq NVARCHAR(MAX) = (
                    SELECT TOP 1 requestSummary FROM [dbo].[integrationLogs]
                    WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
                      AND companyId = @companyId AND ISJSON(requestSummary) = 1
                      AND requestSummary LIKE '%' + @phone10 + '%'
                      AND RIGHT(REPLACE(REPLACE(REPLACE(JSON_VALUE(requestSummary, '$.phone'), '+', ''), ' ', ''), '-', ''), 10) = @phone10
                    ORDER BY created_At DESC);
                DECLARE @lastBranch INT = TRY_CONVERT(INT, JSON_VALUE(@lastReq, '$.branchId'));
                DECLARE @lastPhone NVARCHAR(20) = JSON_VALUE(@lastReq, '$.phone');
                IF @lastPhone IS NOT NULL
                    INSERT INTO @ch
                    SELECT TOP 1 channelId, phoneNumberId, @lastPhone
                    FROM [dbo].[whatsappChannels]
                    WHERE companyId = @companyId AND isActive = 1
                      AND (branchId = @lastBranch OR (@lastBranch IS NULL AND branchId IS NULL)
                           OR (SELECT COUNT(*) FROM [dbo].[whatsappChannels]
                               WHERE companyId = @companyId AND isActive = 1) = 1)
                    ORDER BY CASE WHEN branchId = @lastBranch THEN 0 ELSE 1 END, channelId;
            END

            -- Last time the customer wrote (opens Meta's 24 h window): their last agent turn
            -- with this company, or their last inbound message if the phone is this company's alone.
            DECLARE @lastTurnUtc DATETIME2 = (
                SELECT MAX(created_At) FROM [dbo].[integrationLogs]
                WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
                  AND companyId = @companyId AND requestSummary LIKE '%' + @phone10 + '%'
                  AND created_At >= DATEADD(DAY, -2, SYSUTCDATETIME()));
            DECLARE @otherCompany BIT = CASE WHEN EXISTS (
                    SELECT 1 FROM [dbo].[integrationLogs]
                    WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
                      AND companyId <> @companyId AND requestSummary LIKE '%' + @phone10 + '%')
                OR EXISTS (SELECT 1 FROM [dbo].[whatsappConversations] wc
                           JOIN [dbo].[whatsappChannels] ch ON ch.channelId = wc.channelId
                           WHERE ch.companyId <> @companyId
                             AND RIGHT(REPLACE(REPLACE(REPLACE(wc.customerPhone, '+', ''), ' ', ''), '-', ''), 10) = @phone10)
                THEN 1 ELSE 0 END;
            DECLARE @lastMsgUtc DATETIME2 = CASE WHEN @otherCompany = 0 THEN (
                SELECT MAX(createdAt) FROM [dbo].[whatsappMessages]
                WHERE direction = 'inbound' AND createdAt >= DATEADD(DAY, -2, SYSUTCDATETIME())
                  AND phoneNumber LIKE '%' + RIGHT(@phone10, 4)
                  AND RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(phoneNumber, 'whatsapp:', ''), '+', ''), ' ', ''), '-', ''), 10) = @phone10) END;
            DECLARE @lastInboundCh DATETIME2 =
                CASE WHEN @lastMsgUtc IS NULL OR @lastTurnUtc > @lastMsgUtc THEN @lastTurnUtc ELSE @lastMsgUtc END;

            SELECT ('{"result":' + ISNULL((SELECT channelId, phoneNumberId, customerPhone,
                                                  CONVERT(NVARCHAR(19), @lastInboundCh, 126) AS lastInboundUtc
                                           FROM @ch FOR JSON PATH, INCLUDE_NULL_VALUES), '[]') + '}') AS jsonResult;
            RETURN;
        END

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
          AND l.created_At >= @fromUtc AND l.created_At < @toUtc
          AND (@action = 'list' OR l.requestSummary LIKE '%' + @phone10 + '%');

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

        -- ── list ───────────────────────────────────────────────────────────────
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

        -- ── thread ─────────────────────────────────────────────────────────────
        -- Does this phone belong to this company alone? (whatsappMessages has no company.)
        DECLARE @mine BIT = CASE WHEN EXISTS (SELECT 1 FROM @turns)
            OR EXISTS (SELECT 1 FROM [dbo].[whatsappConversations] wc
                       JOIN [dbo].[whatsappChannels] ch ON ch.channelId = wc.channelId
                       WHERE ch.companyId = @companyId
                         AND RIGHT(REPLACE(REPLACE(REPLACE(wc.customerPhone, '+', ''), ' ', ''), '-', ''), 10) = @phone10)
            THEN 1 ELSE 0 END;
        DECLARE @shared BIT = CASE WHEN EXISTS (
                SELECT 1 FROM [dbo].[integrationLogs]
                WHERE service = 'loanagents_smartloans' AND operation = 'whatsapp_reservations'
                  AND companyId <> @companyId AND requestSummary LIKE '%' + @phone10 + '%')
            OR EXISTS (SELECT 1 FROM [dbo].[whatsappConversations] wc
                       JOIN [dbo].[whatsappChannels] ch ON ch.channelId = wc.channelId
                       WHERE ch.companyId <> @companyId
                         AND RIGHT(REPLACE(REPLACE(REPLACE(wc.customerPhone, '+', ''), ' ', ''), '-', ''), 10) = @phone10)
            THEN 1 ELSE 0 END;
        DECLARE @useMessages BIT = CASE WHEN @mine = 1 AND @shared = 0 THEN 1 ELSE 0 END;

        -- ord breaks ties within the same second: the customer's message first.
        DECLARE @items TABLE (atUtc DATETIME2, ord INT, kind NVARCHAR(20), text NVARCHAR(MAX), detail NVARCHAR(400),
                              channel NVARCHAR(20), status NVARCHAR(30), error NVARCHAR(400));

        IF @useMessages = 1
        BEGIN
            INSERT INTO @items (atUtc, ord, kind, text, detail, status)
            SELECT m.createdAt,
                   CASE WHEN m.direction = 'inbound' THEN 0 ELSE 2 END,
                   CASE WHEN m.direction = 'inbound' THEN 'client'
                        WHEN m.status = 'staff_sent' THEN 'staff'
                        WHEN m.status = 'staff_app' THEN 'staff_app'
                        ELSE 'bot' END,
                   m.messageBody,
                   CASE WHEN m.status = 'staff_sent' THEN NULLIF(m.responseBody, '') END,
                   m.status
            FROM [dbo].[whatsappMessages] m
            WHERE m.createdAt >= @fromUtc AND m.createdAt < @toUtc
              AND m.phoneNumber LIKE '%' + RIGHT(@phone10, 4)
              AND RIGHT(REPLACE(REPLACE(REPLACE(REPLACE(m.phoneNumber, 'whatsapp:', ''), '+', ''), ' ', ''), '-', ''), 10) = @phone10;
        END
        ELSE
        BEGIN
            INSERT INTO @items (atUtc, ord, kind, text)
            SELECT atUtc, 0, 'client', message FROM @turns;
            INSERT INTO @items (atUtc, ord, kind, text, detail)
            SELECT atUtc, 2, 'bot', reply,
                   CASE WHEN latencyMs IS NOT NULL THEN CONVERT(NVARCHAR(20), latencyMs) END
            FROM @turns WHERE ok = 1 AND reply IS NOT NULL;
        END

        INSERT INTO @items (atUtc, ord, kind, text)
        SELECT atUtc, 1, 'agent_failed', NULL FROM @turns WHERE ok = 0;
        INSERT INTO @items (atUtc, ord, kind, text, detail)
        SELECT atUtc, 3, 'action', actionNote, capability FROM @turns WHERE capability IS NOT NULL;
        INSERT INTO @items (atUtc, ord, kind, text, detail, status)
        SELECT atUtc, 4, 'booking',
               CONCAT('Reservación #', reservationId,
                      CASE WHEN serviceType IS NOT NULL THEN ' · ' + serviceType ELSE '' END,
                      CASE WHEN reservationDate IS NOT NULL THEN ' · ' + CONVERT(NVARCHAR(10), reservationDate, 23) ELSE '' END,
                      CASE WHEN timeSlot IS NOT NULL THEN ' ' + timeSlot ELSE '' END),
               CONVERT(NVARCHAR(20), reservationId), status
        FROM @bookings WHERE phone10 = @phone10;

        -- Notifications to this customer as a client of this company (push / WhatsApp / SMS).
        DECLARE @clients TABLE (clientId INT);
        INSERT INTO @clients
        SELECT c.clientId FROM [dbo].[clients] c
        WHERE c.companyId = @companyId AND c.isActive = 1 AND c.first_name <> N'Desconocido'
          AND RIGHT(REPLACE(REPLACE(REPLACE(c.cellphone, '+', ''), ' ', ''), '-', ''), 10) = @phone10;
        DECLARE @appUsers TABLE (userId INT);
        INSERT INTO @appUsers
        SELECT DISTINCT u.userId FROM [dbo].[users] u WHERE u.clientId IN (SELECT clientId FROM @clients);

        INSERT INTO @items (atUtc, ord, kind, text, detail, channel, status, error)
        SELECT COALESCE(d.sentAt, d.failedAt, d.created_At), 5, 'notification',
               d.messagePreview, d.eventName, LOWER(d.selectedChannel), d.status,
               LEFT(d.providerErrorMessage, 400)
        FROM [dbo].[notificationDispatches] d
        WHERE d.companyId = @companyId
          AND d.created_At >= @fromUtc AND d.created_At < @toUtc
          AND ((d.recipientType = 'client' AND d.recipientId IN (SELECT clientId FROM @clients))
            OR (d.recipientType = 'user'   AND d.recipientId IN (SELECT userId FROM @appUsers)));

        INSERT INTO @items (atUtc, ord, kind, text, detail, channel, status)
        SELECT COALESCE(p.sentAt, p.created_At), 5, 'notification',
               CONCAT(p.title, CASE WHEN p.message IS NOT NULL THEN ' — ' + p.message ELSE '' END),
               p.notificationType, 'push',
               CASE WHEN p.isSent = 1 THEN 'SENT' ELSE 'PENDING' END
        FROM [dbo].[pushNotifications] p
        WHERE p.companyId = @companyId AND p.targetUserId IN (SELECT userId FROM @appUsers)
          AND p.created_At >= @fromUtc AND p.created_At < @toUtc;

        DECLARE @lastInbound DATETIME2 = CASE WHEN @useMessages = 1
            THEN (SELECT MAX(atUtc) FROM @items WHERE kind = 'client')
            ELSE (SELECT MAX(atUtc) FROM @turns) END;
        DECLARE @pausedUntil DATETIME2 = (
            SELECT MAX(wc.staffPausedUntil) FROM [dbo].[whatsappConversations] wc
            JOIN [dbo].[whatsappChannels] ch ON ch.channelId = wc.channelId
            WHERE ch.companyId = @companyId AND wc.staffPausedUntil > SYSUTCDATETIME()
              AND RIGHT(REPLACE(REPLACE(REPLACE(wc.customerPhone, '+', ''), ' ', ''), '-', ''), 10) = @phone10);
        DECLARE @name NVARCHAR(200) = (SELECT TOP 1 customerName FROM @turns
                                       WHERE ISNULL(customerName, '') <> '' ORDER BY atUtc DESC);

        DECLARE @itemsJson NVARCHAR(MAX) = (
            SELECT TOP (800) CONVERT(NVARCHAR(19), atUtc, 126) AS atUtc, kind, text, detail, channel, status, error
            FROM @items ORDER BY atUtc, ord
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{'
              + '"phone10":"' + @phone10 + '"'
              + ',"customerName":' + ISNULL('"' + STRING_ESCAPE(@name, 'json') + '"', 'null')
              + ',"source":"' + CASE WHEN @useMessages = 1 THEN 'messages' ELSE 'agent_log' END + '"'
              + ',"lastInboundUtc":' + ISNULL('"' + CONVERT(NVARCHAR(19), @lastInbound, 126) + '"', 'null')
              + ',"staffPausedUntilUtc":' + ISNULL('"' + CONVERT(NVARCHAR(19), @pausedUntil, 126) + '"', 'null')
              + ',"items":' + ISNULL(@itemsJson, '[]')
              + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS jsonResult;
    END CATCH
END
GO
