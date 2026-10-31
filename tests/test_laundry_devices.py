"""
GMO Laundry ESP32 controllers: device key, fixed signed client QR, cycle
chosen on the machine's screen, idempotent authorize with a LAUNDRY_USAGE
debit in walletTransactions.

The SPs are faked in memory (FakeDb) with the same contract as
sql/migrations/2026-10-18_laundry_devices.sql; the ledger is faked with the
idempotency + no-overdraft behaviour of sp_walletTransactions.

Run:  venv/bin/python -m unittest tests/test_laundry_devices.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.laundryDevices as ld  # noqa: E402
import routes_.laundryDevices as routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402

DEVICE_KEY = "test-device-key"
# productOptionChoices of the live catalog: 1002 Servicio de lavado / 1003 Servicio de secado
CHOICES = {1004: (1002, "Basico", 40.0), 1006: (1002, "Carga Alta", 70.0), 1009: (1003, "50 Min", 70.0)}
DESCRIPTIONS = {1004: "Agua baja", 1006: "Agua alta", 1009: None}
CLIENTS = {2260: "Juan"}   # active clients of company 1


class FakeDb:
    def __init__(self, balance=100.0):
        self.device = {"deviceId": 7, "companyId": 1, "branchId": None, "name": "Lavadora 1",
                       "machineType": "washer", "productId": 1002, "priceMXN": None, "cycleMinutes": 45,
                       "keyHash": ld.hash_key(DEVICE_KEY), "isActive": 1}
        self.uses, self.ledger, self.balance = {}, {}, balance
        self.ledger_error = None
        self.calls = []
        self.combo = []      # laundryDeviceProducts rows: productIds in tab order
        self.labels = {}

    def products(self):
        if self.combo:
            return self.combo
        return [self.device["productId"]] if self.device["productId"] else []

    def sp(self, proc, payload):
        self.calls.append((proc, payload))
        root = next(iter(payload))
        row = payload[root][0]
        if proc == "sp_laundryDevices":
            if row["action"] == 4:
                return dict(self.device) if row["deviceId"] == self.device["deviceId"] else {"error": "device_not_found"}
            if row["action"] == 5:
                return {**{k: v for k, v in self.device.items() if k != "keyHash"}, "serverTimeUtc": "2026-10-18T08:00:00"}
            if row["action"] == 1:
                return {"deviceId": 8, "companyId": row["companyId"], "name": row["name"]}
            if row["action"] == 6:
                choice = row.get("productOptionChoiceId")
                if self.device["productId"] is None:
                    if choice is not None:
                        return {"error": "choice_not_for_device"}
                    return {"priceMXN": self.device["priceMXN"]}
                product, name, price = CHOICES.get(choice, (None, None, None))
                if product not in self.products():
                    return {"error": "choice_not_for_device"}
                return {"priceMXN": price, "productOptionChoiceId": choice, "choiceName": name, "productId": product}
            if row["action"] == 7:
                labels = {1002: "Servicio de lavado", 1003: "Servicio de secado", **self.labels}
                return {"cycles": [{"productOptionChoiceId": cid, "name": name, "priceMXN": price,
                                    "description": DESCRIPTIONS[cid], "productId": product,
                                    "groupLabel": labels[product], "groupOrder": order}
                                   for order, prod in enumerate(self.products())
                                   for cid, (product, name, price) in CHOICES.items() if product == prod]}
            if row["action"] == 8:
                name = CLIENTS.get(row["clientId"])
                return {"clientId": row["clientId"], "firstName": name} if name else {"error": "client_not_found"}
        if proc == "sp_laundryDeviceUses":
            if row["action"] == 1:
                key = (row["deviceId"], row["requestId"])
                if key in self.uses:
                    use = self.uses[key]
                    if (use["clientId"], use["productOptionChoiceId"]) != (row["clientId"], row["productOptionChoiceId"]):
                        return {"error": "request_conflict"}
                    return {**use, "replayed": 1}
                use = {"useId": len(self.uses) + 1, "status": "pending", "reason": None, **row}
                self.uses[key] = use
                return {**use, "replayed": 0}
            if row["action"] == 2:
                use = next(u for u in self.uses.values() if u["useId"] == row["useId"])
                if use["status"] == "pending":
                    use.update({k: v for k, v in row.items() if k not in ("action", "useId")})
                return {**use, "replayed": 0}
        raise AssertionError(f"unexpected {proc} {payload}")

    def post_entry(self, **kw):
        if self.ledger_error:
            return {"error": self.ledger_error}
        key = kw["idempotency_key"]
        if key in self.ledger:
            return {**self.ledger[key], "replayed": "true"}
        if self.balance - kw["amount_mxn"] < 0:
            return {"error": "Saldo insuficiente", "available": self.balance}
        self.balance -= kw["amount_mxn"]
        entry = {"entryId": 900 + len(self.ledger), "balanceAfter": self.balance, **kw}
        self.ledger[key] = entry
        return entry


class Base(unittest.TestCase):
    def setUp(self):
        self.db = FakeDb()
        patches = [
            mock.patch.dict(os.environ, {"LAUNDRY_QR_SECRET": "s3cret"}),
            mock.patch.object(ld, "_sp", side_effect=self.db.sp),
            mock.patch.object(ld, "post_entry", side_effect=self.db.post_entry),
            mock.patch.object(ld, "get_balance",
                              side_effect=lambda company, client: {"availableBalance": self.db.balance}),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        app = FastAPI()
        app.include_router(routes.router)
        self.client = TestClient(app)

    def qr(self, company_id=1, client_id=2260):
        return ld.client_qr_text(company_id, client_id)

    def authorize(self, qr, choice=1004, request_id="req-00000001", key=DEVICE_KEY, device_id="7"):
        body = {"requestId": request_id, "clientQr": qr}
        if choice is not None:
            body["productOptionChoiceId"] = choice
        return self.client.post("/laundryDevices/authorize",
                                headers={"X-Device-Id": device_id, "X-Device-Key": key}, json=body)


class ClientQrTest(Base):
    def test_round_trip(self):
        qr = self.qr()
        self.assertTrue(qr.startswith("GMO1.1.2260."))
        self.assertEqual(ld.verify_client_qr(qr), {"companyId": 1, "clientId": 2260})

    def test_scanner_line_endings_are_ignored(self):
        self.assertEqual(ld.verify_client_qr(self.qr() + "\r\n")["clientId"], 2260)

    def test_changing_the_client_breaks_the_signature(self):
        prefix, company, _, sig = self.qr().split(".")
        with self.assertRaisesRegex(ValueError, "qr_invalid"):
            ld.verify_client_qr(f"{prefix}.{company}.2261.{sig}")

    def test_plain_client_id_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "qr_malformed"):
            ld.verify_client_qr("2260")

    def test_cycle_minutes(self):
        device = {"cycleMinutes": 45}
        self.assertEqual(ld.cycle_minutes("50 Min", device), 50)
        self.assertEqual(ld.cycle_minutes("Carga Alta", device), 45)
        self.assertEqual(ld.cycle_minutes(None, device), 45)

    def test_endpoint(self):
        r = self.client.post("/laundryDevices/clientQr", json={"laundryDevices": [{"companyId": 1, "clientId": 2260}]})
        self.assertEqual(r.json()["clientQr"], self.qr())

    def test_endpoint_needs_secret(self):
        with mock.patch.dict(os.environ, {"LAUNDRY_QR_SECRET": ""}):
            r = self.client.post("/laundryDevices/clientQr", json={"laundryDevices": [{"companyId": 1, "clientId": 2}]})
        self.assertEqual(r.status_code, 503)


class AuthorizeTest(Base):
    def test_charges_the_chosen_cycle_once(self):
        r = self.authorize(self.qr(), choice=1006)
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertTrue(body["authorized"])
        self.assertEqual((body["amountMXN"], body["choiceName"], body["balanceAfter"], body["cycleMinutes"]),
                         (70.0, "Carga Alta", 30.0, 45))
        entry = next(iter(self.db.ledger.values()))
        self.assertEqual((entry["entry_type"], entry["direction"], entry["client_id"]), ("LAUNDRY_USAGE", "D", 2260))
        self.assertEqual(entry["idempotency_key"], "laundry:7:req-00000001")

    def test_retry_with_same_request_id_does_not_double_charge(self):
        self.authorize(self.qr())
        r = self.authorize(self.qr())
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["replayed"])
        self.assertEqual(self.db.balance, 60.0)
        self.assertEqual(len(self.db.ledger), 1)

    def test_same_client_can_pay_again_with_a_new_request(self):
        self.authorize(self.qr())
        self.assertEqual(self.authorize(self.qr(), request_id="req-00000002").status_code, 200)
        self.assertEqual(self.db.balance, 20.0)

    def test_same_request_id_with_other_cycle_is_conflict(self):
        self.authorize(self.qr(), choice=1004)
        r = self.authorize(self.qr(), choice=1006)
        self.assertEqual((r.status_code, r.json()["reason"]), (409, "request_conflict"))

    def test_insufficient_funds_is_402(self):
        self.db.balance = 10.0
        r = self.authorize(self.qr())
        body = r.json()
        self.assertEqual((r.status_code, body["reason"]), (402, "insufficient_funds"))
        self.assertEqual((body["availableBalance"], body["missingMXN"]), (10.0, 30.0))
        self.db.balance = 50.0  # client tops up, ESP32 starts a new request
        self.assertEqual(self.authorize(self.qr(), request_id="req-00000002").status_code, 200)

    def test_replayed_402_still_reports_the_balance(self):
        self.db.balance = 25.0
        self.authorize(self.qr())
        body = self.authorize(self.qr()).json()
        self.assertTrue(body["replayed"])
        self.assertEqual((body["availableBalance"], body["missingMXN"]), (25.0, 15.0))

    def test_ledger_failure_leaves_use_pending_and_retry_settles(self):
        self.db.ledger_error = "timeout"
        self.assertEqual(self.authorize(self.qr()).status_code, 502)
        self.db.ledger_error = None
        self.assertEqual(self.authorize(self.qr()).status_code, 200)
        self.assertEqual(len(self.db.ledger), 1)

    def test_dryer_cycle_on_the_washer_is_rejected(self):
        r = self.authorize(self.qr(), choice=1009)
        self.assertEqual((r.status_code, r.json()["reason"]), (400, "choice_not_for_device"))
        self.assertEqual(self.db.ledger, {})

    def test_missing_cycle_on_catalog_device_is_rejected(self):
        self.assertEqual(self.authorize(self.qr(), choice=None).status_code, 400)

    def test_combo_machine_accepts_wash_and_dry_cycles(self):
        self.db.device["machineType"] = "combo"
        self.db.combo = [1002, 1003]
        self.db.balance = 500.0
        self.assertEqual(self.authorize(self.qr(), choice=1004).json()["cycleMinutes"], 45)
        body = self.authorize(self.qr(), choice=1009, request_id="req-00000002").json()
        self.assertEqual((body["amountMXN"], body["cycleMinutes"]), (70.0, 50))

    def test_dryer_takes_minutes_from_the_cycle(self):
        self.db.device.update(machineType="dryer", productId=1003)
        body = self.authorize(self.qr(), choice=1009).json()
        self.assertEqual((body["amountMXN"], body["cycleMinutes"]), (70.0, 50))

    def test_fixed_price_device_without_cycle(self):
        self.db.device.update(productId=None, priceMXN=35.0)
        body = self.authorize(self.qr(), choice=None).json()
        self.assertEqual((body["amountMXN"], body["cycleMinutes"]), (35.0, 45))

    def test_plain_client_id_qr(self):
        r = self.authorize("2260")
        self.assertEqual((r.status_code, r.json()["reason"]), (401, "qr_malformed"))
        self.assertEqual(self.db.ledger, {})

    def test_wrong_key(self):
        self.assertEqual(self.authorize(self.qr(), key="nope").status_code, 401)
        self.assertEqual(self.db.ledger, {})

    def test_inactive_device(self):
        self.db.device["isActive"] = 0
        self.assertEqual(self.authorize(self.qr()).status_code, 403)

    def test_qr_from_other_company(self):
        r = self.authorize(self.qr(company_id=2))
        self.assertEqual((r.status_code, r.json()["reason"]), (401, "qr_wrong_company"))

    def test_bad_request_id(self):
        self.assertEqual(self.authorize(self.qr(), request_id="x").status_code, 400)


class QuoteTest(Base):
    def quote(self, qr, choice=1004, key=DEVICE_KEY):
        body = {"clientQr": qr}
        if choice is not None:
            body["productOptionChoiceId"] = choice
        return self.client.post("/laundryDevices/quote",
                                headers={"X-Device-Id": "7", "X-Device-Key": key}, json=body)

    def test_enough_balance(self):
        r = self.quote(self.qr(), choice=1006)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), {
            "firstName": "Juan", "availableBalance": 100.0, "priceMXN": 70.0, "productOptionChoiceId": 1006,
            "choiceName": "Carga Alta", "cycleMinutes": 45, "enough": True, "missingMXN": 0,
        })

    def test_not_enough_balance(self):
        self.db.balance = 20.0
        body = self.quote(self.qr()).json()
        self.assertEqual((body["enough"], body["missingMXN"]), (False, 20.0))

    def test_never_charges_or_opens_a_use(self):
        self.quote(self.qr())
        self.assertEqual((self.db.ledger, self.db.uses, self.db.balance), ({}, {}, 100.0))

    def test_same_checks_as_authorize(self):
        self.assertEqual(self.quote(self.qr(), choice=1009).json()["reason"], "choice_not_for_device")
        self.assertEqual(self.quote("2260").json()["reason"], "qr_malformed")
        self.assertEqual(self.quote(self.qr(company_id=2)).json()["reason"], "qr_wrong_company")
        self.assertEqual(self.quote(self.qr(), key="nope").status_code, 401)

    def test_unknown_or_inactive_client(self):
        r = self.quote(self.qr(client_id=999))
        self.assertEqual((r.status_code, r.json()["reason"]), (404, "client_not_found"))


class DeviceAdminTest(Base):
    def test_heartbeat_lists_the_screen_cycles(self):
        r = self.client.post("/laundryDevices/heartbeat", headers={"X-Device-Id": "7", "X-Device-Key": DEVICE_KEY},
                             json={"status": "idle", "firmwareVersion": "0.1.0", "rssi": -61})
        self.assertEqual(r.status_code, 200)
        cycles = r.json()["cycles"]
        self.assertEqual([(c["productOptionChoiceId"], c["priceMXN"], c["description"], c["cycleMinutes"])
                          for c in cycles],
                         [(1004, 40.0, "Agua baja", 45), (1006, 70.0, "Agua alta", 45)])
        self.assertEqual((r.json()["deviceName"], r.json()["machineType"]), ("Lavadora 1", "washer"))
        sent = self.db.calls[-2][1]["laundryDevices"][0]
        self.assertEqual((sent["status"], sent["rssi"]), ("idle", -61))

    def test_heartbeat_groups_cycles_by_tab_on_a_combo(self):
        self.db.combo, self.db.labels = [1002, 1003], {1002: "Lavado", 1003: "Secado"}
        body = self.client.post("/laundryDevices/heartbeat",
                                headers={"X-Device-Id": "7", "X-Device-Key": DEVICE_KEY}).json()
        self.assertEqual(body["groups"], [{"productId": 1002, "label": "Lavado"}, {"productId": 1003, "label": "Secado"}])
        self.assertEqual([(c["productOptionChoiceId"], c["groupLabel"]) for c in body["cycles"]],
                         [(1004, "Lavado"), (1006, "Lavado"), (1009, "Secado")])

    def test_single_product_has_one_group(self):
        body = self.client.post("/laundryDevices/heartbeat",
                                headers={"X-Device-Id": "7", "X-Device-Key": DEVICE_KEY}).json()
        self.assertEqual(len(body["groups"]), 1)

    def test_heartbeat_without_body(self):
        r = self.client.post("/laundryDevices/heartbeat", headers={"X-Device-Id": "7", "X-Device-Key": DEVICE_KEY})
        self.assertEqual(r.status_code, 200)

    def test_create_returns_key_once_and_stores_only_hash(self):
        r = self.client.post("/laundryDevices", json={"laundryDevices": [{
            "action": 1, "companyId": 1, "name": "Secadora 1", "machineType": "dryer", "productId": 1003,
            "keyHash": "attacker-chosen"}]})
        key = r.json()["deviceKey"]
        sent = self.db.calls[-1][1]["laundryDevices"][0]
        self.assertEqual(sent["keyHash"], ld.hash_key(key))
        self.assertNotIn(key, json.dumps(self.db.calls))



class RegenerateClientQrsTest(Base):
    URL = "/laundryDevices/regenerateClientQrs"

    def setUp(self):
        super().setUp()
        self.uploads, self.saved = [], []
        self.client_ids = list(range(1, 6))
        real_sp = self.db.sp

        def sp(proc, payload):
            row = next(iter(payload.values()))[0]
            if proc == "sp_laundryClientQrs_list":
                ids = [c for c in self.client_ids if c > row["afterClientId"]
                       and (row["clientIds"] is None or c in row["clientIds"])]
                return {"clients": [{"clientId": c} for c in ids[:row["top"]]]}
            if proc == "sp_clients_qr":
                self.saved.append((row["clientId"], row["qrBlobUrl"]))
                return {"message": "qrBlobUrl updated"}
            return real_sp(proc, payload)

        ld._sp.side_effect = sp
        upload = mock.patch("modules.clients._upload_bytes_to_blob",
                            side_effect=lambda raw, path, ctype, meta: self.uploads.append((path, raw, meta))
                            or f"https://blob/clients/{path}")
        upload.start()
        self.addCleanup(upload.stop)
        key = mock.patch.object(worker_key, "WORKER_KEY", "wk")
        key.start()
        self.addCleanup(key.stop)

    def post(self, headers={"X-Worker-Key": "wk"}, **row):
        return self.client.post(self.URL, headers=headers, json={"clients": [{"companyId": 1, **row}]})

    def test_needs_worker_key(self):
        self.assertEqual(self.post(headers={}).status_code, 403)
        self.assertEqual(self.uploads, [])

    def test_uploads_a_signed_png_per_client_and_pages(self):
        body = self.post(top=3).json()
        self.assertEqual((body["listed"], body["updated"], body["nextAfterClientId"]), (3, 3, 3))
        path, png, meta = self.uploads[0]
        self.assertTrue(path.startswith("1/qr/qr_gmo1_"))
        self.assertTrue(png.startswith(b"\x89PNG"))
        self.assertEqual(meta["format"], "GMO1")
        self.assertEqual([c for c, _ in self.saved], [1, 2, 3])

        body = self.post(top=3, afterClientId=3).json()
        self.assertEqual((body["updated"], body["nextAfterClientId"]), (2, None))

    def test_dry_run_changes_nothing(self):
        body = self.post(dryRun=True).json()
        self.assertEqual((body["listed"], body["updated"]), (5, 0))
        self.assertEqual((self.uploads, self.saved), ([], []))

    def test_only_listed_clients(self):
        body = self.post(clientIds=[2, 4]).json()
        self.assertEqual([c for c, _ in self.saved], [2, 4])
        self.assertIsNone(body["nextAfterClientId"])

    def test_one_failure_does_not_stop_the_batch(self):
        ld._sp.side_effect, real = None, ld._sp.side_effect

        def flaky(proc, payload):
            if proc == "sp_clients_qr" and payload["clients"][0]["clientId"] == 2:
                return {"error": "boom"}
            return real(proc, payload)
        ld._sp.side_effect = flaky
        body = self.post().json()
        self.assertEqual((body["updated"], body["failed"]), (4, [{"clientId": 2, "error": "boom"}]))

    def test_png_encodes_the_signed_text(self):
        png = ld.client_qr_png(ld.client_qr_text(1, 1))
        self.assertTrue(png.startswith(b"\x89PNG"))


if __name__ == "__main__":
    unittest.main()
