# Migracion de base de datos sin `.bak`

Scripts para levantar una copia completa de **`montanogilberto_smartloans`** en una
base de datos NUEVA, usando solo T-SQL (sin backup/restore, sin bacpac, sin sysadmin).

Todo se genero leyendo el **esquema real de la base viva** (`sys.*`), no los `.sql`
sueltos del repo — esos ya no reflejan la base (drift historico).

## Los 3 scripts

| Orden | Archivo | Contenido |
|---|---|---|
| 1 | `01_schema_tables.sql` | 141 tablas (columnas, IDENTITY, computed, DEFAULT, PK, UNIQUE, CHECK) + 100 indices + 44 foreign keys |
| 2 | `02_programmability.sql` | 3 views, 1 funcion, 188 stored procedures, 1 trigger (193 objetos) |
| 3 | `03_data.sql` | 7,328 filas en 103 tablas, con `IDENTITY_INSERT` y reseed |

Extra: `04_verify.sql` — se corre en ambas bases y se comparan los resultados.

## Como correrlos

1. Crea la base nueva y **vacia** (`CREATE DATABASE mi_base_nueva;` o desde el panel
   del hosting). Usa la misma collation que el origen: `SQL_Latin1_General_CP1_CI_AS`.
2. En SSMS / Azure Data Studio: conectate, selecciona la base nueva
   (`USE [mi_base_nueva];` o el dropdown) y ejecuta **en este orden**:

   ```
   01_schema_tables.sql
   02_programmability.sql
   03_data.sql
   ```

   Cada archivo usa separadores `GO`, asi que hay que correrlo con SSMS, Azure Data
   Studio o `sqlcmd` (no con un cliente que mande todo como un solo batch):

   ```bash
   sqlcmd -S servidor\MSSQL2016 -U usuario -P '***' -d mi_base_nueva -i 01_schema_tables.sql
   ```

3. Corre `04_verify.sql` en la base **origen** y en la **nueva**, y compara.

Los tres scripts son **idempotentes**: las tablas, indices y FKs se crean solo si no
existen, y los procedures/views hacen `DROP` + `CREATE`. Se pueden re-correr 1 y 2
sin romper nada. `03_data.sql` **no** es idempotente: si lo corres dos veces duplicas
filas (o truena por PK). Para recargar datos, vacia las tablas primero.

### Que hace `03_data.sql` por dentro

1. `NOCHECK CONSTRAINT ALL` + `DISABLE TRIGGER ALL` en todas las tablas (asi el orden
   de insercion y los ciclos de FK no importan, y el trigger `trg_users_set_qr` no
   dispara durante la carga).
2. Los `INSERT ... VALUES` en lotes de 200 filas, con `SET IDENTITY_INSERT ON/OFF`
   para conservar los ids originales.
3. `WITH CHECK CHECK CONSTRAINT ALL` + `ENABLE TRIGGER ALL` — si alguna FK quedara
   violada, aqui truena (y `04_verify.sql` lo reporta).
4. `DBCC CHECKIDENT (..., RESEED)` en las 131 tablas con IDENTITY, para que el
   proximo insert siga la numeracion correcta.

## Regenerar

Los `.sql` son una **foto** del origen (generada 2026-08-15). Si el esquema cambia,
regenera en vez de editar a mano:

```bash
./venv/bin/python sql/migration/generate_migration.py
```

Lee las credenciales de `.env` (`LOCAL_DB_*`) y solo hace `SELECT` sobre `sys.*` y
sobre los datos: no modifica el origen.

Validar sintaxis de lo generado (usa `SET PARSEONLY ON` contra `tempdb`, no ejecuta
nada):

```bash
./venv/bin/python sql/migration/validate_scripts.py
```

## Notas / limites conocidos

- **Tablas que se crean pero llegan vacias** (las tablas, sus indices y sus FKs si
  se crean en el paso 1; solo se omiten sus filas):
  - Observability: `applicationLogs`, `auditLogs`, `integrationLogs`, `workflowLogs`
    — son logs historicos, no hacen falta en la base nueva.
  - `sysdiagrams` — diagramas de SSMS.

  Para copiarlas tambien: `python sql/migration/generate_migration.py --skip-data`
  (sin argumentos = no omitir ninguna). Con los logs incluidos son 24,018 filas y
  el `03_data.sql` pesa ~3.9 MB en lugar de ~700 KB.
- **Extended properties** (9, todas marcadores `microsoft_database_tools_support`
  de SSMS) no se scriptean — no afectan a la aplicacion.
- No hay usuarios/roles/permisos, jobs del Agent, ni Service Broker en estos
  scripts. Si la base nueva la usa otro login, hay que crear el usuario y darle
  permisos aparte.
- La base no tiene tipos definidos por el usuario, particiones, ni tablas
  temporales de sistema, asi que nada de eso se pierde.
- El origen es SQL Server 2022 Standard; el destino debe ser 2016+ para que todo
  el T-SQL de los procedures compile igual.
