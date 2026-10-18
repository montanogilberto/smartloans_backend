"""
The customer message for a sale: total + discount + POS rewards line, and the
ticket link appended by the dispatch connector. Also the server-side POS earn
that feeds the rewards line. No database: the SP calls are stubbed.

Run:  venv/bin/python -m unittest tests/test_sale_message.py -v

Fixture catalog = company 1 (gmoLavanderia) on 2026-10-06: three discounts
(100/250/500 pts) and seven "gratis (3x1)" free products at 3 pts. Free
products are earned by units bought of that product, not the points balance.
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.posRewards as pr  # noqa: E402
from modules.income import sale_message  # noqa: E402

CATALOG = [
    {"catalogItemId": 2, "name": "$10 de descuento", "rewardType": "discount_fixed", "requiredPoints": 100.0, "isActive": True},
    {"catalogItemId": 5, "name": "Servicio de lavado gratis (3x1)", "rewardType": "free_product", "requiredPoints": 3.0, "isActive": True},
    {"catalogItemId": 6, "name": "Servicio de secado gratis (3x1)", "rewardType": "free_product", "requiredPoints": 3.0, "isActive": True},
    {"catalogItemId": 3, "name": "$25 de descuento", "rewardType": "discount_fixed", "requiredPoints": 250.0, "isActive": True},
    {"catalogItemId": 11, "name": "Garrafon gratis (3x1)", "rewardType": "free_product", "requiredPoints": 3.0, "isActive": False},
]


def units(item, available, required=3.0):
    """A free_product item as earn_and_summarize returns it (redeem SP's unit check)."""
    return {**item, "unitsRequired": required, "unitsAvailable": available}


LAVADO, SECADO = CATALOG[1], CATALOG[2]
DISCOUNTS = [CATALOG[0], CATALOG[3]]


def summary(earned, balance, catalog=None):
    if catalog is None:
        catalog = DISCOUNTS + [units(LAVADO, 0), units(SECADO, 0)]
    return {"pointsEarned": earned, "balance": balance, "catalog": catalog}


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
    def test_points_balance_never_unlocks_a_free_product(self):
        # The 2026-10-16 SMS bug: 5 pts announced "Garrafon gratis (3x1)"
        # although redeeming it needs 3 garrafones bought.
        label = pr.rewards_label(summary(2, 5))
        self.assertNotIn("Ya puede canjear", label)
        self.assertEqual(label, "Puntos: +2 · Saldo: 5 pts · Le faltan 95 pts para: $10 de descuento")

    def test_free_product_ready_when_units_bought(self):
        self.assertEqual(pr.rewards_label(summary(1, 1, DISCOUNTS + [units(LAVADO, 3), units(SECADO, 1)])),
                         "Puntos: +1 · Saldo: 1 pts · ¡Ya puede canjear: Servicio de lavado gratis (3x1)!")

    def test_ready_counts_free_products_and_points_rewards(self):
        label = pr.rewards_label(summary(1, 120, DISCOUNTS + [units(LAVADO, 4), units(SECADO, 0)]))
        self.assertEqual(label, "Puntos: +1 · Saldo: 120 pts · ¡Ya puede canjear: Servicio de lavado gratis (3x1) y 1 más!")

    def test_points_reward_ready_names_the_most_valuable(self):
        self.assertEqual(pr.rewards_label(summary(1, 260)),
                         "Puntos: +1 · Saldo: 260 pts · ¡Ya puede canjear: $25 de descuento y 1 más!")

    def test_closest_started_free_product(self):
        self.assertEqual(pr.rewards_label(summary(2, 2, DISCOUNTS + [units(LAVADO, 1), units(SECADO, 2)])),
                         "Puntos: +2 · Saldo: 2 pts · Le falta 1 compra para: Servicio de secado gratis (3x1)")
        self.assertEqual(pr.rewards_label(summary(1, 1, [units(LAVADO, 1)])),
                         "Puntos: +1 · Saldo: 1 pts · Le faltan 2 compras para: Servicio de lavado gratis (3x1)")

    def test_no_points_earned_still_shows_balance(self):
        self.assertEqual(pr.rewards_label({"pointsEarned": 0, "balance": 99, "catalog": DISCOUNTS}),
                         "Saldo: 99 pts · Le falta 1 pt para: $10 de descuento")

    def test_free_product_without_unit_status_is_never_promised(self):
        self.assertEqual(pr.rewards_label(summary(2, 5, [LAVADO])), "Puntos: +2 · Saldo: 5 pts")

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

    def test_posts_points_then_reads_active_catalog_and_free_product_units(self):
        fake, calls = self._sp({
            "sp_posRewardTransactions_earnFromTicket": {"pointsEarned": 2.0, "newBalance": 2.0, "transactionId": 9},
            "sp_posRewardCatalogItems": {"result": [{"posRewardCatalogItems": CATALOG}]},
            "sp_posRewardFreeProductStatus": {"result": [{"posRewardFreeProductStatus": [
                {"catalogItemId": 5, "freeProductId": 1002, "requiredUnits": 3.0, "unitsPurchased": 4.0, "unitsAvailable": 1.0},
                {"catalogItemId": 6, "freeProductId": 1003, "requiredUnits": 3.0, "unitsPurchased": 0.0, "unitsAvailable": 0.0},
            ]}]},
        })
        with mock.patch.object(pr, "_sp", side_effect=fake):
            out = pr.earn_and_summarize(earn_json(2260, 4868))
        self.assertEqual(calls[0], ("sp_posRewardTransactions_earnFromTicket",
                                    earn_json(2260, 4868)))  # json_file passed straight through
        self.assertEqual(calls[1][1]["posRewardCatalogItems"][0]["activeOnly"], 1)
        self.assertEqual(calls[2][1], {"posRewardFreeProductStatus": [{"companyId": 1, "clientId": 2260}]})
        self.assertEqual((out["pointsEarned"], out["balance"]), (2.0, 2.0))
        names = [i["name"] for i in out["catalog"]]
        self.assertNotIn("Garrafon gratis (3x1)", names)  # inactive dropped
        lavado = next(i for i in out["catalog"] if i["catalogItemId"] == 5)
        self.assertEqual((lavado["unitsRequired"], lavado["unitsAvailable"]), (3.0, 1.0))

    def test_free_product_status_failure_drops_free_products_only(self):
        fake, _ = self._sp({
            "sp_posRewardTransactions_earnFromTicket": {"pointsEarned": 2.0, "newBalance": 2.0},
            "sp_posRewardCatalogItems": {"result": [{"posRewardCatalogItems": CATALOG}]},
            "sp_posRewardFreeProductStatus": {"error": "Could not find stored procedure"},
        })
        with mock.patch.object(pr, "_sp", side_effect=fake):
            out = pr.earn_and_summarize(earn_json(2260, 4868))
        self.assertEqual([i["catalogItemId"] for i in out["catalog"]], [2, 3])

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
