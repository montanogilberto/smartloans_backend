# POS rewards — database deploy order

Run these scripts **directly in SQL Server** (SSMS / Azure Data Studio), in
this order. The backend never runs SQL files: `modules/posRewards.py` only
calls the stored procedures (`EXEC [dbo].[sp_*]`) once they exist.

Every script is safe to re-run. Scripts 1–3 create the tables and columns
that 4–9 use, so keep the order.

| # | Script | What it does |
|---|---|---|
| 1 | `sql/migrations/2026-10-16c_unify_promotions_into_reward_catalog.sql` | Catalog columns (code, dates, firstPurchaseOnly, requiredUnits); copies `dbo.promotions` into coupons |
| 2 | `sql/migrations/2026-10-18_pos_rewards_integrity.sql` | CHECK constraints + one applied reward per sale |
| 3 | `sql/migrations/2026-10-18b_pos_rewards_earn_pct.sql` | `posRewardSettings` (2.5% for the laundry), `incomeDetails.netAmount`, rewards at 1 pt = $1 |
| 4 | `sql/sp_posRewards.sql` | Stamp-card function, catalog CRUD, earn, redeem, give-back on delete |
| 5 | `sql/sp_posRewardFreeProductStatus.sql` | Stamp-card progress |
| 6 | `sql/sp_whatsappCustomerRewards.sql` | Rewards of a WhatsApp customer (agent) |
| 7 | `sql/sp_promotions.sql` | Coupons, read from the catalog |
| 8 | `sql/sp_income_applyDiscounts.sql` | Coupon + reward on a sale |
| 9 | `sql/sp_posRewardsDashboard.sql` | Puntos POS › Resumen dashboard |

Independent of the order above:

- `sql/migrations/2026-10-18c_income_client_request_id.sql` — `income.clientRequestId`
  and `sp_income_clientRequest` (a retried sale returns the first one). Until it
  runs, sales work as before without that protection.

Last, once sales with the catalog coupons look right:

- `sql/migrations/2026-10-16d_drop_promotions_tables.sql` — drops `dbo.promotions`
  and `dbo.promotionTargets`. It refuses if a coupon wasn't copied or anything
  else still uses them.

Deploy the backend code (`main` → Azure) after scripts 1–9: the new endpoints
call the stored procedures they create.
