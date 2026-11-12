"""
WhatsApp bot, Red GMO: a business offers space for a locker (RECORD_LOCATION_HOST).

The agent proposes {businessName, zoneText, ...} with no confirmation step;
this module upserts it through modules.locationHosts with the channel's
companyId/channelId and the sender's phone. Staff-only fields (status,
staffNotes) and tenant fields from the agent are dropped, and the customer
gets the agent's reply whatever happens to the write.

Run:  venv/bin/python -m unittest tests/test_whatsapp_location_host.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.locationHosts as lh  # noqa: E402
import modules.whatsappReservations as wr  # noqa: E402

CHANNEL = {"channelId": 3, "companyId": 1, "branchId": None, "phoneNumberId": "1330937783442101"}
PHONE = "+5216621234567"
REPLY = "¡Gracias! ¿Qué tipo de negocio es?"


class RecordLocationHostTest(unittest.TestCase):
    def setUp(self):
        self.fields = {"businessName": "Abarrotes Lupita", "zoneText": "Pitic", "opensWeekends": True}
        self.recorded = []
        self.error = None
        patches = [
            mock.patch.object(wr, "AGENT_URL", "https://agent.test"),
            mock.patch.object(wr.whatsappChannels, "get_state", side_effect=lambda *a: {
                "staffPaused": False, "pending": None, "lastBooked": None}),
            mock.patch.object(wr.whatsappChannels, "set_pending", side_effect=AssertionError("no pending")),
            mock.patch.object(wr.whatsappChannels, "clear_pending"),
            mock.patch.object(wr, "_ask_agent", side_effect=lambda *a: (
                REPLY, {"capability": "RECORD_LOCATION_HOST", "fields": self.fields})),
            mock.patch.object(lh, "record_location_host", side_effect=self._record),
            mock.patch.object(wr, "_book", side_effect=AssertionError("must not book")),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _record(self, payload):
        if self.error:
            raise self.error
        self.recorded.append(payload)
        return {"locationHostId": 4, "newOptIn": getattr(self, "new_opt_in", False)}

    def test_new_contact_opt_in_alerts_the_team_once(self):
        self.fields = {**self.fields, "contactOptIn": True, "contactName": "Lupita"}
        self.new_opt_in = True
        with mock.patch.object(wr, "pushNotifications_sp") as push, \
                mock.patch.object(wr.asyncio, "run") as run:
            self.assertEqual(self._reply(), REPLY)
        push_payload = push.call_args.args[0]["pushNotifications"][0]
        self.assertEqual((push_payload["companyId"], push_payload["targetCompanyId"]), (1, 1))
        self.assertIn("Abarrotes Lupita (Pitic)", push_payload["message"])
        self.assertNotIn(PHONE, push_payload["navigationRoute"])
        run.assert_called_once()

    def test_no_alert_when_opt_in_was_already_on_or_absent(self):
        for fields in ({**self.fields, "contactOptIn": True}, self.fields):
            self.fields, self.new_opt_in = fields, False
            with mock.patch.object(wr, "pushNotifications_sp") as push, mock.patch.object(wr.asyncio, "run"):
                self._reply()
            push.assert_not_called()

    def test_no_alert_when_the_write_failed(self):
        self.fields = {**self.fields, "contactOptIn": True}
        self.error = RuntimeError("db down")
        with mock.patch.object(wr, "pushNotifications_sp") as push, mock.patch.object(wr.asyncio, "run"):
            self.assertEqual(self._reply(), REPLY)
        push.assert_not_called()

    def _reply(self):
        return wr.reply_to(CHANNEL, PHONE, "Lupita", "Abarrotes Lupita en la Pitic")

    def test_records_with_channel_company_and_sender_phone(self):
        self.assertEqual(self._reply(), REPLY)
        row = self.recorded[0]["locationHosts"][0]
        self.assertEqual((row["companyId"], row["channelId"], row["contactPhone"]), (1, 3, PHONE))
        self.assertEqual((row["businessName"], row["zoneText"], row["opensWeekends"]),
                         ("Abarrotes Lupita", "Pitic", True))

    def test_agent_cannot_set_tenant_status_or_notes(self):
        self.fields = {**self.fields, "companyId": 1008, "channelId": 9, "contactPhone": "+520000000000",
                       "status": "aprobado", "staffNotes": "ok", "marketingLeadAttributionId": 2}
        self._reply()
        row = self.recorded[0]["locationHosts"][0]
        self.assertEqual((row["companyId"], row["channelId"], row["contactPhone"]), (1, 3, PHONE))
        for key in ("status", "staffNotes", "marketingLeadAttributionId"):
            self.assertNotIn(key, row)

    def test_write_failure_still_replies(self):
        self.error = RuntimeError("sp_locationHosts: channel does not belong to company")
        self.assertEqual(self._reply(), REPLY)


if __name__ == "__main__":
    unittest.main()
