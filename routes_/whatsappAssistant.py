from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from modules.whatsappAssistant import assistant_catalog_sp, customer_rewards, run_migration
from security.worker_key import require_worker_key

router = APIRouter()


@router.post(
    "/promotions",
    summary="Promotions — the POS's existing promo codes (WhatsApp assistant + POS)",
    description="""
Same dbo.promotions the POS applies at checkout (sp_income / sp_income_apply_promo).
action 0 (or omit) — list: { "promotions": [{ "companyId": int,
  "activeOnly"?: bool (active and within startAtUtc/endAtUtc now) }] }
action 1 — insert: { ..., "action": 1, "companyId": int, "code": str, "name": str,
  "promoType": str (one the POS applies, today "B2G1"), "description"?: str,
  "startAtUtc"?: ISO datetime, "endAtUtc"?: ISO datetime }  (created with an "ALL" target)
action 2 — update (only keys sent): { ..., "action": 2, "companyId": int, "promotionId": int, ...fields }
action 3 — deactivate: { ..., "action": 3, "companyId": int, "promotionId": int }
→ { "result": [{ "promotions": [{ ..., "targets": [{ promotionTargetId, targetType, productId, productName }] }] }] }
""",
)
def promotions(json: dict):
    return assistant_catalog_sp("promotions", json)


@router.post(
    "/promotionTargets",
    summary="Promotion targets — which products a promotion discounts (POS)",
    description="""
A promotion targets either everything ("ALL") or a list of products ("PRODUCT").
sp_income and sp_income_apply_promo only discount sale lines the targets cover;
a promotion with no targets discounts nothing.
action 0 (or omit) — list: { "promotionTargets": [{ "companyId": int, "promotionId": int }] }
action 1 — add: { ..., "action": 1, "companyId": int, "promotionId": int,
  "targetType": "ALL" | "PRODUCT", "productId"?: int (required for PRODUCT) }
  ALL replaces the product list; PRODUCT removes ALL.
action 3 — remove: { ..., "action": 3, "companyId": int, "promotionId": int, "promotionTargetId": int }
→ { "result": [{ "promotionTargets": [{ promotionTargetId, promotionId, targetType, productId, productName }] }] }
""",
)
def promotion_targets(json: dict):
    return assistant_catalog_sp("promotionTargets", json)


@router.post(
    "/businessInfo",
    summary="Business info per company/branch (WhatsApp assistant + POS)",
    description="""
action 0 (or omit) — get: { "businessInfo": [{ "companyId": int, "branchId"?: int }] }
  → each field from the branch row, else the company-wide row
action 1 — upsert (only keys sent change): { "businessInfo": [{ "action": 1, "companyId": int,
  "branchId"?: int (null = company-wide), "address"?, "mapsUrl"?, "phone"?, "email"?,
  "paymentMethods"?, "servicesInfo"?, "extraInfo"? }] }
→ { "result": [{ "businessInfo": [{ companyName, branchName, address, ... }] }] }
""",
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
    "/whatsapp/assistant/migrate",
    summary="Create promotions / promotionTargets / businessInfo / businessFaqs SPs, patch sp_income for targets (idempotent)",
)
def whatsapp_assistant_migrate():
    try:
        return JSONResponse(run_migration(), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
