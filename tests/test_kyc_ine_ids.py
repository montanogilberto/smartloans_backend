"""RFC-015 step 1: CIC/OCR from the INE back are stored next to the KYC row,
only with the exact digit count, through sp_clientFaceRecognitions_ineIds."""
import json
import unittest
from unittest import mock

from modules import clientFaceRecognitions as cfr


class CleanIneIdsTests(unittest.TestCase):
    def test_keeps_exact_digit_counts(self):
        self.assertEqual(cfr.clean_ine_ids("123 456 789", "1234<567890123"),
                         {"cic": "123456789", "ocr": "1234567890123"})

    def test_drops_wrong_or_empty_values(self):
        self.assertEqual(cfr.clean_ine_ids("1234567890", "123"), {})
        self.assertEqual(cfr.clean_ine_ids("", None), {})

    def test_vigencia_keeps_the_last_year(self):
        self.assertEqual(cfr.clean_ine_ids("", "", "2023 - 2033"), {"vigencia": "2033"})
        self.assertEqual(cfr.clean_ine_ids("", "", "1999"), {})
        self.assertEqual(cfr.clean_ine_ids("", "", "??"), {})

    def test_keeps_one_when_the_other_is_bad(self):
        self.assertEqual(cfr.clean_ine_ids("123456789", "12"), {"cic": "123456789"})


class SaveHookTests(unittest.TestCase):
    def run_save(self, item, sp_row=("42", "ok", 0)):
        main_cursor = mock.Mock()
        main_cursor.fetchone.return_value = sp_row
        ids_cursor = mock.Mock()
        ids_cursor.fetchone.return_value = ('{"updated":1}',)
        main_conn, ids_conn = mock.Mock(), mock.Mock()
        main_conn.cursor.return_value, ids_conn.cursor.return_value = main_cursor, ids_cursor
        with mock.patch.object(cfr, "connection", side_effect=[main_conn, ids_conn]):
            res = cfr.clientFaceRecognitions_sp({"clientFaceRecognitions": [item]})
        return res, main_cursor, ids_cursor

    BASE = {"action": 2, "companyId": 1, "clientId": 3371, "clientFaceRecognitionId": 42}

    def test_valid_ids_are_written_to_the_saved_row(self):
        res, _, ids_cursor = self.run_save({**self.BASE, "cic": "123456789", "ocr": "1234567890123"})
        self.assertEqual(json.loads(res.body)["clientFaceRecognitionId"], 42)
        sql, params = ids_cursor.execute.call_args.args
        self.assertIn("sp_clientFaceRecognitions_ineIds", sql)
        sent = json.loads(params[0])["clientFaceRecognitions"][0]
        self.assertEqual(sent, {"action": "set", "companyId": 1, "clientId": 3371,
                                "clientFaceRecognitionId": 42, "cic": "123456789", "ocr": "1234567890123"})

    def test_vigencia_alone_is_written(self):
        _, _, ids_cursor = self.run_save({**self.BASE, "vigencia": "2033"})
        sent = json.loads(ids_cursor.execute.call_args.args[1][0])["clientFaceRecognitions"][0]
        self.assertEqual(sent["vigencia"], "2033")
        self.assertNotIn("cic", sent)

    def test_no_ids_in_payload_means_no_extra_call(self):
        main_cursor = mock.Mock()
        main_cursor.fetchone.return_value = ("42", "ok", 0)
        conn = mock.Mock()
        conn.cursor.return_value = main_cursor
        with mock.patch.object(cfr, "connection", return_value=conn) as connection:
            cfr.clientFaceRecognitions_sp({"clientFaceRecognitions": [dict(self.BASE)]})
        self.assertEqual(connection.call_count, 1)

    def test_invalid_ids_are_not_sent(self):
        main_cursor = mock.Mock()
        main_cursor.fetchone.return_value = ("42", "ok", 0)
        conn = mock.Mock()
        conn.cursor.return_value = main_cursor
        with mock.patch.object(cfr, "connection", return_value=conn) as connection:
            cfr.clientFaceRecognitions_sp({"clientFaceRecognitions": [{**self.BASE, "cic": "12", "ocr": ""}]})
        self.assertEqual(connection.call_count, 1)

    def test_a_failed_main_save_writes_nothing(self):
        main_cursor = mock.Mock()
        main_cursor.fetchone.return_value = ("42", "fallo", 1)
        conn = mock.Mock()
        conn.cursor.return_value = main_cursor
        with mock.patch.object(cfr, "connection", return_value=conn) as connection:
            cfr.clientFaceRecognitions_sp({"clientFaceRecognitions": [{**self.BASE, "cic": "123456789"}]})
        self.assertEqual(connection.call_count, 1)

    def test_ids_failure_never_fails_the_kyc_save(self):
        main_cursor = mock.Mock()
        main_cursor.fetchone.return_value = ("42", "ok", 0)
        main_conn = mock.Mock()
        main_conn.cursor.return_value = main_cursor
        with mock.patch.object(cfr, "connection", side_effect=[main_conn, RuntimeError("no SP yet")]):
            res = cfr.clientFaceRecognitions_sp({"clientFaceRecognitions": [{**self.BASE, "cic": "123456789"}]})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(json.loads(res.body)["clientFaceRecognitionId"], 42)


if __name__ == "__main__":
    unittest.main()
