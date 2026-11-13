"""
WhatsApp bot: the team's recent messages to a customer reach the agent, so a
reply to the team ("Enrique Vizcaino / 6621140790" after staff asked for name
and phone, 2026-11-12) is understood. Only what came after the agent's last
reply, last 24 h, newest 3. Read through sp_whatsappAgentConversations "thread".

Run:  venv/bin/python -m unittest tests/test_whatsapp_staff_context.py -v
"""
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.whatsappReservations as wr  # noqa: E402

PHONE = "+5216621140790"


def _at(hours_ago):
    return (datetime.now(timezone.utc) - timedelta(hours=hours_ago)).strftime("%Y-%m-%dT%H:%M:%S")


class StaffContextTest(unittest.TestCase):
    def _run(self, items):
        with mock.patch.object(wr, "assistant_sp", return_value={"result": [{"items": items}]}) as sp:
            return wr._recent_staff_messages(1, PHONE), sp

    def test_only_team_messages_after_the_agents_last_reply(self):
        out, sp = self._run([
            {"kind": "staff", "text": "mensaje viejo", "atUtc": _at(8)},
            {"kind": "bot", "text": "No puedo escuchar audios", "atUtc": _at(6)},
            {"kind": "client", "text": "[audio]", "atUtc": _at(6)},
            {"kind": "staff", "text": "Hola. ¿Nos podría proporcionar su nombre?", "atUtc": _at(5)},
        ])
        self.assertEqual([m["text"] for m in out], ["Hola. ¿Nos podría proporcionar su nombre?"])
        req = sp.call_args.args[1]["whatsappAgentConversations"][0]
        self.assertEqual((req["action"], req["companyId"], req["phone10"]), ("thread", 1, "6621140790"))

    def test_app_messages_count_older_than_24h_do_not_and_max_three(self):
        out, _ = self._run([{"kind": "staff_app", "text": "viejo", "atUtc": _at(30)}]
                           + [{"kind": "staff_app", "text": f"m{i}", "atUtc": _at(4 - i)} for i in range(4)])
        self.assertEqual([m["text"] for m in out], ["m1", "m2", "m3"])

    def test_no_staff_or_failure_is_empty(self):
        self.assertEqual(self._run([{"kind": "bot", "text": "hola", "atUtc": _at(1)}])[0], [])
        with mock.patch.object(wr, "assistant_sp", side_effect=RuntimeError("db down")):
            self.assertEqual(wr._recent_staff_messages(1, PHONE), [])

    def test_agent_request_carries_them(self):
        resp = mock.MagicMock()
        resp.json.return_value = {"reply": "ok", "pendingAction": None}
        with mock.patch.object(wr, "AGENT_URL", "https://agent.test"), \
                mock.patch.object(wr.httpx, "post", return_value=resp) as post:
            wr._ask_agent({"channelId": 3, "companyId": 1}, PHONE, "Enrique", "Enrique Vizcaino", None,
                          staff_messages=[{"text": "¿Su nombre?", "atUtc": _at(1)}])
        self.assertEqual(post.call_args.kwargs["json"]["staffMessages"][0]["text"], "¿Su nombre?")


if __name__ == "__main__":
    unittest.main()
