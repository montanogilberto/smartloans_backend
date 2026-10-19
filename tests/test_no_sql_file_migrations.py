"""
The backend never runs SQL files: database objects are deployed directly in
SQL Server (sql/migrations/README_pos_rewards.md, README_whatsapp_assistant.md).
Neither module keeps a migrate endpoint.

Run:  venv/bin/python -m unittest tests/test_migrate_auth.py -v
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.posRewards as pos_rewards  # noqa: E402
import modules.whatsappAssistant as assistant  # noqa: E402
import routes_.posRewards as pos_rewards_routes  # noqa: E402
import routes_.whatsappAssistant as assistant_routes  # noqa: E402

app = FastAPI()
app.include_router(pos_rewards_routes.router)
app.include_router(assistant_routes.router)
client = TestClient(app)


class NoSqlFileMigrationsTest(unittest.TestCase):
    def test_no_migrate_endpoints(self):
        for path in ("/posRewards/migrate", "/whatsapp/assistant/migrate"):
            with self.subTest(path=path):
                self.assertEqual(client.post(path, headers={"X-Worker-Key": "x"}).status_code, 404)

    def test_modules_do_not_run_sql_files(self):
        for module in (pos_rewards, assistant):
            with self.subTest(module=module.__name__):
                for name in ("run_sql_files", "run_migration", "_MIGRATION_FILES", "POS_REWARDS_MIGRATION_FILES"):
                    self.assertFalse(hasattr(module, name), f"{module.__name__}.{name}")


if __name__ == "__main__":
    unittest.main()
