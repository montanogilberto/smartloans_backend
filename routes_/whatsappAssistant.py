from fastapi import APIRouter, Depends

from modules.whatsappAssistant import (
    assistant_catalog_sp, customer_rewards, whatsapp_agent_conversations, whatsapp_agent_dashboard,
    whatsapp_agent_insights,
)
from modules.whatsappCloud import staff_reply
from security.session_tokens import require_company_admin_on_write
from security.worker_key import require_worker_key

router = APIRouter()


@router.post(
    "/promotions",
    summary="Promotions — the POS's existing promo codes (WhatsApp assistant + POS)",
    description="""
The coupons in dbo.posRewardCatalogItems (rewardType coupon_b2g1) — what the POS
applies at checkout (sp_income_applyDiscounts). promotionId = catalogItemId.
action 0 (or omit) — list: { "promotions": [{ "companyId": int,
  "activeOnly"?: bool (active and within startAtUtc/endAtUtc now) }] }
action 1 — insert: { ..., "action": 1, "companyId": int, "code": str, "name": str,
  "promoType": str (one the POS applies, today "B2G1"), "description"?: str,
  "startAtUtc"?: ISO datetime, "endAtUtc"?: ISO datetime,
  "productId"?: int (only product discounted; omit = all), "firstPurchaseOnly"?: bool }
action 2 — update (only keys sent): { ..., "action": 2, "companyId": int, "promotionId": int, ...fields }
action 3 — deactivate: { ..., "action": 3, "companyId": int, "promotionId": int }
→ { "result": [{ "promotions": [...] }] }
""",
    dependencies=[Depends(require_company_admin_on_write("promotions"))],
)
def promotions(json: dict):
    return assistant_catalog_sp("promotions", json)


@router.post(
    "/businessInfo",
    summary="Business info per company/branch (WhatsApp assistant + POS)",
    description="""
action 0 (or omit) — get: { "businessInfo": [{ "companyId": int, "branchId"?: int }] }
  → each field from the branch row, else the company-wide row
action 1 — upsert (only keys sent change): { "businessInfo": [{ "action": 1, "companyId": int,
  "branchId"?: int (null = company-wide), "address"?, "mapsUrl"?, "phone"?, "email"?,
  "paymentMethods"?, "servicesInfo"?, "extraInfo"?, "pickupPolicy"?, "deliveryPolicy"?,
  "whatsappNumber"?, "websiteUrl"?, "street"?, "city"?, "postalCode"? }] }
  (send a key as null to clear it; street/city/postalCode fall back to the
  company-wide row together, never one by one)
→ { "result": [{ "businessInfo": [{ companyName, branchName, address, ... }] }] }
""",
    dependencies=[Depends(require_company_admin_on_write("businessInfo"))],
)
def business_info(json: dict):
    return assistant_catalog_sp("businessInfo", json)


@router.post(
    "/businessFaqs",
    summary="FAQs per company/branch (WhatsApp assistant + POS)",
    description="""
action 0 (or omit) — list: { "businessFaqs": [{ "companyId": int, "branchId"?: int, "activeOnly"?: bool }] }
action 1 — insert: { ..., "action": 1, "companyId": int, "branchId"?: int,
  "question": str, "answer": str, "sortOrder"?: int }
action 2 — update (only keys sent): { ..., "action": 2, "companyId": int, "faqId": int, ...fields }
action 3 — deactivate: { ..., "action": 3, "companyId": int, "faqId": int }
→ { "result": [{ "businessFaqs": [...] }] }
""",
    dependencies=[Depends(require_company_admin_on_write("businessFaqs"))],
)
def business_faqs(json: dict):
    return assistant_catalog_sp("businessFaqs", json)


@router.post(
    "/whatsapp/assistant/customerRewards",
    summary="WhatsApp sender's own reward points (agent service only, X-Worker-Key)",
    description="""
{ "customerRewards": [{ "companyId": int, "phone": str (the WhatsApp sender) }] }
→ { "result": [{ "status": "found", "clientId", "firstName", "balance",
    "lifetimeEarned", "redeemable": [{ name, requiredPoints, canRedeemNow, ... }] }] }
  or { "status": "not_found" | "ambiguous" }
""",
)
def whatsapp_customer_rewards(json: dict, _: str = Depends(require_worker_key)):
    return customer_rewards(json)


@router.post(
    "/whatsapp/agentDashboard",
    summary="WhatsApp agent dashboard: activity, handoffs, bookings and sales after chatting (read-only)",
    description="""{ "whatsappAgentDashboard": [{ "companyId": int, "startDate"?: "YYYY-MM-DD",
  "endDate"?: "YYYY-MM-DD", "attributionDays"?: int (default 14) }] }
(Hermosillo days; default the last 30 days)
→ { "result": [{ "period": {startDate, endDate},
  "kpis": { messagesAnswered, failedCalls, failureRatePct, avgLatencyMs, p95LatencyMs, customers,
            handoffs, proposals, bookings, bookingsCancelled, customersWhoBought, salesAfterChat,
            attributionDays },
  "funnel": { customers, gotProposal, booked, bought },
  "daily": [{date, messages, customers, failures, handoffs, bookings}],
  "dataSince": { agentCalls: date|null, bookings: date|null } }] }
customersWhoBought / salesAfterChat: sales within attributionDays after the customer's
first message — they happened after the chat, the agent didn't necessarily cause them.""",
)
def whatsapp_agent_dashboard_route(json: dict):
    return whatsapp_agent_dashboard(json)


@router.post(
    "/whatsapp/agentConversations",
    summary="WhatsApp agent conversations: what each customer wrote and what the agent answered (read-only)",
    description="""
action "list": { "whatsappAgentConversations": [{ "action": "list", "companyId": int,
  "startDate"?: "YYYY-MM-DD", "endDate"?: "YYYY-MM-DD", "search"?: str }] }   (default the last 30 days)
→ { "result": [{ "period": {startDate, endDate},
  "conversations": [{ phone10, customerName, turns, failures, firstAtUtc, lastAtUtc,
                      lastMessage, lastReply, handedOff, proposed, bookings }] }] }
action "thread": { "whatsappAgentConversations": [{ "action": "thread", "companyId": int,
  "phone10": str, "startDate"?, "endDate"? }]   (default the last 90 days)
→ { "result": [{ phone10, customerName,
  "turns": [{ atUtc, message, reply, ok, latencyMs, capability, actionNote }],
  "bookings": [{ reservationId, atUtc, status, reservationDate, timeSlot, serviceType }] }] }
Source: the agent calls in integrationLogs + WhatsApp reservations. The customer's plain
"sí"/"no" to a proposal and messages while a person has the chat are not included.""",
)
def whatsapp_agent_conversations_route(json: dict):
    return whatsapp_agent_conversations(json)


@router.post(
    "/whatsapp/staffReply",
    summary="A POS user replies to a WhatsApp customer from the business number (the agent keeps answering)",
    description="""
{ "whatsappStaffReply": [{ "companyId": int, "userId": int, "phone10": str, "body": str (≤ 4096) }] }
→ 200 { sent: true, messageId, atUtc }
400 bad input · 404 no_channel · 409 outside_24h (no customer message in the last 24 h:
Meta only delivers templates) · 502 send_failed
Sent from the number the customer wrote to; logged in whatsappMessages (status 'staff_sent');
the agent is never paused: it keeps answering the customer's next messages.""",
)
def whatsapp_staff_reply_route(json: dict):
    return staff_reply(json)


@router.post(
    "/whatsapp/agentInsights",
    summary="¿Qué quieren mis clientes? — AI summary of a period's WhatsApp customer messages (read-only)",
    description="""
{ "whatsappAgentInsights": [{ "companyId": int, "startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD" }] }
→ { "result": [{ summary, commonDoubts: [{question, count, suggestion}], unmetNeeds: [str],
  messagesAnalyzed }] }
Newest 500 customer messages of the period (no greetings/confirmations), phones and emails
removed, summarized by LoanAgents /support/whatsapp-insights. One LLM call; nothing stored.""",
)
def whatsapp_agent_insights_route(json: dict):
    return whatsapp_agent_insights(json)
