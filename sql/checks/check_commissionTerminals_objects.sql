-- =============================================================================
-- Read-only validation: do the objects sp_commissionTerminals.sql needs exist?
-- Safe to run anytime (SELECT only). Run BEFORE and AFTER deploying the SPs.
-- =============================================================================

-- 1) Table: current name vs. the pre-2026-09-18 name the SQL file still uses
SELECT 'table'                                   AS objectKind,
       n.name                                    AS objectName,
       CASE WHEN OBJECT_ID('dbo.' + n.name, 'U') IS NOT NULL
            THEN 'EXISTS' ELSE 'MISSING' END     AS status
FROM (VALUES ('commissionTerminals'), ('commission_terminals')) AS n(name)

UNION ALL

-- 2) Stored procedures the backend calls (modules/commissionTerminals.py)
SELECT 'procedure',
       p.name,
       CASE WHEN OBJECT_ID('dbo.' + p.name, 'P') IS NOT NULL
            THEN 'EXISTS' ELSE 'MISSING' END
FROM (VALUES ('sp_commissionTerminals'),
             ('sp_commissionTerminals_all'),
             ('sp_commissionTerminals_one')) AS p(name)

UNION ALL

-- 3) The income column that points at the catalog
SELECT 'column',
       'income.commissionTerminalId',
       CASE WHEN COL_LENGTH('dbo.income', 'commissionTerminalId') IS NOT NULL
            THEN 'EXISTS' ELSE 'MISSING' END;

-- 4) Stored procedures that reference a table that no longer exists
--    (catches every leftover from a rename batch, not just this module)
SELECT DISTINCT
       OBJECT_NAME(d.referencing_id) AS procedureName,
       d.referenced_entity_name      AS missingObject
FROM sys.sql_expression_dependencies d
WHERE d.referenced_id IS NULL
  AND d.referenced_database_name IS NULL
  AND OBJECTPROPERTY(d.referencing_id, 'IsProcedure') = 1
  AND NOT EXISTS (SELECT 1 FROM sys.objects o WHERE o.name = d.referenced_entity_name)
  AND NOT EXISTS (SELECT 1 FROM sys.types   t WHERE t.name = d.referenced_entity_name)
ORDER BY missingObject, procedureName;
