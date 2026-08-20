"""
Generador de los 3 scripts de migracion de base de datos.

Lee el ESQUEMA REAL de la base origen (solo lecturas sobre sys.*) y escribe:

    01_schema_tables.sql   -> tablas, identities, computed, defaults, PK, UNIQUE,
                              CHECK, indices y FOREIGN KEYs
    02_programmability.sql -> views, functions, stored procedures, triggers
    03_data.sql            -> INSERTs de todos los datos (IDENTITY_INSERT + reseed)

Uso:
    python sql/migration/generate_migration.py                 # usa .env
    python sql/migration/generate_migration.py --out sql/migration

Los .sql generados se corren en ORDEN sobre la base NUEVA (ya creada y vacia).
No requiere .bak, ni bacpac, ni permisos de sysadmin: solo SELECT sobre sys.* .
"""

import argparse
import datetime
import decimal
import os
import sys
from collections import defaultdict

import pymssql
from dotenv import load_dotenv

# ---------------------------------------------------------------- conexion

def connect():
    load_dotenv()
    server = os.getenv("LOCAL_DB_SERVER")
    database = os.getenv("LOCAL_DB_NAME")
    user = os.getenv("LOCAL_DB_USER")
    password = os.getenv("LOCAL_DB_PASSWORD")
    if not all([server, database, user, password]):
        sys.exit("Faltan LOCAL_DB_* en .env")
    conn = pymssql.connect(
        server=server, database=database, user=user, password=password,
        login_timeout=15, timeout=300, charset="UTF-8",
    )
    return conn, database


def q(cur, sql):
    cur.execute(sql)
    return cur.fetchall()


def qn(name):
    """Quoted name."""
    return "[" + name.replace("]", "]]") + "]"


# ---------------------------------------------------------------- tipos

NO_LEN = {
    "int", "bigint", "smallint", "tinyint", "bit", "money", "smallmoney",
    "date", "datetime", "smalldatetime", "uniqueidentifier", "sql_variant",
    "xml", "image", "text", "ntext", "geography", "geometry", "hierarchyid",
    "timestamp", "rowversion",
}


def render_type(t, max_len, prec, scale):
    t = t.lower()
    if t in ("nvarchar", "nchar"):
        n = "max" if max_len == -1 else str(max_len // 2)
        return f"{t}({n})"
    if t in ("varchar", "char", "varbinary", "binary"):
        n = "max" if max_len == -1 else str(max_len)
        return f"{t}({n})"
    if t in ("decimal", "numeric"):
        return f"{t}({prec},{scale})"
    if t in ("datetime2", "time", "datetimeoffset"):
        return f"{t}({scale})"
    if t == "float":
        return "float" if prec >= 53 else f"float({prec})"
    if t == "sysname":
        return "nvarchar(128)"
    if t in NO_LEN:
        return t
    return t


# ---------------------------------------------------------------- metadata

def fetch_tables(cur):
    rows = q(cur, """
        SELECT t.object_id, s.name, t.name
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE t.is_ms_shipped = 0 AND t.temporal_type = 0
        ORDER BY s.name, t.name
    """)
    return [{"id": r[0], "schema": r[1], "name": r[2]} for r in rows]


def fetch_columns(cur):
    rows = q(cur, """
        SELECT c.object_id, c.column_id, c.name, ty.name, c.max_length,
               c.precision, c.scale, c.is_nullable, c.is_identity,
               ISNULL(CONVERT(bigint, ic.seed_value), 1),
               ISNULL(CONVERT(bigint, ic.increment_value), 1),
               c.is_computed, cc.definition, ISNULL(cc.is_persisted, 0),
               c.collation_name
        FROM sys.columns c
        JOIN sys.types ty ON ty.user_type_id = c.user_type_id
        JOIN sys.tables t ON t.object_id = c.object_id AND t.is_ms_shipped = 0
        LEFT JOIN sys.identity_columns ic
               ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        LEFT JOIN sys.computed_columns cc
               ON cc.object_id = c.object_id AND cc.column_id = c.column_id
        ORDER BY c.object_id, c.column_id
    """)
    out = defaultdict(list)
    for r in rows:
        out[r[0]].append({
            "column_id": r[1], "name": r[2], "type": r[3], "max_length": r[4],
            "precision": r[5], "scale": r[6], "nullable": r[7],
            "identity": r[8], "seed": r[9], "incr": r[10],
            "computed": r[11], "definition": r[12], "persisted": r[13],
            "collation": r[14],
        })
    return out


def fetch_defaults(cur):
    rows = q(cur, """
        SELECT dc.parent_object_id, c.name, dc.name, dc.definition
        FROM sys.default_constraints dc
        JOIN sys.columns c ON c.object_id = dc.parent_object_id
                          AND c.column_id = dc.parent_column_id
        JOIN sys.tables t ON t.object_id = dc.parent_object_id AND t.is_ms_shipped = 0
    """)
    out = defaultdict(dict)
    for r in rows:
        out[r[0]][r[1]] = (r[2], r[3])
    return out


def fetch_key_constraints(cur):
    """PK + UNIQUE."""
    rows = q(cur, """
        SELECT kc.parent_object_id, kc.name, kc.type, i.type_desc,
               c.name, ic.is_descending_key, ic.key_ordinal
        FROM sys.key_constraints kc
        JOIN sys.indexes i ON i.object_id = kc.parent_object_id
                          AND i.index_id = kc.unique_index_id
        JOIN sys.index_columns ic ON ic.object_id = i.object_id
                                 AND ic.index_id = i.index_id
        JOIN sys.columns c ON c.object_id = ic.object_id
                          AND c.column_id = ic.column_id
        JOIN sys.tables t ON t.object_id = kc.parent_object_id AND t.is_ms_shipped = 0
        ORDER BY kc.parent_object_id, kc.name, ic.key_ordinal
    """)
    out = defaultdict(dict)
    for tid, cname, ctype, idx_type, col, desc, ordinal in rows:
        entry = out[tid].setdefault(cname, {"type": ctype.strip(), "idx": idx_type, "cols": []})
        entry["cols"].append(qn(col) + (" DESC" if desc else ""))
    return out


def fetch_checks(cur):
    rows = q(cur, """
        SELECT cc.parent_object_id, cc.name, cc.definition, cc.is_disabled
        FROM sys.check_constraints cc
        JOIN sys.tables t ON t.object_id = cc.parent_object_id AND t.is_ms_shipped = 0
    """)
    out = defaultdict(list)
    for r in rows:
        out[r[0]].append({"name": r[1], "def": r[2], "disabled": r[3]})
    return out


def fetch_indexes(cur):
    rows = q(cur, """
        SELECT i.object_id, i.name, i.index_id, i.type_desc, i.is_unique,
               i.filter_definition, c.name, ic.is_descending_key,
               ic.is_included_column, ic.key_ordinal
        FROM sys.indexes i
        JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        JOIN sys.tables t ON t.object_id = i.object_id AND t.is_ms_shipped = 0
        WHERE i.is_primary_key = 0 AND i.is_unique_constraint = 0
          AND i.type IN (1, 2) AND i.name IS NOT NULL
        ORDER BY i.object_id, i.index_id, ic.is_included_column, ic.key_ordinal
    """)
    out = defaultdict(dict)
    for tid, iname, iid, itype, uniq, filt, col, desc, included, ordinal in rows:
        e = out[tid].setdefault(iname, {"type": itype, "unique": uniq, "filter": filt,
                                        "keys": [], "incl": []})
        if included:
            e["incl"].append(qn(col))
        else:
            e["keys"].append(qn(col) + (" DESC" if desc else ""))
    return out


FK_ACTION = {0: "NO ACTION", 1: "CASCADE", 2: "SET NULL", 3: "SET DEFAULT"}


def fetch_foreign_keys(cur):
    rows = q(cur, """
        SELECT fk.name, ps.name, pt.name, rs.name, rt.name,
               fk.delete_referential_action, fk.update_referential_action,
               fk.is_disabled, fk.is_not_trusted,
               pc.name, rc.name, fkc.constraint_column_id,
               fk.parent_object_id, fk.referenced_object_id
        FROM sys.foreign_keys fk
        JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
        JOIN sys.tables pt ON pt.object_id = fk.parent_object_id
        JOIN sys.schemas ps ON ps.schema_id = pt.schema_id
        JOIN sys.tables rt ON rt.object_id = fk.referenced_object_id
        JOIN sys.schemas rs ON rs.schema_id = rt.schema_id
        JOIN sys.columns pc ON pc.object_id = fkc.parent_object_id
                           AND pc.column_id = fkc.parent_column_id
        JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id
                           AND rc.column_id = fkc.referenced_column_id
        ORDER BY fk.name, fkc.constraint_column_id
    """)
    out = {}
    for (name, pschema, ptable, rschema, rtable, da, ua, disabled, untrusted,
         pcol, rcol, ordinal, pid, rid) in rows:
        e = out.setdefault(name, {
            "pschema": pschema, "ptable": ptable, "rschema": rschema, "rtable": rtable,
            "delete": FK_ACTION.get(da, "NO ACTION"), "update": FK_ACTION.get(ua, "NO ACTION"),
            "disabled": disabled, "untrusted": untrusted,
            "pcols": [], "rcols": [], "pid": pid, "rid": rid,
        })
        e["pcols"].append(qn(pcol))
        e["rcols"].append(qn(rcol))
    return out


def fetch_modules(cur):
    """Views, functions, procedures, triggers con su definicion original."""
    rows = q(cur, """
        SELECT o.type, s.name, o.name, m.definition, o.create_date
        FROM sys.sql_modules m
        JOIN sys.objects o ON o.object_id = m.object_id
        JOIN sys.schemas s ON s.schema_id = o.schema_id
        WHERE o.is_ms_shipped = 0
        ORDER BY o.type, s.name, o.name
    """)
    return [{"type": r[0].strip(), "schema": r[1], "name": r[2], "def": r[3]} for r in rows]


# ---------------------------------------------------------------- 01 tablas

def build_table_ddl(t, cols, defaults, keys, checks):
    lines = []
    for c in cols:
        if c["computed"]:
            persisted = " PERSISTED" if c["persisted"] else ""
            lines.append(f"    {qn(c['name'])} AS {c['definition']}{persisted}")
            continue
        piece = f"    {qn(c['name'])} {render_type(c['type'], c['max_length'], c['precision'], c['scale'])}"
        if c["identity"]:
            piece += f" IDENTITY({c['seed']},{c['incr']})"
        piece += " NULL" if c["nullable"] else " NOT NULL"
        d = defaults.get(c["name"])
        if d:
            piece += f" CONSTRAINT {qn(d[0])} DEFAULT {d[1]}"
        lines.append(piece)

    for cname, k in sorted(keys.items()):
        kind = "PRIMARY KEY" if k["type"] == "PK" else "UNIQUE"
        clustered = "CLUSTERED" if k["idx"] == "CLUSTERED" else "NONCLUSTERED"
        lines.append(f"    CONSTRAINT {qn(cname)} {kind} {clustered} ({', '.join(k['cols'])})")

    for ck in sorted(checks, key=lambda x: x["name"]):
        lines.append(f"    CONSTRAINT {qn(ck['name'])} CHECK {ck['def']}")

    full = f"{qn(t['schema'])}.{qn(t['name'])}"
    return (f"IF OBJECT_ID(N'{t['schema']}.{t['name']}', N'U') IS NULL\nBEGIN\n"
            f"CREATE TABLE {full} (\n" + ",\n".join(lines) + "\n);\nEND\nGO\n")


def build_index_ddl(t, indexes):
    out = []
    for iname, ix in sorted(indexes.items()):
        uniq = "UNIQUE " if ix["unique"] else ""
        typ = "CLUSTERED " if ix["type"] == "CLUSTERED" else "NONCLUSTERED "
        stmt = (f"CREATE {uniq}{typ}INDEX {qn(iname)} ON "
                f"{qn(t['schema'])}.{qn(t['name'])} ({', '.join(ix['keys'])})")
        if ix["incl"]:
            stmt += f" INCLUDE ({', '.join(ix['incl'])})"
        if ix["filter"]:
            stmt += f" WHERE {ix['filter']}"
        out.append(f"IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'{iname}' "
                   f"AND object_id = OBJECT_ID(N'{t['schema']}.{t['name']}'))\n{stmt};\nGO\n")
    return out


def build_fk_ddl(fk, name):
    parent = f"{qn(fk['pschema'])}.{qn(fk['ptable'])}"
    ref = f"{qn(fk['rschema'])}.{qn(fk['rtable'])}"
    check = "WITH NOCHECK" if fk["untrusted"] else "WITH CHECK"
    stmt = (f"ALTER TABLE {parent} {check} ADD CONSTRAINT {qn(name)} "
            f"FOREIGN KEY ({', '.join(fk['pcols'])}) REFERENCES {ref} ({', '.join(fk['rcols'])})")
    if fk["delete"] != "NO ACTION":
        stmt += f" ON DELETE {fk['delete']}"
    if fk["update"] != "NO ACTION":
        stmt += f" ON UPDATE {fk['update']}"
    body = (f"IF OBJECT_ID(N'{fk['pschema']}.{name}', N'F') IS NULL\nBEGIN\n{stmt};\nEND\nGO\n")
    if fk["disabled"]:
        body += f"ALTER TABLE {parent} NOCHECK CONSTRAINT {qn(name)};\nGO\n"
    else:
        body += f"ALTER TABLE {parent} CHECK CONSTRAINT {qn(name)};\nGO\n"
    return body


# ---------------------------------------------------------------- 03 datos

def literal(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float, decimal.Decimal)):
        return str(v)
    if isinstance(v, (bytes, bytearray)):
        return "0x" + bytes(v).hex().upper() if v else "0x"
    if isinstance(v, datetime.datetime):
        return "'" + v.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "'"
    if isinstance(v, datetime.date):
        return "'" + v.isoformat() + "'"
    if isinstance(v, datetime.time):
        return "'" + v.strftime("%H:%M:%S.%f")[:-3] + "'"
    return "N'" + str(v).replace("'", "''") + "'"


def topo_sort(tables, fks):
    """Ordena tablas: padres antes que hijos (ignora ciclos y auto-referencias)."""
    by_id = {t["id"]: t for t in tables}
    deps = defaultdict(set)
    for fk in fks.values():
        if fk["pid"] != fk["rid"] and fk["pid"] in by_id and fk["rid"] in by_id:
            deps[fk["pid"]].add(fk["rid"])
    ordered, seen, stack = [], set(), set()

    def visit(tid):
        if tid in seen or tid in stack:
            return
        stack.add(tid)
        for d in sorted(deps.get(tid, ())):
            visit(d)
        stack.discard(tid)
        seen.add(tid)
        ordered.append(by_id[tid])

    for t in sorted(tables, key=lambda x: (x["schema"], x["name"])):
        visit(t["id"])
    return ordered


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--batch", type=int, default=200, help="filas por INSERT")
    ap.add_argument("--skip-data", nargs="*",
                    default=["sysdiagrams",
                             # observability: logs historicos, no hacen falta en la base nueva
                             "applicationLogs", "auditLogs", "integrationLogs", "workflowLogs"],
                    help="tablas cuyos datos NO se copian (la tabla si se crea)")
    args = ap.parse_args()

    conn, dbname = connect()
    cur = conn.cursor()
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    header = (f"/* Generado desde [{dbname}] el {stamp}\n"
              f"   por sql/migration/generate_migration.py — NO editar a mano. */\n")

    tables = fetch_tables(cur)
    columns = fetch_columns(cur)
    defaults = fetch_defaults(cur)
    keys = fetch_key_constraints(cur)
    checks = fetch_checks(cur)
    indexes = fetch_indexes(cur)
    fks = fetch_foreign_keys(cur)
    modules = fetch_modules(cur)

    os.makedirs(args.out, exist_ok=True)

    # ---- 01 tablas + relaciones ----
    p1 = os.path.join(args.out, "01_schema_tables.sql")
    with open(p1, "w", encoding="utf-8") as f:
        f.write(header)
        f.write(f"/* PASO 1 de 3 — {len(tables)} tablas, {len(fks)} foreign keys, "
                f"{sum(len(v) for v in indexes.values())} indices */\n")
        f.write("SET ANSI_NULLS ON;\nGO\nSET QUOTED_IDENTIFIER ON;\nGO\n\n")
        f.write("/* ---------- TABLAS ---------- */\n")
        for t in tables:
            f.write(f"\n-- {t['schema']}.{t['name']}\n")
            f.write(build_table_ddl(t, columns[t["id"]], defaults.get(t["id"], {}),
                                    keys.get(t["id"], {}), checks.get(t["id"], [])))
        f.write("\n/* ---------- INDICES ---------- */\n")
        for t in tables:
            for ddl in build_index_ddl(t, indexes.get(t["id"], {})):
                f.write("\n" + ddl)
        f.write("\n/* ---------- FOREIGN KEYS ---------- */\n")
        for name in sorted(fks):
            f.write("\n" + build_fk_ddl(fks[name], name))

    # ---- 02 programabilidad ----
    order = {"V": 0, "FN": 1, "IF": 1, "TF": 1, "P": 2, "PC": 2, "TR": 3}
    label = {"V": "VIEWS", "FN": "FUNCTIONS", "IF": "FUNCTIONS", "TF": "FUNCTIONS",
             "P": "STORED PROCEDURES", "PC": "STORED PROCEDURES", "TR": "TRIGGERS"}
    p2 = os.path.join(args.out, "02_programmability.sql")
    with open(p2, "w", encoding="utf-8") as f:
        f.write(header)
        counts = defaultdict(int)
        for m in modules:
            counts[label.get(m["type"], m["type"])] += 1
        f.write("/* PASO 2 de 3 — " + ", ".join(f"{v} {k.lower()}" for k, v in counts.items()) + " */\n")
        f.write("SET ANSI_NULLS ON;\nGO\nSET QUOTED_IDENTIFIER ON;\nGO\n")
        current = None
        for m in sorted(modules, key=lambda x: (order.get(x["type"], 9), x["schema"], x["name"])):
            grp = label.get(m["type"], m["type"])
            if grp != current:
                current = grp
                f.write(f"\n/* ---------- {grp} ---------- */\n")
            kind = {"V": "V", "FN": "FN", "IF": "IF", "TF": "TF",
                    "P": "P", "PC": "PC", "TR": "TR"}[m["type"]]
            f.write(f"\n-- {m['schema']}.{m['name']}\n")
            f.write(f"IF OBJECT_ID(N'{m['schema']}.{m['name']}', N'{kind}') IS NOT NULL\n"
                    f"    DROP {'VIEW' if kind == 'V' else 'FUNCTION' if kind in ('FN','IF','TF') else 'TRIGGER' if kind == 'TR' else 'PROCEDURE'} "
                    f"{qn(m['schema'])}.{qn(m['name'])};\nGO\n")
            f.write(m["def"].replace("\r\n", "\n").rstrip() + "\nGO\n")

    # ---- 03 datos ----
    skip = {s.lower() for s in args.skip_data}
    ordered = topo_sort(tables, fks)
    p3 = os.path.join(args.out, "03_data.sql")
    total_rows = 0
    with open(p3, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("/* PASO 3 de 3 — copia de datos.\n"
                "   Deshabilita FKs y triggers, inserta, y vuelve a habilitarlos.\n"
                "   Tablas creadas pero SIN datos: "
                + ", ".join(sorted(args.skip_data)) + " */\n")
        f.write("SET NOCOUNT ON;\nGO\n\n")
        f.write("/* -- desactiva validacion de FKs y triggers durante la carga -- */\n")
        for t in ordered:
            full = f"{qn(t['schema'])}.{qn(t['name'])}"
            f.write(f"ALTER TABLE {full} NOCHECK CONSTRAINT ALL;\n")
            f.write(f"DISABLE TRIGGER ALL ON {full};\n")
        f.write("GO\n")

        for t in ordered:
            if t["name"].lower() in skip:
                continue
            cols = [c for c in columns[t["id"]] if not c["computed"]]
            if not cols:
                continue
            names = [c["name"] for c in cols]
            full = f"{qn(t['schema'])}.{qn(t['name'])}"
            cur.execute(f"SELECT {', '.join(qn(n) for n in names)} FROM {full}")
            rows = cur.fetchall()
            if not rows:
                continue
            total_rows += len(rows)
            has_identity = any(c["identity"] for c in cols)
            f.write(f"\n/* ---------- {t['schema']}.{t['name']} — {len(rows)} filas ---------- */\n")
            if has_identity:
                f.write(f"SET IDENTITY_INSERT {full} ON;\nGO\n")
            collist = ", ".join(qn(n) for n in names)
            for i in range(0, len(rows), args.batch):
                chunk = rows[i:i + args.batch]
                f.write(f"INSERT INTO {full} ({collist}) VALUES\n")
                f.write(",\n".join("(" + ", ".join(literal(v) for v in r) + ")" for r in chunk))
                f.write(";\nGO\n")
            if has_identity:
                f.write(f"SET IDENTITY_INSERT {full} OFF;\nGO\n")

        f.write("\n/* -- reactiva FKs (con validacion) y triggers -- */\n")
        for t in ordered:
            full = f"{qn(t['schema'])}.{qn(t['name'])}"
            f.write(f"ALTER TABLE {full} WITH CHECK CHECK CONSTRAINT ALL;\n")
            f.write(f"ENABLE TRIGGER ALL ON {full};\n")
        f.write("GO\n")

        f.write("\n/* -- reinicia los contadores IDENTITY -- */\n")
        for t in ordered:
            if any(c["identity"] for c in columns[t["id"]]):
                f.write(f"DBCC CHECKIDENT ('{t['schema']}.{t['name']}', RESEED);\n")
        f.write("GO\n")

    conn.close()
    for p in (p1, p2, p3):
        print(f"{p}  ({os.path.getsize(p) / 1024:.0f} KB)")
    print(f"tablas: {len(tables)}  objetos: {len(modules)}  filas copiadas: {total_rows}")


if __name__ == "__main__":
    main()
