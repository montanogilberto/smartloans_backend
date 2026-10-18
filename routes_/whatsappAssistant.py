from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from modules.whatsappAssistant import assistant_catalog_sp, customer_rewards, run_migration
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
    summary="Create businessInfo / businessFaqs tables + SPs (idempotent; promotions: /posRewards/migrate)",
)
def whatsapp_assistant_migrate():
    try:
        return JSONResponse(run_migration(), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
