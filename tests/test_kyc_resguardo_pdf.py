"""
KYC third document — "Constancia de resguardo del pagaré físico"
(sql/migrations/2026-11-19_kyc_resguardo_pdf.sql).

Run:  venv/bin/python -m unittest tests/test_kyc_resguardo_pdf.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.clientFaceRecognitions as cfr  # noqa: E402


class WithResguardoUrlsTest(unittest.TestCase):
    def test_merges_urls_by_record_id(self):
        result = {"clientFaceRecognitions": [
            {"clientFaceRecognitionId": 1, "companyId": 1008},
            {"clientFaceRecognitionId": 2, "companyId": 1008},
        ]}
        listing = {"resguardos": [{"clientFaceRecognitionId": 2, "resguardoPdfBlobUrl": "https://x/r.pdf"}]}
        with mock.patch.object(cfr, "_resguardo_sp", return_value=listing) as sp:
            out = cfr._with_resguardo_urls(result, {"clientFaceRecognitions": [{"companyId": 1008}]})
        sp.assert_called_once_with({"action": "list", "companyId": 1008, "clientId": None})
        self.assertIsNone(out["clientFaceRecognitions"][0]["resguardoPdfBlobUrl"])
        self.assertEqual(out["clientFaceRecognitions"][1]["resguardoPdfBlobUrl"], "https://x/r.pdf")

    def test_missing_migration_leaves_rows_readable(self):
        result = {"clientFaceRecognitions": [{"clientFaceRecognitionId": 1, "companyId": 1008}]}
        with mock.patch.object(cfr, "_resguardo_sp", return_value=None):
            out = cfr._with_resguardo_urls(result, {"clientFaceRecognitions": [{"companyId": 1008}]})
        self.assertIsNone(out["clientFaceRecognitions"][0]["resguardoPdfBlobUrl"])

    def test_empty_read_skips_the_sp(self):
        with mock.patch.object(cfr, "_resguardo_sp") as sp:
            cfr._with_resguardo_urls({"clientFaceRecognitions": []}, {})
        sp.assert_not_called()


class ContractConnectorTest(unittest.IsolatedAsyncioTestCase):
    async def test_uploads_resguardo_saves_it_and_returns_three_links(self):
        uploads = []

        def fake_upload(b64, path, content_type, metadata):
            uploads.append((path, metadata["type"]))
            return f"https://blob/{path}"

        saved = cfr.JSONResponse(content={"msg": "ok", "error": False, "clientFaceRecognitionId": 55}, status_code=200)
        with mock.patch.object(cfr, "_upload_base64_to_blob", side_effect=fake_upload), \
             mock.patch.object(cfr, "clientFaceRecognitions_sp", return_value=saved), \
             mock.patch.object(cfr, "_save_resguardo_url") as save:
            resp = await cfr.contract_clientFaceRecognition_connector({
                "companyId": 1008, "clientId": 7, "clientFaceRecognitionId": 55,
                "contractPdfBase64": "QQ==", "pagarePdfBase64": "QQ==", "resguardoPdfBase64": "QQ==",
                "hasPhysicalPagare": True,
            })
        body = json.loads(resp.body)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual([t for _, t in uploads], ["contract", "pagare", "pagare_resguardo"])
        self.assertTrue(body["resguardoPdfBlobUrl"].startswith("https://blob/7/pagares/resguardo_"))
        self.assertTrue(body["contractPdfBlobUrl"].startswith("https://blob/7/contracts/contract_"))
        self.assertTrue(body["pagarePdfBlobUrl"].startswith("https://blob/7/pagares/pagare_"))
        save.assert_called_once_with(1008, 7, 55, body["resguardoPdfBlobUrl"])

    async def test_failed_save_does_not_store_resguardo(self):
        failed = cfr.JSONResponse(content={"msg": "x", "error": True}, status_code=200)
        with mock.patch.object(cfr, "_upload_base64_to_blob", return_value="https://blob/r.pdf"), \
             mock.patch.object(cfr, "clientFaceRecognitions_sp", return_value=failed), \
             mock.patch.object(cfr, "_save_resguardo_url") as save:
            await cfr.contract_clientFaceRecognition_connector({
                "companyId": 1008, "clientId": 7, "resguardoPdfBase64": "QQ==",
            })
        save.assert_not_called()


if __name__ == "__main__":
    unittest.main()
