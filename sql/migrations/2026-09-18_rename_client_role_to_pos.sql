-- =============================================================================
-- Renames the 'client' role code to 'pos' — the roleCode a client_login.py
-- self-service session (see modules/client_login.py) gets. 'client' was
-- ambiguous: every participant in this system (borrower, lender, staff) is
-- also a "client" of some kind; this role specifically means a plain POS
-- customer, which is what dbo.clients.clientType='pos' already calls it.
-- Matches that naming instead of colliding with it.
--
-- NOT YET EXECUTED against any database — run manually, same convention as
-- every other file in this migrations/ folder. Run this BEFORE re-running
-- sql/sp_roles.sql (which has already been updated to say 'pos' instead of
-- 'client') -- sp_roles.sql's seeding joins on dbo.roles.code, so until this
-- rename runs, re-running sp_roles.sql would silently match nothing for
-- this role (in particular the 'myRewards' uiFeature grant, which is
-- correctly written in sp_roles.sql but was never live-seeded because the
-- role catalog still said 'client' when it last ran).
--
-- dbo.userCompanies.roleName is a DENORMALIZED COPY of the roleCode string
-- (set directly by @roleCode in sp_users, not a foreign key to
-- dbo.roles.code — confirmed by reading sql/migration/02_programmability.sql:
-- "roleName = ISNULL(@roleCode, roleName)") — so existing sessions with
-- roleName='client' need their own UPDATE, the roles-table rename alone
-- does not fix them retroactively.
--
-- Scope at time of writing: 2 live userCompanies rows (userId 32, 33 —
-- the test accounts created while verifying the /client-login flow this
-- session), 1 live dbo.roles row (roleId 4).
-- =============================================================================

-- Preview — run first.
SELECT roleId, code, name FROM dbo.roles WHERE code = 'client';
SELECT userId, companyId, roleId, roleName FROM dbo.userCompanies WHERE roleName = 'client';

-- The rename.
UPDATE dbo.roles
SET code = 'pos'
WHERE code = 'client';

UPDATE dbo.userCompanies
SET roleName = 'pos'
WHERE roleName = 'client';

-- Verification.
SELECT roleId, code, name FROM dbo.roles WHERE code IN ('client', 'pos');
SELECT userId, companyId, roleId, roleName FROM dbo.userCompanies WHERE roleName IN ('client', 'pos');

-- After this runs successfully, re-run sql/sp_roles.sql (safe/idempotent,
-- additive-only) to pick up the 'myRewards' uiFeature grant for the
-- now-renamed 'pos' role.
