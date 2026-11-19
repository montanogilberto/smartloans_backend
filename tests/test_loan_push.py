"""RFC-014 core push (modules/loanPush.py): send_azure_push between the parties
of a loan, saved to the inbox, triggered by the backend transitions."""
import asyncio
import json
import unittest
from unittest import mock

from modules import loanPush, loanProposals, transferEvidence


class RenderTests(unittest.TestCase):
    def test_every_template_renders(self):
        params = {"name": "Ana", "amount": 5000, "rate": 24, "term": 12, "loanId": 88}
        for key in loanPush.TEMPLATES:
            kind, title, message, route = loanPush.render(key, **params)
            self.assertTrue(title and message and route.startswith("/"), key)
            self.assertNotIn("{", title + message + route, key)

    def test_money_and_deep_link(self):
        _, title, message, route = loanPush.render("funding_declared", amount=5000, loanId=88)
        self.assertIn("$5,000.00", message)
        self.assertEqual(route, "/loan-detail/88")


class PushToClientTests(unittest.TestCase):
    def run_push(self, user_id=1037, sent=True):
        cursor = mock.Mock()
        cursor.fetchone.return_value = (json.dumps({"status": "success", "pushNotificationId": 555}),)
        conn = mock.Mock()
        conn.cursor.return_value = cursor
        self.pushed = []

        async def fake_send(title, message, target_user_id=None, data=None):
            self.pushed.append({"user": target_user_id, "title": title, "data": data})
            return {"sent": sent}

        with mock.patch.object(loanPush, "connection", return_value=conn), \
                mock.patch.object(loanPush, "resolve_push_user_ids", return_value={3371: user_id}), \
                mock.patch.object(loanPush, "send_azure_push", side_effect=fake_send), \
                mock.patch.object(loanPush, "_record_delivery") as record:
            ok = asyncio.run(loanPush.push_to_client(1008, 3371, "loan_requested",
                                                     name="Ana", amount=5000, rate=24, term=12, proposalId=9))
        return ok, cursor, record, conn

    def test_pushes_to_the_user_saves_inbox_and_records_delivery(self):
        ok, cursor, record, conn = self.run_push()
        self.assertTrue(ok)
        self.assertEqual(self.pushed[0]["user"], 1037)  # userId, never the clientId
        self.assertEqual(self.pushed[0]["data"], {"navigationRoute": "/p2p-lending"})
        stored = json.loads(cursor.execute.call_args.args[1][0])["pushNotifications"][0]
        self.assertEqual(stored["targetUserId"], 1037)
        self.assertEqual(stored["action"], 1)
        record.assert_called_once_with(cursor, 555, 1037, True)
        conn.close.assert_called_once()

    def test_client_without_app_user_is_skipped(self):
        ok, cursor, record, _ = self.run_push(user_id=None)
        self.assertFalse(ok)
        self.assertEqual(self.pushed, [])
        cursor.execute.assert_not_called()

    def test_failure_never_raises(self):
        with mock.patch.object(loanPush, "connection", side_effect=RuntimeError("db down")):
            self.assertFalse(asyncio.run(loanPush.push_to_client(1008, 3371, "loan_rejected", amount=1)))


class ProposalNoticeTests(unittest.TestCase):
    BEFORE = {"proposalId": 9, "companyId": 1008, "lenderId": 3371, "borrowerId": 2165,
              "requestedAmount": 5000, "proposedRate": 24, "termMonths": 12, "status": "pending"}

    def notices(self, item, before=None, result=None):
        return [(cid, tpl) for cid, tpl, _ in loanProposals.proposal_notices(item, before, result or {})]

    def test_new_request_goes_to_the_lender(self):
        out = loanProposals.proposal_notices(
            {"action": 1, "borrowerName": "Ana"}, None,
            {"proposalId": 9, "lenderId": 3371, "borrowerId": 2165, "requestedAmount": 5000,
             "proposedRate": 24, "termMonths": 12})
        self.assertEqual([(c, t) for c, t, _ in out], [(3371, "loan_requested")])
        self.assertEqual(out[0][2]["name"], "Ana")

    def test_failed_create_notifies_nobody(self):
        self.assertEqual(self.notices({"action": 1}, None, {"error": "x"}), [])

    def test_accepted_goes_to_both(self):
        self.assertEqual(self.notices({"action": 2, "status": "accepted"}, self.BEFORE),
                         [(2165, "loan_approved_borrower"), (3371, "loan_approved_lender")])

    def test_lender_rejection_goes_to_the_borrower(self):
        self.assertEqual(self.notices({"action": 2, "status": "rejected"}, self.BEFORE),
                         [(2165, "loan_rejected")])

    def test_counteroffer_goes_to_the_borrower_with_new_terms(self):
        out = loanProposals.proposal_notices(
            {"action": 2, "status": "countered", "counteredAmount": 4000, "counteredRate": 20,
             "counteredTermMonths": 6}, self.BEFORE, {})
        self.assertEqual(out[0][:2], (2165, "loan_countered"))
        self.assertEqual((out[0][2]["amount"], out[0][2]["rate"], out[0][2]["term"]), (4000, 20, 6))

    def test_borrower_answers_to_a_counteroffer_go_to_the_lender(self):
        countered = {**self.BEFORE, "status": "countered"}
        self.assertEqual(self.notices({"action": 2, "status": "pending"}, countered),
                         [(3371, "loan_counter_accepted")])
        self.assertEqual(self.notices({"action": 2, "status": "rejected"}, countered),
                         [(3371, "loan_counter_rejected")])

    def test_no_status_change_notifies_nobody(self):
        self.assertEqual(self.notices({"action": 2, "status": "pending"}, self.BEFORE), [])
        self.assertEqual(self.notices({"action": 2, "lenderNote": "x"}, self.BEFORE), [])
        self.assertEqual(self.notices({"action": 3}, self.BEFORE), [])


class EvidenceReviewTests(unittest.TestCase):
    def run_hook(self, status, result=None):
        with mock.patch.object(transferEvidence.threading, "Thread") as thread:
            transferEvidence._maybe_push_evidence_review(
                {"transferEvidence": [{"action": "validate", "companyId": 1008, "transferEvidenceId": 7,
                                       "validationStatus": status}]}, result or {"message": "ok"})
        return thread

    def test_review_push_only_when_not_valid(self):
        self.run_hook("NEEDS_REVIEW").assert_called_once()
        self.run_hook("INVALID").assert_called_once()
        self.run_hook("VALID").assert_not_called()

    def test_no_push_when_the_save_failed(self):
        self.run_hook("NEEDS_REVIEW", {"error": "x"}).assert_not_called()

    def test_send_targets_the_funding_borrower(self):
        evidence = {"referenceType": "FUNDING", "referenceId": 41}
        ft = {"borrowerClientId": 2165, "amountMXN": 5000, "loanId": 88, "fundingTransactionId": 41}
        with mock.patch.object(transferEvidence, "transfer_evidence_sp",
                               return_value=mock.Mock(body=json.dumps(evidence))), \
                mock.patch("modules.fundingTransactions._sp_raw", return_value=ft), \
                mock.patch("modules.loanPush.push_to_client", new=mock.AsyncMock(return_value=True)) as push:
            transferEvidence._send_evidence_review(1008, 7)
        push.assert_awaited_once_with(1008, 2165, "funding_evidence_review", amount=5000, loanId=88,
                                      fundingTransactionId=41)


if __name__ == "__main__":
    unittest.main()
