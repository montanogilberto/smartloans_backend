from fastapi import APIRouter
from modules.commissionTerminals import (
    commission_terminals_sp,
    all_commission_terminals_sp,
    one_commission_terminal_sp,
)

router = APIRouter()


@router.post(
    "/commissionTerminals",
    summary="Commission terminals CRUD (payment terminal / provider commission catalog)",
    description="""
action 1 — create:
  { "commissionTerminals": [{ "action": 1, "provider": str, "terminalName": str,
    "commissionRatePct": number, "paymentMethod"?: str, "country"?: str,
    "fixedFeeAmount"?: number, "currency"?: str, "isActive"?: bool }] }
action 2 — update:
  { "commissionTerminals": [{ "action": 2, "commissionTerminalId": int, ...any field above }] }
action 3 — deactivate (never DELETE — income rows may already reference it):
  { "commissionTerminals": [{ "action": 3, "commissionTerminalId": int }] }
""",
)
def commission_terminals(json: dict):
    return commission_terminals_sp(json)


@router.get(
    "/all_commissionTerminals",
    summary="List the commission terminal catalog",
    description="Returns ALL terminals (active and inactive) ordered by provider/terminalName.",
)
def all_commission_terminals():
    return all_commission_terminals_sp()


@router.post(
    "/commissionTerminals/one",
    summary="Get a single commission terminal by id",
    description='Body: { "commissionTerminals": [{ "commissionTerminalId": int }] }',
)
def one_commission_terminal(json: dict):
    return one_commission_terminal_sp(json)
