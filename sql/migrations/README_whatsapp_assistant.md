# WhatsApp assistant — database deploy order

Run these scripts **directly in SQL Server** (SSMS / Azure Data Studio), in
this order. The backend never runs SQL files: `modules/whatsappAssistant.py`
only calls the stored procedures (`EXEC [dbo].[sp_*]`) once they exist.

Every script is safe to re-run.

| # | Script | What it does |
|---|---|---|
| 1 | `sql/migrations/2026-10-16_whatsapp_assistant_catalogs.sql` | `businessInfo` and `businessFaqs` tables; `promotions.description` |
| 2 | `sql/sp_businessInfo.sql` | `POST /businessInfo` |
| 3 | `sql/sp_businessFaqs.sql` | `POST /businessFaqs` |

The other two SPs the assistant uses read the POS rewards catalog, so they
are deployed with it (`sql/migrations/README_pos_rewards.md`, steps 6–7):

- `sql/sp_whatsappCustomerRewards.sql` — `POST /whatsapp/assistant/customerRewards`
- `sql/sp_promotions.sql` — `POST /promotions`

Deploy the backend code after these scripts: the endpoints call the stored
procedures they create.
