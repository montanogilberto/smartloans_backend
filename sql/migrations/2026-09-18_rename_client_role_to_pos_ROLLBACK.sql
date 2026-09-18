-- Reverts 2026-09-18_rename_client_role_to_pos.sql.
-- WARNING: same caveat as the clientType backfill rollback — if any new
-- userCompanies row was created with roleName='pos' AFTER the forward
-- migration ran (any new /client-login signup), this will also revert
-- those back to 'client', not just the ones the forward migration touched.
-- Only safe to run shortly after the forward migration, before new POS
-- self-service accounts accumulate.

UPDATE dbo.roles
SET code = 'client'
WHERE code = 'pos';

UPDATE dbo.userCompanies
SET roleName = 'client'
WHERE roleName = 'pos';
