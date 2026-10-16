/* Verificacion post-migracion.
   Correr este mismo script en la base ORIGEN y en la base NUEVA
   y comparar los 3 resultados: deben ser identicos. */

SET NOCOUNT ON;

-- 1) Resumen de objetos
SELECT DB_NAME() AS baseDatos,
       (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0)                     AS tablas,
       (SELECT COUNT(*) FROM sys.views WHERE is_ms_shipped = 0)                      AS vistas,
       (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0)                 AS procedures,
       (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN','IF','TF') AND is_ms_shipped = 0) AS funciones,
       (SELECT COUNT(*) FROM sys.triggers WHERE is_ms_shipped = 0)                   AS triggers,
       (SELECT COUNT(*) FROM sys.foreign_keys)                                       AS foreignKeys,
       (SELECT COUNT(*) FROM sys.key_constraints WHERE type = 'PK')                  AS primaryKeys,
       (SELECT COUNT(*) FROM sys.check_constraints)                                  AS checks,
       (SELECT COUNT(*) FROM sys.default_constraints)                                AS defaults,
       (SELECT COUNT(*) FROM sys.indexes
         WHERE is_primary_key = 0 AND is_unique_constraint = 0 AND index_id > 0 AND name IS NOT NULL
           AND object_id IN (SELECT object_id FROM sys.tables))                      AS indices;

-- 2) Filas por tabla (comparar linea por linea)
SELECT s.name AS esquema, t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name
ORDER BY s.name, t.name;

-- 3) Foreign keys que quedaron sin validar (deberia devolver 0 filas)
SELECT name AS foreignKeyNoConfiable, OBJECT_NAME(parent_object_id) AS tabla
FROM sys.foreign_keys
WHERE is_not_trusted = 1 OR is_disabled = 1;
