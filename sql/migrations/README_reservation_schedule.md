# Reservation schedule + holidays — database deploy order

Run these scripts **directly in SQL Server** (SSMS / Azure Data Studio), in
this order, on each database (DEV, QA, PROD). The backend never runs SQL files.
Every script is safe to re-run.

| # | Script | What it does |
|---|---|---|
| 1 | `sql/migrations/2026-11-09_reservation_holidays.sql` | `reservationHolidays` table (per companyId + date) |
| 2 | `sql/sp_reservationHolidays.sql` | `POST /reservationHolidays` — list / set / remove a date |
| 3 | `sql/sp_reservationSchedule.sql` | `POST /reservationSchedule` — schedule day by day, holidays applied |
| 4 | `sql/sp_reservations.sql` | slots (action 6) and booking (action 1) respect holidays |

Step 1 must run before step 4: `sp_reservations` compiles without the table
(deferred name resolution) but would fail at runtime on actions 1 and 6.

Rollback: re-run the previous `sql/sp_reservations.sql` from git history, then
`sql/migrations/2026-11-09_reservation_holidays_ROLLBACK.sql`.

Check after deploying:

```sql
EXEC dbo.sp_reservationSchedule @pjsonfile = N'{"reservationSchedule":[{"companyId":1,"days":7}]}';
```
