"""
Valida la SINTAXIS de los 3 scripts generados sin ejecutarlos.

Se conecta a tempdb (nunca a la base de negocio) y corre cada batch con
SET PARSEONLY ON, que hace que SQL Server parsee la sentencia y NO la ejecute.
Doble proteccion: base tempdb + PARSEONLY reactivado antes de cada batch.

Uso:  python sql/migration/validate_scripts.py
"""

import os
import re
import sys

import pymssql
from dotenv import load_dotenv

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = ["01_schema_tables.sql", "02_programmability.sql", "03_data.sql"]
SPLIT = re.compile(r"^\s*GO\s*$", re.M | re.I)


def main():
    load_dotenv()
    conn = pymssql.connect(
        server=os.getenv("LOCAL_DB_SERVER"), database="tempdb",
        user=os.getenv("LOCAL_DB_USER"), password=os.getenv("LOCAL_DB_PASSWORD"),
        login_timeout=15, timeout=300, charset="UTF-8", autocommit=True,
    )
    cur = conn.cursor()
    failures = 0
    for fname in FILES:
        path = os.path.join(HERE, fname)
        text = open(path, encoding="utf-8").read()
        batches = [b for b in SPLIT.split(text) if b.strip()]
        bad = 0
        for i, batch in enumerate(batches, 1):
            try:
                cur.execute("SET PARSEONLY ON;\n" + batch)
            except Exception as exc:  # noqa: BLE001
                bad += 1
                failures += 1
                if bad <= 5:
                    print(f"\n[{fname}] batch {i}: {exc}")
                    print("   " + batch.strip()[:300].replace("\n", "\n   "))
        print(f"{fname}: {len(batches)} batches, {bad} con error de sintaxis")
    cur.execute("SET PARSEONLY OFF;")
    conn.close()
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
