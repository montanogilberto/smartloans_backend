"""RFC-019 — interés posterior al plazo en préstamos 'interest_free'."""
import asyncio
import json
import unittest
from datetime import date
from decimal import Decimal
from unittest.mock import patch

from modules import automatedPayments as ap


def _cuotas(principal="1000.00", n=3, first_due="2026-01-15", paid=None):
    """n cuotas REGULAR iguales; paid = {installmentNumber: 'YYYY-MM-DD'}."""
    paid = paid or {}
    y, m, d = map(int, first_due.split("-"))
    rows = []
    for i in range(1, n + 1):
        mm = m + i - 1
        due = date(y + (mm - 1) // 12, (mm - 1) % 12 + 1, d)
        rows.append({
            "installmentId": i, "installmentNumber": i, "installmentType": "REGULAR",
            "clientId": 7, "lenderId": 9, "dueDate": due.isoformat(),
            "amount": principal, "principal": principal, "interest": "0.00",
            "status": "paid" if i in paid else "pending",
            "paidAt": f"{paid[i]}T18:00:00" if i in paid else None,
        })
    return rows


def _calc(rows, as_of, rate="36.00", term=3):
    return ap.compute_post_term_interest({
        "termMonths": term, "postTermRate": rate, "installments": rows, "asOfDate": as_of,
    })


class ComputePostTermInterestTests(unittest.TestCase):
    # Plazo: cuotas el 15-ene, 15-feb, 15-mar → M = 2026-03-15.

    def test_no_interest_until_term_end(self):
        r = _calc(_cuotas(), "2026-03-15")
        self.assertEqual(r["termEndDate"], date(2026, 3, 15))
        self.assertEqual(r["periodsDue"], [])
        self.assertEqual(r["accruedUnbilledInterest"], Decimal("0.00"))
        self.assertEqual(r["nextCutoffDate"], date(2026, 4, 15))

    def test_late_payment_inside_term_is_free(self):
        # Cuota 1 pagada el 10-mar (tarde, pero antes de M) y las demás en M.
        rows = _cuotas(paid={1: "2026-03-10", 2: "2026-03-15", 3: "2026-03-15"})
        r = _calc(rows, "2026-06-01")
        self.assertEqual(r["periodsDue"], [])
        self.assertEqual(r["unpaidPrincipal"], Decimal("0.00"))

    def test_open_period_accrues_daily_on_unpaid_principal(self):
        # 3000 sin pagar, 10 días después de M: 3000 × 10 × 0.36/365 = 29.589… → 29.59
        r = _calc(_cuotas(), "2026-03-25")
        self.assertEqual(r["periodsDue"], [])
        self.assertEqual(r["accruedUnbilledInterest"], Decimal("29.59"))
        self.assertEqual(r["nextCutoffDate"], date(2026, 4, 15))
        self.assertEqual(r["unpaidPrincipal"], Decimal("3000.00"))

    def test_full_period_billed_at_cutoff(self):
        # 15-mar → 15-abr = 31 días: 3000 × 31 × 0.36/365 = 91.726… → 91.73
        r = _calc(_cuotas(), "2026-04-15")
        self.assertEqual(len(r["periodsDue"]), 1)
        p = r["periodsDue"][0]
        self.assertEqual(p["installmentNumber"], 4)
        self.assertEqual(p["interest"], Decimal("91.73"))
        self.assertEqual(p["interestPeriodStart"], date(2026, 3, 15))
        self.assertEqual(p["interestPeriodEnd"], date(2026, 4, 15))
        self.assertEqual(p["remainingBalance"], Decimal("3000.00"))
        self.assertEqual(p["dueDate"], date(2026, 4, 25))  # corte + 10 días

    def test_partial_payment_mid_period_uses_daily_balance(self):
        # Cuotas 1-2 pagadas en M; cuota 3 (1000) pagada el 25-mar → 10 días.
        rows = _cuotas(paid={1: "2026-03-15", 2: "2026-03-15", 3: "2026-03-25"})
        r = _calc(rows, "2026-03-25")
        # Todo el capital pagado el 25-mar → corte anticipado ese día.
        self.assertEqual(len(r["periodsDue"]), 1)
        p = r["periodsDue"][0]
        self.assertEqual(p["interestPeriodEnd"], date(2026, 3, 25))
        self.assertEqual(p["interest"], Decimal("9.86"))  # 1000 × 10 × 0.36/365
        self.assertEqual(p["remainingBalance"], Decimal("0.00"))
        self.assertIsNone(r["nextCutoffDate"])

    def test_no_more_periods_after_full_payoff(self):
        rows = _cuotas(paid={1: "2026-03-15", 2: "2026-03-15", 3: "2026-03-25"})
        r = _calc(rows, "2026-09-01")
        self.assertEqual([p["installmentNumber"] for p in r["periodsDue"]], [4])

    def test_already_billed_period_not_repeated_and_counted(self):
        rows = _cuotas() + [{
            "installmentNumber": 4, "installmentType": "POST_TERM_INTEREST",
            "dueDate": "2026-04-25", "principal": "0", "interest": "91.73",
            "amount": "91.73", "status": "pending", "paidAt": None,
        }]
        # Periodo 2 (15-abr → 15-may) aún abierto: nada que cobrar, el 1 ya está cobrado.
        r = _calc(rows, "2026-05-10")
        self.assertEqual(r["periodsDue"], [])
        self.assertEqual(r["billedInterest"], Decimal("91.73"))
        self.assertEqual(r["billedUnpaidInterest"], Decimal("91.73"))
        self.assertEqual(r["nextCutoffDate"], date(2026, 5, 15))
        # Al corte del periodo 2 sólo aparece el 5, nunca otra vez el 4.
        r2 = _calc(rows, "2026-05-15")
        self.assertEqual([p["installmentNumber"] for p in r2["periodsDue"]], [5])

    def test_missed_job_days_bill_every_closed_period(self):
        r = _calc(_cuotas(), "2026-06-20")
        self.assertEqual([p["installmentNumber"] for p in r["periodsDue"]], [4, 5, 6])
        # El vencimiento nunca queda en el pasado: hoy + 10 días.
        self.assertEqual(r["periodsDue"][0]["dueDate"], date(2026, 6, 30))
        self.assertEqual(r["nextCutoffDate"], date(2026, 7, 15))

    def test_interest_not_capitalized(self):
        billed_unpaid = {
            "installmentNumber": 4, "installmentType": "POST_TERM_INTEREST",
            "dueDate": "2026-04-25", "principal": "0", "interest": "91.73",
            "amount": "91.73", "status": "pending", "paidAt": None,
        }
        # Periodo 2 (15-abr → 15-may, 30 días) sólo sobre el capital: 3000 × 30 × 0.36/365
        r = _calc(_cuotas() + [billed_unpaid], "2026-05-15")
        self.assertEqual(r["periodsDue"][0]["interest"], Decimal("88.77"))

    def test_zero_rate_never_bills(self):
        r = _calc(_cuotas(), "2026-09-01", rate="0")
        self.assertEqual(r["periodsDue"], [])

    def test_paid_without_date_does_not_accrue(self):
        rows = _cuotas(paid={1: "2026-03-01", 2: "2026-03-01", 3: "2026-03-01"})
        rows[2]["paidAt"] = None
        r = _calc(rows, "2026-06-01")
        self.assertEqual(r["periodsDue"], [])


class AccrueJobTests(unittest.TestCase):
    def _run(self, candidates, insert_result=None, **body):
        calls = []

        def fake_insert(payload):
            calls.append(payload)
            return insert_result if insert_result is not None else {"installmentId": 99, "created": True}

        with patch.object(ap, "_sp_installments_all", return_value={"loans": candidates}) as q, \
             patch.object(ap, "_sp_installments", side_effect=fake_insert), \
             patch.object(ap, "log_workflow_step"):
            resp = asyncio.run(ap.accrue_post_term_interest(body))
        return json.loads(resp.body), calls, q

    def _loan(self, rows):
        return {"loanId": 5, "companyId": 1008, "termMonths": 3, "postTermRate": 36.0,
                "loanStatus": "active", "installments": rows}

    def test_inserts_one_immutable_row_per_closed_period(self):
        body, calls, q = self._run([self._loan(_cuotas())], asOfDate="2026-04-15")
        self.assertEqual(body["created"], 1)
        self.assertEqual(len(calls), 1)
        c = calls[0]
        self.assertEqual(c["action"], "insert_post_term_interest")
        self.assertEqual((c["loanId"], c["companyId"], c["clientId"], c["lenderId"]), (5, 1008, 7, 9))
        self.assertEqual(c["installmentNumber"], 4)
        self.assertEqual(c["interest"], "91.73")
        self.assertEqual(c["dueDate"], "2026-04-25")
        self.assertEqual((c["interestPeriodStart"], c["interestPeriodEnd"]), ("2026-03-15", "2026-04-15"))
        self.assertEqual(q.call_args[0][0], {"action": "post_term_candidates", "asOfDate": "2026-04-15"})

    def test_dry_run_writes_nothing(self):
        body, calls, _ = self._run([self._loan(_cuotas())], asOfDate="2026-04-15", dryRun=True)
        self.assertEqual(calls, [])
        self.assertEqual(body["details"][0]["result"], "dry_run")

    def test_already_billed_counts_as_skipped(self):
        body, _, _ = self._run([self._loan(_cuotas())], insert_result={"installmentId": None, "created": False},
                               asOfDate="2026-04-15")
        self.assertEqual((body["created"], body["skipped"]), (0, 1))

    def test_company_filter_passed_to_sp(self):
        _, _, q = self._run([], companyId=1008, asOfDate="2026-04-15")
        self.assertEqual(q.call_args[0][0]["companyId"], 1008)

    def test_job_never_touches_money(self):
        # Sólo sp_loanInstallments: ni ledger, ni Stripe, ni confirmaciones.
        with patch.object(ap, "credit_wallet") as wallet, patch.object(ap.stripe, "PaymentIntent") as pi:
            self._run([self._loan(_cuotas())], asOfDate="2026-06-20")
        wallet.assert_not_called()
        pi.create.assert_not_called()


class StatusEndpointTests(unittest.TestCase):
    def test_standard_loan_returns_plan_only(self):
        with patch.object(ap, "_sp_loan_one", return_value={"loanId": 1, "paymentPlan": "standard"}):
            resp = asyncio.run(ap.post_term_interest_status({"loanId": 1, "companyId": 1008}))
        self.assertEqual(json.loads(resp.body), {"loanId": 1, "paymentPlan": "standard"})

    def test_interest_free_summary(self):
        loan = {"loanId": 5, "paymentPlan": "interest_free", "postTermRate": 36.0, "termMonths": 3}
        with patch.object(ap, "_sp_loan_one", return_value=loan), \
             patch.object(ap, "_sp_installments_all", return_value={"installments": _cuotas()}):
            resp = asyncio.run(ap.post_term_interest_status(
                {"loanId": 5, "companyId": 1008, "asOfDate": "2026-03-25"}))
        body = json.loads(resp.body)
        self.assertEqual(body["termEndDate"], "2026-03-15")
        self.assertEqual(body["accruedUnbilledInterest"], 29.59)
        self.assertEqual(body["unpaidPrincipal"], 3000.0)
        self.assertEqual(body["nextCutoffDate"], "2026-04-15")
        self.assertEqual(body["postTermRate"], 36.0)

    def test_missing_ids_400(self):
        resp = asyncio.run(ap.post_term_interest_status({"loanId": 5}))
        self.assertEqual(resp.status_code, 400)


if __name__ == "__main__":
    unittest.main()
