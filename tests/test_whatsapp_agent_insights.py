"""
POST /whatsapp/agentInsights — "¿Qué quieren mis clientes?".

The SP and the LoanAgents call are mocked: checks that phones/emails never
leave the backend, that topic counts are computed here, and that the
integration log carries no customer text.

Run:  venv/bin/python -m unittest tests/test_whatsapp_agent_insights.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.whatsappAssistant as wa  # noqa: E402

ROWS = [
    {"message": "¿Cuánto cuesta lavar 5 kilos? mi cel 662 196 3584", "topic": "precios"},
    {"message": "¿abren el domingo? escribe a ana@gmail.com", "topic": "horarios"},
    {"message": "precio del edredón", "topic": "precios"},
]


class InsightsTest(unittest.TestCase):
    def setUp(self):
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(wa, "_AGENT_URL", "http://agents").start()
        mock.patch.object(wa, "_sp", return_value={"result": [{"messages": ROWS}]}).start()
        resp = mock.Mock(status_code=200)
        resp.json.return_value = {"summary": "Preguntan precios", "commonDoubts": [], "unmetNeeds": [],
                                  "messagesAnalyzed": 3}
        self.post = mock.patch.object(wa.httpx, "post", return_value=resp).start()
        self.timed = mock.patch.object(wa, "timed_integration").start()

    def _call(self):
        return wa.whatsapp_agent_insights({"whatsappAgentInsights": [
            {"companyId": 1, "startDate": "2026-10-01", "endDate": "2026-10-31"}]})

    def test_strips_contact_data_and_counts_topics(self):
        res = self._call()
        self.assertEqual(res.status_code, 200)
        sent = self.post.call_args.kwargs["json"]
        joined = " ".join(sent["messages"])
        self.assertNotIn("196 3584", joined)
        self.assertNotIn("ana@gmail.com", joined)
        self.assertIn("[teléfono]", joined)
        self.assertEqual(sent["topicCounts"], [{"topic": "precios", "count": 2}, {"topic": "horarios", "count": 1}])

    def test_integration_log_has_no_customer_text(self):
        self._call()
        logged = str(self.timed.call_args)
        self.assertNotIn("kilos", logged)
        self.assertIn("'messages': 3", logged)

    def test_requires_period(self):
        res = wa.whatsapp_agent_insights({"whatsappAgentInsights": [{"companyId": 1}]})
        self.assertEqual(res.status_code, 400)
        self.post.assert_not_called()


if __name__ == "__main__":
    unittest.main()
