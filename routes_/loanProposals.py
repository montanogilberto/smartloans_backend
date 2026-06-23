from fastapi import APIRouter
from modules.loanProposals import loan_proposals_sp, all_loan_proposals_sp, one_loan_proposal_sp

router = APIRouter()


@router.post(
    "/loanProposals",
    summary="Loan Proposals CRUD",
    description="""
Create, update, or delete a P2P loan proposal.

action 1 — create:
  { "loanProposals": [{ "action": 1, "companyId": int, "lenderId": int, "borrowerId": int,
    "requestedAmount": float, "proposedRate": float, "termMonths": int,
    "status": "pending", "borrowerNote"?: str }] }

action 2 — update (accept/reject):
  { "loanProposals": [{ "action": 2, "proposalId": int, "status": str, "respondedAt"?: str }] }

action 3 — delete:
  { "loanProposals": [{ "action": 3, "proposalId": int, "companyId": int }] }
""",
)
def loan_proposals(json: dict):
    return loan_proposals_sp(json)


@router.post(
    "/all_loanProposals",
    summary="List all Loan Proposals",
    description="""
Returns all proposals for a company, optionally filtered by lenderId, borrowerId, or status.

Body: { "loanProposals": [{ "companyId": int, "lenderId"?: int, "borrowerId"?: int, "status"?: str }] }
Returns: { "loanProposals": LoanProposal[] }
""",
)
def all_loan_proposals(json: dict):
    return all_loan_proposals_sp(json)


@router.post(
    "/one_loanProposal",
    summary="Get one Loan Proposal",
    description="""
Returns a single proposal by proposalId.

Body: { "loanProposals": [{ "proposalId": int }] }
Returns: { "loanProposals": [LoanProposal] }
""",
)
def one_loan_proposal(json: dict):
    return one_loan_proposal_sp(json)
