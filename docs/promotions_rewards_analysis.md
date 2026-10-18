# Promotions vs. POS rewards — analysis (2026-10-16)

Scope: `dbo.promotions`, `dbo.promotion_targets`, `dbo.posRewardCatalogItems`, across
smartloans_backend, POSVendingV2/POSVending (POS front), menuLaundy (customer kiosk) and
LoanAgents_SmartLoans (WhatsApp agent). Data: live catalog rows pasted on 2026-10-16;
promotions from the 2026-08-15 snapshot.

## 1. The tables don't duplicate each other, they mix three mechanics

| Mechanic | What the customer experiences | Where it lives today | How it's paid |
|---|---|---|---|
| **Coupon** | "2x1 on your first purchase" | `promotions` (1 row: `2X1`, B2G1) + `promotion_targets` (1 row: ALL) | Discount on the sale, recomputed by `sp_income` |
| **Points reward** | "$10 off for 100 pts" | `posRewardCatalogItems` rows 2-4 (`discount_fixed`) | Points balance is debited (`REDEEM` in ledger) |
| **Stamp card** | "Buy 3 Lavado, the 4th is free" | `posRewardCatalogItems` rows 5-11 (`free_product`) | **No points.** Units bought of that product (`incomeDetails`) |

The confusion comes from two places:
- The stamp card is really a *promotion* (buy N, get 1), but it's stored in the *points* catalog.
  Its `requiredPoints = 3` doesn't mean points; it means units, via `pointsPerUnit`.
- The coupon is a full table (`promotions`) that holds a single row. The POS front hardcodes the
  code (`WELCOME_COUPON_CODE = '2X1'`, CartPage.tsx:110) and the first-purchase rule.

`promotion_targets` isn't a third concept: it's a child of `promotions` (FK) that says which
products a coupon covers.

There is also a **fourth, unrelated** system with similar names: loan rewards
(`rewardTransactions`, `rewardBenefits`, `finance/RewardsPage.tsx`, `modules/rewards.py`). It
isn't part of this merge.

## 2. Who uses what

| | Backend | POS front (POSVending) | menuLaundy | Agent |
|---|---|---|---|---|
| `promotions` | `sp_income` (B2G1 at checkout), `sp_income_apply_promo`, `sp_promotions` + `POST /promotions`; `income.promotionId/promotionCode/discountAmount`; `sp_tickets_one` | CartPage sends `promotionCode: '2X1'` and computes its own 2x1 preview | — | `get_promotions` → `/promotions` |
| `promotion_targets` | `sp_income_apply_promo` (`sp_income` ignores it) | — | — | — |
| `posRewardCatalogItems` | `sp_posRewardCatalogItems` (CRUD), `_redeem`, `_ProductCounts`, `_ProductRates`, `sp_whatsappCustomerRewards`, sale SMS (`modules/posRewards.py`); FK from `posRewardRedemptions` | Admin CRUD (`pos/PosRewards/*`), CartPage stamp-card apply, RewardsDashboard redeem | RewardsCheckPage (catalog + "3+1" free count) | `get_my_reward_points` → `customerRewards` |

## 3. Bugs found along the way

Ordered by impact. Items marked **(money)** change what is charged or recorded.

1. **Coupon + stamp card in the same sale loses the free unit server-side (money).** The front
   total subtracts both. Then `sp_income`, because a code is present, recomputes the total from
   the option prices with B2G1 only and overwrites it. The income row ends up higher than what
   the cashier charged.
2. **A reward is redeemed before the sale exists (money).** CartPage calls `redeem` with no
   `incomeId`. If the sale fails or the cart is cleared, the redemption stays `applied` and the
   stamp-card units (or points) are gone. The ticket also never records the reward discount:
   `discountAmount` covers only the coupon.
3. **Points rewards ($10/$25/$50) never reach a sale.** They can only be redeemed from
   RewardsDashboard, which debits points but applies no discount anywhere. CartPage only
   offers `free_product`.
4. **Customers are promised stamp cards based on points.** The sale SMS did this ("¡Ya puede
   canjear: Garrafon gratis!" at 5 pts); it's fixed in uncommitted work. **Still wrong:**
   `sp_whatsappCustomerRewards.canRedeemNow` (`requiredPoints <= balance`), so the WhatsApp
   agent repeats the same false promise.
5. **The first-purchase coupon is enforced only in the front.** The backend accepts `2X1` from
   anyone, any number of times.
6. **`requiredPoints` has two meanings.** It means points for discounts and units for stamp
   cards, and each app converts it differently:
   - backend redeem: `requiredPoints / pointsPerUnit`
   - CartPage: `unitsAvailable >= requiredPoints`
   - menuLaundy: `floor(units / requiredPoints)`

   These agree only while `pointsPerUnit = 1`.
7. **Naming.** "gratis (3x1)" is described as "compra 3, el 4to es gratis", which is a 4x3. "3x1"
   also reads like the `2X1` coupon.
8. **The B2G1 engine** pairs units only within a line, prices lines from option prices only, and
   in `sp_income` skips `promotion_targets` (see the earlier review).

## 4. Options for "one table"

### A. Keep `posRewardCatalogItems` as the single table (recommended)
- It's the table everything else already uses: the FK from `posRewardRedemptions`, the admin
  CRUD screen, menuLaundy, the agent and the SMS.
- Moving the coupon in is one row of data. Moving the catalog into `promotions` would mean
  repointing the FK and redemption history.
- Downside: the name says "rewards" while it would hold a coupon. A view `dbo.vw_promotions`
  (or simply the `/promotions` endpoint) can expose the coupon side under the old name.

### B. Keep `dbo.promotions` as the single table
- Better name, but the loyalty schema has to move into it: FK, three SPs, two admin screens,
  menuLaundy and the agent.
- The 10 catalog rows and the redemption history have to be re-keyed. Same end state, roughly
  3x the change surface.

## 5. Target model (option A)

`posRewardCatalogItems` gains an explicit type per mechanic, and units stop hiding in
`requiredPoints`:

| Column | coupon | points reward | stamp card |
|---|---|---|---|
| `rewardType` | `coupon_b2g1` | `discount_fixed` / `discount_pct` | `free_product` |
| `code` (new, unique per company) | `2X1` | NULL | NULL |
| `startAtUtc` / `endAtUtc` (new) | optional | optional | optional |
| `firstPurchaseOnly` (new BIT) | 1 | 0 | 0 |
| `requiredPoints` | 0 | 100 / 250 / 500 | 0 |
| `requiredUnits` (new) | NULL | NULL | 3 |
| `freeProductId` / target product | NULL = all products | NULL | product |
| `discountValue` | NULL | 10 / 25 / 50 | NULL |

Every use, coupon included, writes a `posRewardRedemptions` row linked to the `incomeId`. That
gives one history of "what discount was given on which ticket". `income.promotionId` then
stores the `catalogItemId`.

## 6. Change list per repo (option A)

**Backend (smartloans_backend)**
1. Migration:
   - add `code`, `startAtUtc`, `endAtUtc`, `firstPurchaseOnly`, `requiredUnits`;
   - extend the CHECK constraints;
   - copy `promotions` → catalog (`2X1` → `coupon_b2g1`);
   - backfill `requiredUnits = requiredPoints / pointsPerUnit` and `requiredPoints = 0` for `free_product`;
   - remap `income.promotionId`.
2. `sp_income` / `sp_income_apply_promo`: look up the coupon in the catalog. Enforce
   `firstPurchaseOnly` server-side. Subtract stamp-card free units passed with the sale instead
   of overwriting them (fixes bugs 1 and 5).
3. `sp_posRewardRedemptions_redeem`:
   - use `requiredUnits`;
   - accept `incomeId`;
   - add a "redeem with the sale" path inside `sp_income`, so a failed sale can't consume a reward (fixes bug 2).
4. `sp_promotions` / `POST /promotions`: read `coupon_*` rows from the catalog, keeping the same
   response shape. The agent doesn't change.
5. `sp_whatsappCustomerRewards`, `sp_posRewardFreeProductStatus`, `modules/posRewards.py`:
   decide by type (balance vs units) (fixes bug 4).
6. Drop `promotion_targets` and `promotions` after a soak period. Delete `sp_promotionTargets`,
   `/promotionTargets` and the `sp_income` targets patch from the 2026-10-16 uncommitted work.

**POS front (POSVending)**
1. CartPage:
   - load the active coupon from the catalog instead of `'2X1'`;
   - send redemptions with the sale (not before it);
   - allow points rewards in the cart (fixes bug 3).
2. PosRewards admin (`CatalogItemModal`, constants): add "Cupón" (code, dates, first purchase
   only) and a units field for "Tarjeta de sellos".
3. RewardsDashboard: hide coupons; for points rewards, decide what "canjear" outside a sale means.

**menuLaundy**
- RewardsCheckPage: use `requiredUnits`, and hide `coupon_*` rows (or show them as promos).

**Agent (LoanAgents_SmartLoans)**
- `get_promotions`: no change (same endpoint and shape).
- `get_my_reward_points` / prompt: present stamp cards by units ("te faltan 2 lavados") and
  points rewards by balance.

## 7. Open decisions

1. Option A (keep `posRewardCatalogItems`) or B (keep `promotions`)?
2. Should a points reward ($10 off) be applied inside a sale (recommended) or only redeemed from
   the dashboard?
3. Can a coupon and a stamp card stack in one sale (today the front allows it)?
4. Rename "gratis (3x1)" to "4x3" / "el 4to gratis"?
