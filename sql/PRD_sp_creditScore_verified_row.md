# PRD — Redeploy `sp_creditScore_data` (KYC flags return 0 for a verified client)

**Target object:** `[dbo].[sp_creditScore_data]` (in `sql/sp_creditScore.sql`)
**Pipeline:** posgmo-factory (SP is factory-owned — do **not** hand-edit prod; this PRD drives the deploy)
**Type:** Deploy / drift fix (primary) + defensive hardening (secondary)
**Priority:** High (blocks all credit-limit issuance)

---

## Root cause (verified against prod)

`POST /credit-score/available-credit` for client `2116` / company `1008` returns
`kycEligible: false`, `"KYC incompleto…"`, `availableCredit: 0`, and
`internalScore: 712` **with zero KYC bonuses** (a verified client would be 762).

Ground truth from prod:

- `POST /all_clientFaceRecognitions {clientId:2116, companyId:1008}` returns
  **exactly one** row — `clientFaceRecognitionId: 38`,
  `isVerified: true, contractAccepted: true, pagareAccepted: true`,
  `createdAt: 2026-07-18`. **No newer/unverified row exists.**
- The **on-disk** `sp_creditScore_data` (`sql/sp_creditScore.sql`, lines 123–126)
  reads those flags with `TOP 1 … ORDER BY createdAt DESC` — for a single
  verified row it returns `1`.

So the **stored procedure running in Azure SQL is older than the file** — it
predates (or differs from) the `clientFaceRecognitions` flag reads and returns
`isVerified / pagareAccepted / contractAccepted = 0`. The aggregate fields are
correct (base 412 is a genuine new-borrower profile), only the three KYC flags
are wrong. **This is deployment drift, not a code or data bug.**

## Primary fix — deploy the current SP

Re-apply `sql/sp_creditScore.sql` (the `ALTER/CREATE PROCEDURE
[dbo].[sp_creditScore_data]` definition) to the production Azure SQL database
through the factory pipeline. No source change needed — the file is already
correct.

**Verify after deploy:**

```bash
curl -X POST https://smartloansbackend.azurewebsites.net/credit-score/available-credit \
  -H 'Content-Type: application/json' \
  -d '{ "clientId": 2116, "companyId": 1008 }'
# expect: kycEligible:true, tier:"PROMO_FIRST_TIME", availableCredit:3000,
#         internalScore:762 (712 base + 50 KYC bonuses)
```

## Secondary — harden row selection while redeploying (optional but recommended)

Today's selection takes the **newest** row. If a client re-enters the wizard and
creates a newer *unfinished* row (`isVerified = 0`), it would then shadow the
completed expediente. Not the cause here (single row), but cheap to prevent.
Change lines 123–126 to read all three flags from the newest **verified** row:

```sql
        -- Biometric & legal flags — from the newest COMPLETED (verified)
        -- expediente, so a newer unfinished re-KYC attempt can't lower an
        -- already-earned verified status.
        DECLARE @faceId INT = (
            SELECT TOP 1 clientFaceRecognitionId
            FROM   [dbo].[clientFaceRecognitions]
            WHERE  clientId = @clientId AND companyId = @companyId
              AND  isVerified = 1
            ORDER BY createdAt DESC
        );
        DECLARE @isVerified       BIT = CASE WHEN @faceId IS NULL THEN 0 ELSE 1 END;
        DECLARE @pagareAccepted   BIT = ISNULL((
            SELECT pagareAccepted   FROM [dbo].[clientFaceRecognitions]
            WHERE clientFaceRecognitionId = @faceId), 0);
        DECLARE @contractAccepted BIT = ISNULL((
            SELECT contractAccepted FROM [dbo].[clientFaceRecognitions]
            WHERE clientFaceRecognitionId = @faceId), 0);
```

The `FOR JSON` projection (unchanged) already emits `ISNULL(@isVerified,0)` etc.

## Out of scope (separate work)

- **companyId split** — wizard writes `clientFaceRecognitions` under the session
  company (1008); if the dashboard ever calls the engine with the client's own
  companyId (1), the join misses. Track separately.
- Persisting `availableCredit` onto `clientDashboards` (own PRD).

## Acceptance criteria

1. After deploy, client `2116`/`1008` → `kycEligible:true`,
   `availableCredit:3000`, `tier:PROMO_FIRST_TIME`, `internalScore:762`.
2. A client with no verified row still returns all flags `0` / `availableCredit:0`.
3. Output JSON shape of `sp_creditScore_data` is unchanged for existing consumers.
