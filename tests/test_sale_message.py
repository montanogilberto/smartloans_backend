"""
The customer message for a sale: total + discount + POS rewards line, and the
ticket link appended by the dispatch connector. Also the server-side POS earn
that feeds the rewards line. No database: the SP calls are stubbed.

Run:  venv/bin/python -m unittest tests/test_sale_message.py -v

Fixture catalog = company 1 (gmoLavanderia) on 2026-10-06: three discounts
(100/250/500 pts) and seven "gratis (3x1)" free products at 3 pts.
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.posRewards as pr  # noqa: E402
from modules.income import sale_message  # noqa: E402

CATALOG = [
    {"name": "$10 de descuento", "requiredPoints": 100.0, "isActive": True},
    {"name": "Servicio de lavado gratis (3x1)", "requiredPoints": 3.0, "isActive": True},
    {"name": "Servicio de secado gratis (3x1)", "requiredPoints": 3.0, "isActive": True},
    {"name": "$25 de descuento", "requiredPoints": 250.0, "isActive": True},
    {"name": "Garrafon gratis (3x1)", "requiredPoints": 3.0, "isActive": False},
]


def summary(earned, balance, catalog=CATALOG):
    return {"pointsEarned": earned, "balance": balance, "catalog": [i for i in catalog if i["isActive"]]}


def earn_json(client_id, income_id):
    return {"posRewardTransactions": [{"companyId": 1, "clientId": client_id, "incomeId": income_id}]}


class SaleMessageTest(unittest.TestCase):
    def test_total_only(self):
        self.assertEqual(sale_message({"total": 390.0}), "Gracias por su compra. Total: $390.00 MXN")

    def test_total_discount_and_rewards_one_per_line(self):
        msg = sale_message({"total": 180.0, "discountAmount": 180.0, "promoCode": "2X1", "rewardsLine": "Puntos: +2 · Saldo: 2 pts"})
        self.assertEqual(msg.split("\n"), [
            "Gracias por su compra. Total: $180.00 MXN",
            "Descuento aplicado (2X1): -$180.00 MXN",
            "Puntos: +2 · Saldo: 2 pts",
        ])

    def test_unknown_total_still_thanks(self):
        self.assertEqual(sale_message({"total": None}), "Gracias por su compra.")

    def test_thousands_separator(self):
        self.assertIn("$1,250.50", sale_message({"total": 1250.5}))


class RewardsLabelTest(unittest.TestCase):
    def test_client_2260_after_ticket_4868(self):
        # earned 2, balance 2: the 3-pt free services are 1 point away
        self.assertEqual(pr.rewards_label(summary(2, 2)),
                         "Puntos: +2 · Saldo: 2 pts · Le falta 1 pt para: Servicio de lavado gratis (3x1)")

    def test_reward_ready_names_the_best_one_and_counts_the_rest(self):
        label = pr.rewards_label(summary(1, 120))
        self.assertTrue(label.startswith("Puntos: +1 · Saldo: 120 pts · ¡Ya puede canjear: $10 de descuento y 2 más!"))

    def test_plural_when_several_points_missing(self):
        self.assertEqual(pr.rewards_label({"pointsEarned": 1, "balance": 1, "catalog": CATALOG[1:2]}),
                         "Puntos: +1 · Saldo: 1 pts · Le faltan 2 pts para: Servicio de lavado gratis (3x1)")

    def test_no_points_earned_still_shows_balance(self):
        self.assertEqual(pr.rewards_label({"pointsEarned": 0, "balance": 2, "catalog": CATALOG[1:2]}),
                         "Saldo: 2 pts · Le falta 1 pt para: Servicio de lavado gratis (3x1)")

    def test_nothing_to_say(self):
        self.assertEqual(pr.rewards_label(None), "")
        self.assertEqual(pr.rewards_label(summary(0, 0)), "")

    def test_no_catalog_just_points(self):
        self.assertEqual(pr.rewards_label(summary(2, 2, [])), "Puntos: +2 · Saldo: 2 pts")


class EarnAndSummarizeTest(unittest.TestCase):
    def _sp(self, responses):
        calls = []

        def fake(proc, payload):
            calls.append((proc, payload))
            return responses[proc]
        return fake, calls

    def test_posts_points_then_reads_active_catalog(self):
        fake, calls = self._sp({
            "sp_posRewardTransactions_earnFromTicket": {"pointsEarned": 2.0, "newBalance": 2.0, "transactionId": 9},
            "sp_posRewardCatalogItems": {"result": [{"posRewardCatalogItems": CATALOG}]},
        })
        with mock.patch.object(pr, "_sp", side_effect=fake):
            out = pr.earn_and_summarize(earn_json(2260, 4868))
        self.assertEqual(calls[0], ("sp_posRewardTransactions_earnFromTicket",
                                    earn_json(2260, 4868)))  # json_file passed straight through
        self.assertEqual(calls[1][1]["posRewardCatalogItems"][0]["activeOnly"], 1)
        self.assertEqual((out["pointsEarned"], out["balance"]), (2.0, 2.0))
        self.assertNotIn("Garrafon gratis (3x1)", [i["name"] for i in out["catalog"]])  # inactive dropped

    def test_walk_in_never_earns(self):
        with mock.patch.object(pr, "_sp") as sp:
            self.assertIsNone(pr.earn_and_summarize(earn_json(1, 4900)))
        sp.assert_not_called()

    def test_sp_error_means_no_rewards_line_not_a_failed_sale(self):
        fake, _ = self._sp({"sp_posRewardTransactions_earnFromTicket": {"error": "boom"}})
        with mock.patch.object(pr, "_sp", side_effect=fake):
            self.assertIsNone(pr.earn_and_summarize(earn_json(2260, 4868)))
        with mock.patch.object(pr, "_sp", side_effect=RuntimeError("db down")):
            self.assertIsNone(pr.earn_and_summarize(earn_json(2260, 4868)))


if __name__ == "__main__":
    unittest.main()
