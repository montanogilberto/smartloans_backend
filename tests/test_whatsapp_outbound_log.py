"""log_outbound_message returns the new whatsappMessages id (sp_whatsapp_messages
action 1 since 2026-11-12) and never raises; status receipts log the phone masked."""
import unittest
from unittest import mock

import modules.whatsapp as wa
import modules.whatsappCloud as wc

ROW = {"phoneNumber": "+526621380481", "messageBody": "hola", "direction": "outbound", "status": "staff_sent"}


def _conn(row=None, exc=None):
    cur = mock.MagicMock()
    if exc:
        cur.execute.side_effect = exc
    cur.fetchone.return_value = row
    conn = mock.MagicMock()
    conn.cursor.return_value = cur
    return conn, cur


class LogOutboundMessage(unittest.TestCase):
    def test_returns_new_id(self):
        conn, cur = _conn(("1234", "Message Logged Successfully", ""))
        with mock.patch.object(wa, "connection", return_value=conn):
            self.assertEqual(wa.log_outbound_message(ROW), 1234)
        self.assertIn('"action": 1', cur.execute.call_args[0][1][0])
        conn.commit.assert_called_once()

    def test_old_sp_without_id_returns_none(self):
        conn, _ = _conn(("", "Message Logged Successfully", ""))
        with mock.patch.object(wa, "connection", return_value=conn):
            self.assertIsNone(wa.log_outbound_message(ROW))

    def test_sp_error_returns_none(self):
        conn, _ = _conn(("", "boom", "1"))
        with mock.patch.object(wa, "connection", return_value=conn):
            self.assertIsNone(wa.log_outbound_message(ROW))

    def test_never_raises(self):
        conn, _ = _conn(exc=RuntimeError("db down"))
        with mock.patch.object(wa, "connection", return_value=conn):
            self.assertIsNone(wa.log_outbound_message(ROW))


class StatusLogMasksPhone(unittest.TestCase):
    def test_full_phone_not_logged(self):
        payload = {"entry": [{"changes": [{"field": "messages", "value": {"statuses": [
            {"id": "wamid.A", "status": "delivered", "recipient_id": "5216621380481"},
            {"id": "wamid.B", "status": "failed", "recipient_id": "5216621380481",
             "errors": [{"code": 131042, "title": "Business eligibility payment issue"}]}]}}]}]}
        with mock.patch.object(wc, "_update_dispatch"), self.assertLogs(wc.logger, "INFO") as logs:
            wc._log_statuses(payload)
        text = "\n".join(logs.output)
        self.assertNotIn("5216621380481", text)
        self.assertIn("to=…0481", text)


class DeliveryReceipts(unittest.TestCase):
    CHANNEL = {"channelId": 2, "companyId": 1, "phoneNumberId": "PNID"}

    def test_send_links_the_log_row_as_accepted(self):
        with mock.patch.object(wc, "log_outbound_message", return_value=77) as logged, \
             mock.patch.object(wc.whatsappMessageDeliveries, "upsert_delivery") as up:
            wc._record_outbound(channel=self.CHANNEL, phone_number="+526621380481", message_body="hola",
                                response_body="userId=9", status="staff_sent", wamid="wamid.X",
                                sender_kind="staff_pos")
        self.assertEqual(logged.call_args[0][0]["status"], "staff_sent")
        self.assertEqual(up.call_args[0][0], {"providerMessageId": "wamid.X", "whatsappMessageId": 77,
                                              "companyId": 1, "channelId": 2, "senderKind": "staff_pos",
                                              "status": "accepted"})

    def test_send_without_wamid_only_logs(self):
        with mock.patch.object(wc, "log_outbound_message", return_value=77), \
             mock.patch.object(wc.whatsappMessageDeliveries, "upsert_delivery") as up:
            wc._record_outbound(channel=self.CHANNEL, phone_number="+52", message_body="x", response_body="",
                                status="sent", wamid=None, sender_kind="agent")
        up.assert_not_called()

    def _payload(self, *statuses, pnid="PNID"):
        return {"entry": [{"changes": [{"field": "messages", "value": {
            "metadata": {"phone_number_id": pnid}, "statuses": list(statuses)}}]}]}

    def test_webhook_receipts_are_upserted_with_company_from_the_number(self):
        failed = {"id": "wamid.B", "status": "failed", "timestamp": "1762974000", "recipient_id": "5216621380481",
                  "errors": [{"code": 131042, "title": "Business eligibility payment issue"}]}
        read = {"id": "wamid.A", "status": "read", "timestamp": "1762973000", "recipient_id": "5216621380481"}
        with mock.patch.object(wc.whatsappChannels, "get_channel", return_value=self.CHANNEL) as gc, \
             mock.patch.object(wc.whatsappMessageDeliveries, "upsert_delivery") as up, \
             mock.patch.object(wc, "_update_dispatch"):
            wc._log_statuses(self._payload(read, failed))
        gc.assert_called_once_with("PNID")
        rows = [c[0][0] for c in up.call_args_list]
        self.assertEqual(rows[0], {"providerMessageId": "wamid.A", "companyId": 1, "channelId": 2, "status": "read",
                                   "statusTimestamp": "1762973000", "errorCode": None, "errorTitle": None})
        self.assertEqual((rows[1]["status"], rows[1]["errorCode"], rows[1]["errorTitle"]),
                         ("failed", "131042", "Business eligibility payment issue"))

    def test_unknown_number_is_skipped_and_never_breaks_the_webhook(self):
        st = {"id": "wamid.C", "status": "delivered", "recipient_id": "5216621380481"}
        with mock.patch.object(wc.whatsappChannels, "get_channel", side_effect=RuntimeError("db")), \
             mock.patch.object(wc.whatsappMessageDeliveries, "upsert_delivery") as up, \
             mock.patch.object(wc, "_update_dispatch") as disp:
            wc._log_statuses(self._payload(st))
        up.assert_not_called()
        disp.assert_called_once()  # notificationDispatch receipts keep working


class UpsertDelivery(unittest.TestCase):
    import modules.whatsappMessageDeliveries as md

    def test_bad_input_never_touches_the_db(self):
        with mock.patch.object(self.md, "connection") as c:
            self.assertIsNone(self.md.upsert_delivery({"providerMessageId": "w", "status": "deleted"}))
            self.assertIsNone(self.md.upsert_delivery({"status": "sent"}))
        c.assert_not_called()

    def test_upsert_sends_action_1_and_returns_id(self):
        conn, cur = _conn(("5", "Delivery status upserted", ""))
        with mock.patch.object(self.md, "connection", return_value=conn):
            out = self.md.upsert_delivery({"providerMessageId": "w", "status": "sent", "companyId": 1, "channelId": 2})
        self.assertEqual(out, 5)
        sent = cur.execute.call_args[0][1][0]
        self.assertIn('"whatsappMessageDeliveries"', sent)
        self.assertIn('"action": 1', sent)

    def test_db_error_returns_none(self):
        conn, _ = _conn(exc=RuntimeError("down"))
        with mock.patch.object(self.md, "connection", return_value=conn):
            self.assertIsNone(self.md.upsert_delivery({"providerMessageId": "w", "status": "read",
                                                       "companyId": 1, "channelId": 2}))


if __name__ == "__main__":
    unittest.main()
