"""
Lender platform fee (RFC-016 fase 3b): 5% + IVA charged to the lender's saved
card when the FUNDING intent is created; only a signature-verified Stripe webhook
marks it PAID/REFUNDED; funding stays locked until PAID. No database or Stripe:
sp_platformFees and Stripe are stubbed.

Run:  venv/bin/python -m unittest tests/test_platform_fees.py -v
"""
import asyncio
import json
import os
import sys
import unittest
from decimal import Decimal
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.platformFees as fees  # noqa: E402
import modules.paymentIntents as payment_intents  # noqa: E402
import modules.stripe_payments as sp  # noqa: E402
import routes_.platformFees as routes  # noqa: E402

FEE = {"platformFeeId": 1, "companyId": 1008, "loanId": 14, "lenderClientId": 2167,
       "totalAmount": Decimal("29.00"), "status": "PENDING", "stripePaymentIntentId": ""}


class FakeSP:
    """sp_platformFees stand-in: records calls, answers like the real SP."""

    def __init__(self, fee=None, write_result=("1", "ok", "")):
        self.fee = dict(fee) if fee else None
        self.calls = []
        self.write_result = write_result

    def __call__(self, payload):
        self.calls.append(payload)
        action = payload["action"]
        if action == "by_loan":
            return [(json.dumps({"platformFees": [self.fee]}, default=str),)] if self.fee else [(None,)]
        if action == "insert":
            self.fee = dict(FEE)
        return [self.write_result]

    def actions(self):
        return [c["action"] for c in self.calls]


def run(coro):
    return asyncio.run(coro)


class ChargeTest(unittest.TestCase):
    def setUp(self):
        mock.patch.dict(os.environ, {"PLATFORM_FEE_CHARGE_ENABLED": "true"}).start()
        self.sp = FakeSP()
        mock.patch.object(fees, "_exec", self.sp).start()
        mock.patch.object(fees.stripe, "api_key", "sk_test_real").start()
        self.push = mock.patch.object(fees, "push_in_background").start()
        self.card = mock.patch.object(fees, "_lender_card", return_value=("pm_1", "cus_1")).start()
        self.create = mock.patch.object(fees.stripe.PaymentIntent, "create", return_value={"id": "pi_1"}).start()
        mock.patch.object(fees, "log_integration").start()
        mock.patch.object(fees, "log_workflow_step").start()

    def tearDown(self):
        mock.patch.stopall()

    def test_creates_the_fee_and_charges_the_exact_total_once_per_loan(self):
        fees.charge_fee(1008, 14, 2167)
        kwargs = self.create.call_args.kwargs
        self.assertEqual(kwargs["amount"], 2900)            # $29.00 = 25 + 4 IVA, in centavos
        self.assertEqual(kwargs["currency"], "mxn")
        self.assertTrue(kwargs["off_session"] and kwargs["confirm"])
        self.assertEqual(kwargs["customer"], "cus_1")
        self.assertEqual(kwargs["idempotency_key"], "platform_fee:1008:14")
        self.assertEqual(kwargs["metadata"]["type"], "platform_fee")
        self.assertIn("insert", self.sp.actions())
        self.assertIn("set_intent", self.sp.actions())

    def test_never_marks_paid_itself(self):
        fees.charge_fee(1008, 14, 2167)
        self.assertNotIn("mark_webhook", self.sp.actions())

    def test_no_saved_card_asks_for_one_and_charges_nothing(self):
        self.card.return_value = None
        fees.charge_fee(1008, 14, 2167)
        self.create.assert_not_called()
        self.assertEqual(self.push.call_args.args[2], "platform_fee_card_needed")

    def test_needs_3ds_keeps_the_intent_and_tells_the_lender(self):
        err = fees.stripe.CardError("auth", None, code="authentication_required")
        err.error = mock.Mock(payment_intent={"id": "pi_3ds"})
        self.create.side_effect = err
        fees.charge_fee(1008, 14, 2167)
        stored = [c for c in self.sp.calls if c["action"] == "set_intent"][0]
        self.assertEqual(stored["stripePaymentIntentId"], "pi_3ds")
        self.assertEqual(stored["failureReason"], "authentication_required")
        self.assertEqual(self.push.call_args.args[2], "platform_fee_action_required")

    def test_an_existing_charge_is_never_repeated(self):
        self.sp.fee = {**FEE, "stripePaymentIntentId": "pi_old"}
        fees.charge_fee(1008, 14, 2167)
        self.create.assert_not_called()

    def test_paid_fee_is_left_alone(self):
        self.sp.fee = {**FEE, "status": "PAID"}
        fees.charge_fee(1008, 14, 2167)
        self.create.assert_not_called()

    def test_centavos_round_half_up(self):
        self.assertEqual(fees._centavos(Decimal("580.005")), 58001)
        self.assertEqual(fees._centavos("29.00"), 2900)


class ChargeSwitchTest(unittest.TestCase):
    """PLATFORM_FEE_CHARGE_ENABLED off (the default): nothing is created or charged."""

    def setUp(self):
        mock.patch.dict(os.environ, {"PLATFORM_FEE_CHARGE_ENABLED": ""}).start()
        self.sp = FakeSP()
        mock.patch.object(fees, "_exec", self.sp).start()
        self.create = mock.patch.object(fees.stripe.PaymentIntent, "create").start()

    def tearDown(self):
        mock.patch.stopall()

    def test_charge_is_refused_and_touches_nothing(self):
        with self.assertRaises(fees.FeeError):
            fees.charge_fee(1008, 14, 2167)
        self.assertEqual(self.sp.calls, [])
        self.create.assert_not_called()

    def test_background_charge_does_not_start(self):
        with mock.patch("threading.Thread") as thread:
            fees.charge_fee_in_background(1008, 14, 2167)
        thread.assert_not_called()

    def test_retry_explains_it_is_not_active(self):
        r = run(fees.retry_fee({"companyId": 1008, "loanId": 14}, 2167))
        self.assertEqual(r.status_code, 400)
        self.assertIn("aún no está activo", json.loads(r.body)["error"])


class WebhookTest(unittest.TestCase):
    def setUp(self):
        self.sp = FakeSP(fee=FEE)
        mock.patch.object(fees, "_exec", self.sp).start()
        self.push = mock.patch.object(fees, "push_in_background").start()
        mock.patch.object(fees, "log_workflow_step").start()
        self.refund = mock.patch.object(fees.stripe.Refund, "create").start()

    def tearDown(self):
        mock.patch.stopall()

    def test_succeeded_marks_paid_and_notifies(self):
        run(fees.handle_fee_webhook_event("payment_intent.succeeded", {
            "id": "pi_1", "metadata": {"type": "platform_fee", "companyId": "1008", "loanId": "14",
                                       "lenderClientId": "2167"}}))
        mark = [c for c in self.sp.calls if c["action"] == "mark_webhook"][0]
        self.assertEqual((mark["stripePaymentIntentId"], mark["status"]), ("pi_1", "PAID"))
        self.assertEqual(self.push.call_args.args[2], "platform_fee_paid")

    def test_success_on_a_cancelled_fee_is_refunded(self):
        self.sp.write_result = ("REFUNDED", "Invalid webhook status transition", "1")
        run(fees.handle_fee_webhook_event("payment_intent.succeeded", {"id": "pi_1", "metadata": {"loanId": "14"}}))
        self.refund.assert_called_once()
        self.push.assert_not_called()

    def test_partial_refund_does_not_refund_the_fee(self):
        run(fees.handle_fee_webhook_event("charge.refunded", {"payment_intent": "pi_1", "refunded": False}))
        self.assertEqual(self.sp.calls, [])

    def test_full_refund_marks_refunded(self):
        run(fees.handle_fee_webhook_event("charge.refunded", {
            "payment_intent": "pi_1", "refunded": True, "refunds": {"data": [{"id": "re_1"}]}}))
        mark = self.sp.calls[0]
        self.assertEqual((mark["status"], mark["stripeRefundId"]), ("REFUNDED", "re_1"))


class StripeWebhookRoutingTest(unittest.TestCase):
    EVENT = {"type": "payment_intent.succeeded",
             "data": {"object": {"id": "pi_1", "metadata": {"type": "platform_fee"}}}}

    def _call(self, secret):
        app = FastAPI()
        app.post("/stripe/webhook")(sp.handle_webhook)
        with mock.patch.object(sp, "WEBHOOK_SECRET", secret), \
                mock.patch.object(sp, "CONNECT_WEBHOOK_SECRET", ""), \
                mock.patch.object(sp.stripe.Webhook, "construct_event"), \
                mock.patch.object(fees, "handle_fee_webhook_event", new_callable=mock.AsyncMock) as handler, \
                mock.patch.object(sp, "_sp_transaction") as wallet:
            r = TestClient(app).post("/stripe/webhook", content=json.dumps(self.EVENT),
                                     headers={"stripe-signature": "t=1,v1=x"})
            return r, handler, wallet

    def test_fee_event_needs_a_verified_signature(self):
        r, handler, _ = self._call("")
        self.assertEqual(r.status_code, 400)
        handler.assert_not_called()

    def test_verified_fee_event_goes_to_the_fee_module_not_the_wallet(self):
        r, handler, wallet = self._call("whsec_real")
        self.assertEqual(r.status_code, 200)
        handler.assert_called_once()
        wallet.assert_not_called()


class FundingLockTest(unittest.TestCase):
    def tearDown(self):
        mock.patch.stopall()

    def _fee(self, fee):
        mock.patch.object(fees, "fee_for_loan", return_value=fee).start()

    def test_unpaid_fee_blocks(self):
        self._fee({**FEE, "status": "PENDING"})
        self.assertIsNotNone(fees.require_fee_paid(1008, 14))

    def test_paid_fee_allows(self):
        self._fee({**FEE, "status": "PAID"})
        self.assertIsNone(fees.require_fee_paid(1008, 14))

    def test_loan_without_fee_allowed_until_enforced(self):
        self._fee(None)
        with mock.patch.dict(os.environ, {"PLATFORM_FEE_ENFORCED": ""}):
            self.assertIsNone(fees.require_fee_paid(1008, 14))
        with mock.patch.dict(os.environ, {"PLATFORM_FEE_ENFORCED": "true", "PLATFORM_FEE_CHARGE_ENABLED": "true"}):
            self.assertIsNotNone(fees.require_fee_paid(1008, 14))

    def test_enforced_without_charging_never_locks_a_loan_with_no_fee(self):
        self._fee(None)
        with mock.patch.dict(os.environ, {"PLATFORM_FEE_ENFORCED": "true", "PLATFORM_FEE_CHARGE_ENABLED": ""}):
            self.assertIsNone(fees.require_fee_paid(1008, 14))


class FundingIntentHookTest(unittest.TestCase):
    def test_creating_a_funding_intent_charges_the_lender(self):
        with mock.patch.object(fees, "charge_fee_in_background") as charge:
            payment_intents._platform_fee_hooks(
                {"paymentIntents": [{"action": "create", "intentType": "FUNDING"}]},
                {"paymentIntentId": 5, "intentType": "FUNDING", "companyId": 1008, "loanId": 14,
                 "payerClientId": 2167})
        charge.assert_called_once_with(1008, 14, 2167)

    def test_installment_intents_do_not_charge(self):
        with mock.patch.object(fees, "charge_fee_in_background") as charge:
            payment_intents._platform_fee_hooks(
                {"paymentIntents": [{"action": "create"}]},
                {"paymentIntentId": 6, "intentType": "INSTALLMENT", "companyId": 1008, "loanId": 14})
        charge.assert_not_called()


class RoutesTest(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(routes.router)
        self.client = TestClient(app)

    def tearDown(self):
        mock.patch.stopall()

    def test_no_session_is_rejected(self):
        r = self.client.post("/platformFees/client-secret", json={"companyId": 1008, "loanId": 14})
        self.assertEqual(r.status_code, 401)

    def test_another_lenders_fee_is_not_found(self):
        mock.patch.object(routes, "decode", return_value={"clientId": 999}).start()
        mock.patch.object(fees, "fee_for_loan", return_value=dict(FEE)).start()
        r = self.client.post("/platformFees/client-secret", json={"companyId": 1008, "loanId": 14},
                             headers={"Authorization": "Bearer t"})
        self.assertEqual(r.status_code, 404)

    def test_there_is_no_route_that_writes_a_status(self):
        paths = {r.path for r in routes.router.routes}
        self.assertNotIn("/platformFees", paths)
        self.assertNotIn("/platformFees/webhook", paths)
        self.assertNotIn("/platformFees/charge", paths)


if __name__ == "__main__":
    unittest.main()
