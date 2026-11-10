"""
POST /reservationSchedule (schedule day by day) and POST /reservationHolidays.

The DB is mocked: these tests check each route calls its SP with the body as
sent, that the schedule is open to read (agents, kiosk), and that a holiday
write needs the worker key or a company admin's session, like /reservationHours.

Run:  venv/bin/python -m unittest tests/test_reservation_schedule.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.reservations as reservations  # noqa: E402
import routes_.reservations as routes  # noqa: E402

app = FastAPI()
app.include_router(routes.router)
client = TestClient(app)

SCHEDULE = {"result": [{"reservationSchedule": [
    {"date": "2026-12-25", "dayOfWeek": 4, "weekday": "viernes", "isOpen": False,
     "openTime": None, "closeTime": None, "isHoliday": True, "holidayName": "Navidad"}]}]}


class ReservationScheduleTest(unittest.TestCase):
    def test_schedule_reads_by_company(self):
        body = {"reservationSchedule": [{"companyId": 1, "fromDate": "2026-12-25", "days": 1}]}
        with mock.patch.object(reservations, "_sp", return_value=SCHEDULE) as sp:
            r = client.post("/reservationSchedule", json=body)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), SCHEDULE)
        sp.assert_called_once_with(body, "sp_reservationSchedule")

    def test_holidays_list_is_open(self):
        body = {"reservationHolidays": [{"companyId": 1}]}
        with mock.patch.object(reservations, "_sp", return_value={"result": [{"reservationHolidays": []}]}) as sp:
            r = client.post("/reservationHolidays", json=body)
        self.assertEqual(r.status_code, 200)
        sp.assert_called_once_with(body, "sp_reservationHolidays")

    def test_holiday_write_needs_admin_or_worker_key(self):
        body = {"reservationHolidays": [{"action": 1, "companyId": 1, "holidayDate": "2026-12-25"}]}
        with mock.patch.object(reservations, "_sp") as sp:
            r = client.post("/reservationHolidays", json=body)
        self.assertEqual(r.status_code, 403)
        sp.assert_not_called()

    def test_db_error_is_500(self):
        with mock.patch.object(reservations, "_sp", side_effect=RuntimeError("boom")):
            r = client.post("/reservationSchedule", json={"reservationSchedule": [{"companyId": 1}]})
        self.assertEqual(r.status_code, 500)


if __name__ == "__main__":
    unittest.main()
