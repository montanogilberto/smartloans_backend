-- =============================================================================
-- Backfill dbo.clients.companyId from the store where the client buys
-- =============================================================================
-- Forward-only data migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB. Run step 1 alone first
-- and review it; step 2 changes data.
--
-- WHY: the POS "register client" form in the cart
-- (POSVending src/components/pos/ClientSelector.tsx) never sent companyId,
-- so every client registered at the counter was saved with companyId NULL.
-- Found 2026-10-06 with clientId 2260 (Carlos Corral): 2 sales in company 1
-- (gmoLavanderia) but no company, so he was missing from the store's client
-- list and every company-scoped rewards/report query. Frontend fixed the
-- same day (the form now sends companyId); this repairs existing rows.
--
-- RULE: a NULL-company client gets the company of their sales ONLY when all
-- of their sales are in exactly one company. Clients with no sales, or with
-- sales in more than one company, are listed in step 3 and left alone — that
-- needs a person to decide, not a guess.
-- Idempotent: only rows with companyId IS NULL are touched.
-- =============================================================================

-- ── 1. Preview: who would be fixed, and to which company ─────────────────────
SELECT c.clientId, c.first_name, c.last_name, c.cellphone, c.clientType, c.created_At,
       MIN(i.companyId) AS newCompanyId, COUNT(*) AS sales
FROM dbo.clients c
JOIN dbo.income i ON i.clientId = c.clientId
WHERE c.companyId IS NULL
  AND c.clientId <> 1                       -- walk-in "mostrador" placeholder
GROUP BY c.clientId, c.first_name, c.last_name, c.cellphone, c.clientType, c.created_At
HAVING COUNT(DISTINCT i.companyId) = 1
ORDER BY c.clientId;
GO

-- ── 2. Apply ─────────────────────────────────────────────────────────────────
;WITH single AS (
    SELECT i.clientId, MIN(i.companyId) AS companyId
    FROM dbo.income i
    GROUP BY i.clientId
    HAVING COUNT(DISTINCT i.companyId) = 1
)
UPDATE c
   SET c.companyId  = s.companyId,
       c.updated_at = GETDATE()
FROM dbo.clients c
JOIN single s ON s.clientId = c.clientId
WHERE c.companyId IS NULL
  AND c.clientId <> 1;

SELECT @@ROWCOUNT AS clientsFixed;
GO

-- ── 3. Left alone: still NULL — decide these by hand ─────────────────────────
SELECT c.clientId, c.first_name, c.last_name, c.cellphone, c.clientType, c.created_At,
       COUNT(i.incomeId)          AS sales,
       COUNT(DISTINCT i.companyId) AS companies
FROM dbo.clients c
LEFT JOIN dbo.income i ON i.clientId = c.clientId
WHERE c.companyId IS NULL
  AND c.clientId <> 1
GROUP BY c.clientId, c.first_name, c.last_name, c.cellphone, c.clientType, c.created_At
ORDER BY c.created_At DESC;
GO
