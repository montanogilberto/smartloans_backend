"""
WhatsApp bot: the campaign agent records a demand signal (RECORD_DEMAND_SIGNAL).

The agent proposes {concept, preferredZoneText, ...} with no confirmation step;
this module upserts it through modules.demandSignals with the channel's
companyId/channelId and the sender's phone — never values from the agent —
and the customer gets the agent's reply whatever happens to the write.
No database / no Meta / no agent: everything external is stubbed.

Run:  venv/bin/python -m unittest tests/test_whatsapp_demand_signal.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.demandSignals as ds  # noqa: E402
import modules.whatsappReservations as wr  # noqa: E402

CHANNEL = {"channelId": 3, "companyId": 1, "branchId": None, "phoneNumberId": "1330937783442101"}
PHONE = "+5216621234567"
REPLY = "¡Gracias! ¿Cada cuánto lo usarías y a qué hora te acomoda?"


class RecordDemandSignalTest(unittest.TestCase):
    def setUp(self):
        self.fields = {"concept": "lockers", "preferredZoneText": "por la Pitic", "wouldUse": "si"}
        self.lookup = {"result": [{"status": "found", "clientId": 5417, "firstName": "Ana"}]}
        self.recorded = []
        self.record_error = None
        self.set_pending = mock.MagicMock()
        patches = [
            mock.patch.object(wr, "AGENT_URL", "https://agent.test"),
            mock.patch.object(wr.whatsappChannels, "get_state", side_effect=lambda *a: {
                "staffPaused": False, "pending": None, "lastBooked": None}),
            mock.patch.object(wr.whatsappChannels, "set_pending", self.set_pending),
            mock.patch.object(wr.whatsappChannels, "clear_pending"),
            mock.patch.object(wr, "_ask_agent", side_effect=lambda *a: (
                REPLY, {"capability": "RECORD_DEMAND_SIGNAL", "fields": self.fields})),
            mock.patch.object(wr, "assistant_sp", side_effect=lambda proc, payload: self.lookup),
            mock.patch.object(ds, "record_demand_signal", side_effect=self._record),
            mock.patch.object(wr, "_book", side_effect=AssertionError("must not book")),
            mock.patch.object(wr, "_hand_off_to_staff", side_effect=AssertionError("must not hand off")),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _record(self, payload):
        if self.record_error:
            raise self.record_error
        self.recorded.append(payload)
        return {"demandSignalId": 7, "intentLevel": "media"}

    def _reply(self):
        return wr.reply_to(CHANNEL, PHONE, "Ana", "por la Pitic, cerca de mi trabajo")

    def test_records_with_channel_company_and_sender_phone(self):
        self.assertEqual(self._reply(), REPLY)
        row = self.recorded[0]["demandSignals"][0]
        self.assertEqual((row["companyId"], row["channelId"], row["customerPhone"]), (1, 3, PHONE))
        self.assertEqual(row["concept"], "lockers")
        self.assertEqual(row["preferredZoneText"], "por la Pitic")
        self.assertEqual(row["clientId"], 5417)
        self.set_pending.assert_not_called()  # no confirmation step

    def test_agent_cannot_set_tenant_phone_client_or_attribution(self):
        self.fields = {**self.fields, "companyId": 1008, "channelId": 99, "customerPhone": "+520000000000",
                       "clientId": 1, "marketingLeadAttributionId": 5, "intentLevel": "alta"}
        self._reply()
        row = self.recorded[0]["demandSignals"][0]
        self.assertEqual((row["companyId"], row["channelId"], row["customerPhone"], row["clientId"]),
                         (1, 3, PHONE, 5417))
        self.assertNotIn("marketingLeadAttributionId", row)
        self.assertNotIn("intentLevel", row)

    def test_unknown_customer_has_no_client_id(self):
        self.lookup = {"result": [{"status": "not_found"}]}
        self._reply()
        self.assertNotIn("clientId", self.recorded[0]["demandSignals"][0])

    def test_empty_fields_are_left_out(self):
        self.fields = {**self.fields, "frequency": None}
        self._reply()
        self.assertNotIn("frequency", self.recorded[0]["demandSignals"][0])

    def test_write_failure_still_replies(self):
        self.record_error = RuntimeError("sp_demandSignals: channel does not belong to company")
        self.assertEqual(self._reply(), REPLY)

    def test_lookup_failure_still_records(self):
        with mock.patch.object(wr, "assistant_sp", side_effect=RuntimeError("db down")):
            self.assertEqual(self._reply(), REPLY)
        self.assertNotIn("clientId", self.recorded[0]["demandSignals"][0])


if __name__ == "__main__":
    unittest.main()
