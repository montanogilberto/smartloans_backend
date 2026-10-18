"""
GMO Laundry ESP32 controllers: device key, signed QR token, idempotent
authorize with a LAUNDRY_USAGE debit in walletTransactions.

The SPs are faked in memory (FakeDb) with the same contract as
sql/migrations/2026-10-18_laundry_devices.sql; the ledger is faked with the
idempotency + no-overdraft behaviour of sp_walletTransactions.

Run:  venv/bin/python -m unittest tests/test_laundry_devices.py -v
"""
import json
import os
import sys
import time
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.laundryDevices as ld  # noqa: E402
import routes_.laundryDevices as routes  # noqa: E402

DEVICE_KEY = "test-device-key"


class FakeDb:
    def __init__(self, balance=100.0):
        self.device = {"deviceId": 7, "companyId": 1, "branchId": None, "name": "Lavadora 1",
                       "machineType": "washer", "priceMXN": 35.0, "cycleMinutes": 45,
                       "keyHash": ld.hash_key(DEVICE_KEY), "isActive": 1}
        self.uses, self.ledger, self.balance = {}, {}, balance
        self.ledger_error = None
        self.calls = []

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
        if proc == "sp_laundryDeviceUses":
            if row["action"] == 1:
                key = (row["deviceId"], row["requestId"])
                if key in self.uses:
                    use = self.uses[key]
                    if use["tokenId"] != row["tokenId"]:
                        return {"error": "request_conflict"}
                    return {**use, "replayed": 1}
                if any(u["tokenId"] == row["tokenId"] and u["status"] in ("pending", "authorized")
                       for u in self.uses.values()):
                    return {"error": "token_used"}
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
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        app = FastAPI()
        app.include_router(routes.router)
        self.client = TestClient(app)

    def token(self, company_id=1, client_id=2260):
        return ld.issue_qr_token(company_id, client_id)["qrToken"]

    def authorize(self, token, request_id="req-00000001", key=DEVICE_KEY, device_id="7"):
        return self.client.post("/laundryDevices/authorize",
                                headers={"X-Device-Id": device_id, "X-Device-Key": key},
                                json={"requestId": request_id, "qrToken": token})


class QrTokenTest(Base):
    def test_round_trip(self):
        out = ld.verify_qr_token(self.token())
        self.assertEqual((out["companyId"], out["clientId"]), (1, 2260))

    def test_tampered_payload_is_rejected(self):
        v, payload, sig = self.token().split(".")
        forged = ld._b64e(json.dumps({"c": 1, "u": 1, "j": "x", "e": int(time.time()) + 300}).encode())
        with self.assertRaisesRegex(ValueError, "token_invalid"):
            ld.verify_qr_token(f"{v}.{forged}.{sig}")

    def test_expired(self):
        old = ld.issue_qr_token(1, 2260, now=time.time() - 3600)["qrToken"]
        with self.assertRaisesRegex(ValueError, "token_expired"):
            ld.verify_qr_token(old)

    def test_endpoint_needs_secret(self):
        with mock.patch.dict(os.environ, {"LAUNDRY_QR_SECRET": ""}):
            r = self.client.post("/laundryDevices/qrToken", json={"laundryDevices": [{"companyId": 1, "clientId": 2}]})
        self.assertEqual(r.status_code, 503)


class AuthorizeTest(Base):
    def test_charges_machine_price_once(self):
        r = self.authorize(self.token())
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertTrue(body["authorized"])
        self.assertEqual((body["amountMXN"], body["balanceAfter"], body["cycleMinutes"]), (35.0, 65.0, 45))
        entry = next(iter(self.db.ledger.values()))
        self.assertEqual((entry["entry_type"], entry["direction"], entry["client_id"]), ("LAUNDRY_USAGE", "D", 2260))
        self.assertEqual(entry["idempotency_key"], "laundry:7:req-00000001")

    def test_retry_with_same_request_id_does_not_double_charge(self):
        token = self.token()
        self.authorize(token)
        r = self.authorize(token)
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["replayed"])
        self.assertEqual(self.db.balance, 65.0)
        self.assertEqual(len(self.db.ledger), 1)

    def test_same_qr_on_new_request_is_token_used(self):
        token = self.token()
        self.authorize(token)
        r = self.authorize(token, request_id="req-00000002")
        self.assertEqual((r.status_code, r.json()["reason"]), (409, "token_used"))
        self.assertEqual(self.db.balance, 65.0)

    def test_insufficient_funds_is_402_and_qr_stays_usable(self):
        self.db.balance = 10.0
        token = self.token()
        r = self.authorize(token)
        self.assertEqual((r.status_code, r.json()["reason"]), (402, "insufficient_funds"))
        self.db.balance = 50.0  # client tops up, ESP32 starts a new request
        self.assertEqual(self.authorize(token, request_id="req-00000002").status_code, 200)

    def test_ledger_failure_leaves_use_pending_and_retry_settles(self):
        token = self.token()
        self.db.ledger_error = "timeout"
        self.assertEqual(self.authorize(token).status_code, 502)
        self.db.ledger_error = None
        r = self.authorize(token)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(self.db.ledger), 1)

    def test_wrong_key(self):
        r = self.authorize(self.token(), key="nope")
        self.assertEqual(r.status_code, 401)
        self.assertEqual(self.db.ledger, {})

    def test_inactive_device(self):
        self.db.device["isActive"] = 0
        self.assertEqual(self.authorize(self.token()).status_code, 403)

    def test_token_from_other_company(self):
        r = self.authorize(self.token(company_id=2))
        self.assertEqual((r.status_code, r.json()["reason"]), (401, "token_wrong_company"))

    def test_bad_request_id(self):
        self.assertEqual(self.authorize(self.token(), request_id="x").status_code, 400)


class DeviceAdminTest(Base):
    def test_heartbeat(self):
        r = self.client.post("/laundryDevices/heartbeat", headers={"X-Device-Id": "7", "X-Device-Key": DEVICE_KEY},
                             json={"status": "idle", "firmwareVersion": "0.1.0", "rssi": -61})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["priceMXN"], 35.0)
        sent = self.db.calls[-1][1]["laundryDevices"][0]
        self.assertEqual((sent["status"], sent["rssi"]), ("idle", -61))

    def test_heartbeat_without_body(self):
        r = self.client.post("/laundryDevices/heartbeat", headers={"X-Device-Id": "7", "X-Device-Key": DEVICE_KEY})
        self.assertEqual(r.status_code, 200)

    def test_create_returns_key_once_and_stores_only_hash(self):
        r = self.client.post("/laundryDevices", json={"laundryDevices": [{
            "action": 1, "companyId": 1, "name": "Secadora 1", "machineType": "dryer", "priceMXN": 30,
            "keyHash": "attacker-chosen"}]})
        key = r.json()["deviceKey"]
        sent = self.db.calls[-1][1]["laundryDevices"][0]
        self.assertEqual(sent["keyHash"], ld.hash_key(key))
        self.assertNotIn(key, json.dumps(self.db.calls))


if __name__ == "__main__":
    unittest.main()
