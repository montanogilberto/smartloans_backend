from fastapi import APIRouter
from modules.loanOffers import loan_offers_sp, all_loan_offers_sp, one_loan_offer_sp

router = APIRouter()


@router.post(
    "/loanOffers",
    summary="Loan Offers CRUD",
    description="""
Create, update, or close a lender's capital offer broadcast.

action 1 — create (publish offer + triggers push notification from frontend):
  { "loanOffers": [{ "action": 1, "companyId": int, "lenderId": int,
    "availableCapital": float, "minRate": float, "maxRate": float,
    "minTermMonths": int, "maxTermMonths": int,
    "description"?: str, "isActive": true, "expiresAt"?: str }] }

action 2 — update / close:
  { "loanOffers": [{ "action": 2, "offerId": int, "companyId": int, "isActive": false }] }

action 3 — delete:
  { "loanOffers": [{ "action": 3, "offerId": int, "companyId": int }] }
""",
)
def loan_offers(json: dict):
    return loan_offers_sp(json)


@router.post(
    "/all_loanOffers",
    summary="List active Loan Offers",
    description="""
Returns all (or active-only) loan offers for a company.

Body: { "loanOffers": [{ "companyId": int, "isActive"?: bool }] }
Returns: { "loanOffers": LoanOffer[] }
""",
)
def all_loan_offers(json: dict):
    return all_loan_offers_sp(json)


@router.post(
    "/one_loanOffer",
    summary="Get one Loan Offer",
    description="""
Returns a single offer by offerId.

Body: { "loanOffers": [{ "offerId": int }] }
Returns: { "loanOffers": [LoanOffer] }
""",
)
def one_loan_offer(json: dict):
    return one_loan_offer_sp(json)
