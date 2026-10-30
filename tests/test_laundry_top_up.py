"""
Recarga con tarjeta del saldo prepago de GMO Lavandería (paymentType
laundry_top_up): al confirmarse el cargo se acredita el NETO en
walletTransactions (DEPOSIT, idempotente por intent) — el mismo libro que
descuenta /laundryDevices/authorize. wallet_top_up (cartera P2P) sigue yendo a
clientWallets.

Run:  venv/bin/python -m unittest tests/test_laundry_top_up.py -v
"""
import asyncio
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.stripe_payments as sp  # noqa: E402


def _tx(payment_type, status="succeeded", prev="pending"):
    return {"transactionId": 55, "paymentType": payment_type, "status": status, "prevStatus": prev,
            "amount": 10000, "fromClientId": 2260, "companyId": 1,
            "stripePaymentIntentId": "pi_abc"}


class LaundryTopUpTests(unittest.TestCase):
    def setUp(self):
        self.post_entry = mock.patch.object(sp, "post_entry", return_value={"entryId": 9, "balanceAfter": 92.4}).start()
        self.credit_wallet = mock.patch("modules.walletBalance.credit_wallet", new=mock.AsyncMock()).start()
        mock.patch.object(sp, "log_workflow_step").start()
        self.addCleanup(mock.patch.stopall)

    def settle(self, tx, net=92.4):
        asyncio.run(sp._settle_wallet_top_up(tx, net_mxn=net))

    def test_laundry_top_up_credits_ledger_net_once_per_intent(self):
        self.settle(_tx("laundry_top_up"))
        self.post_entry.assert_called_once()
        kw = self.post_entry.call_args.kwargs
        self.assertEqual(kw["entry_type"], "DEPOSIT")
        self.assertEqual(kw["direction"], "C")
        self.assertEqual(kw["amount_mxn"], 92.4)
        self.assertEqual((kw["company_id"], kw["client_id"]), (1, 2260))
        self.assertEqual(kw["idempotency_key"], "stripe:pi_abc")
        self.credit_wallet.assert_not_called()

    def test_already_settled_is_skipped(self):
        # confirm del app y webhook: sólo quien hizo pending→succeeded acredita.
        self.settle(_tx("laundry_top_up", prev="succeeded"))
        self.post_entry.assert_not_called()

    def test_not_succeeded_is_skipped(self):
        self.settle(_tx("laundry_top_up", status="processing"))
        self.post_entry.assert_not_called()

    def test_p2p_wallet_top_up_still_uses_client_wallets(self):
        self.settle(_tx("wallet_top_up"))
        self.credit_wallet.assert_awaited_once()
        self.post_entry.assert_not_called()

    def test_other_payment_types_do_not_credit(self):
        self.settle(_tx("loan_repayment"))
        self.post_entry.assert_not_called()
        self.credit_wallet.assert_not_called()


if __name__ == "__main__":
    unittest.main()
