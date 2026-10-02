#!/usr/bin/env python3
"""
Fail the build if any backend Python issues raw SQL.

Backend rule: modules never issue raw SQL -- every read and mutation goes
through a stored procedure (EXEC [dbo].[sp_*]). A 2026-09-23 audit found 23
raw statements in modules/ that nothing had caught; they were all moved to
SPs (sql/migrations/2026-09-23_add_*.sql). This check keeps it that way.

    python scripts/check_raw_sql.py            # scan the repo, exit 1 on hits
    python scripts/check_raw_sql.py modules/x.py

The detector below (find_raw_sql and helpers) is a VERBATIM copy of
Agent_POSGMO/posgmo-factory/agents/reviewer/raw_sql.py -- the Factory's
reviewer runs the same check on generated modules. Change both together.

Excluded: venv/, __pycache__/, and sql/migration/ (the migration generator
reads SQL Server's own catalog views; it is tooling, not app code).
"""

from __future__ import annotations

import ast
import os
import re
import sys
from dataclasses import dataclass

_EXEC_PREFIX = re.compile(r"^\s*EXEC(UTE)?\b", re.IGNORECASE)

_TABLE = r"[\w\[\]#@.]+"
_SQL_STATEMENT = re.compile(
    r"^\s*(?:"
    r"SELECT\b[\s\S]*?\bFROM\s+" + _TABLE +
    r"|INSERT\s+(?:INTO\s+)?" + _TABLE +
    r"|UPDATE\s+" + _TABLE + r"\s+SET\b"
    r"|DELETE\s+(?:FROM\s+)?" + _TABLE +
    r"|MERGE\s+(?:INTO\s+)?" + _TABLE +
    r"|TRUNCATE\s+TABLE\b"
    r"|(?:CREATE|ALTER|DROP)\s+(?:TABLE|PROC|PROCEDURE|VIEW|INDEX)\b"
    r")"
)


@dataclass(frozen=True)
class RawSql:
    line: int
    kind: str      # "execute_literal" | "sql_literal"
    snippet: str

    def __str__(self) -> str:
        return f"line {self.line}: {self.snippet}"


def _literal_text(node: ast.AST) -> str | None:
    """Text of a str constant, or the constant parts of an f-string
    (placeholders become '{}'); None for anything else."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        return "".join(
            v.value if isinstance(v, ast.Constant) and isinstance(v.value, str) else "{}"
            for v in node.values
        )
    return None


def _docstring_nodes(tree: ast.AST) -> set[int]:
    ids: set[int] = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            body = getattr(node, "body", None) or []
            if body and isinstance(body[0], ast.Expr) and _literal_text(body[0].value) is not None:
                ids.add(id(body[0].value))
    return ids


def _snippet(text: str) -> str:
    return " ".join(text.split())[:100]


def _find_with_regex(source: str) -> list[RawSql]:
    """Fallback for content that does not parse (LLM output mid-repair)."""
    found = []
    pat = re.compile(r"""\.execute(?:many)?\s*\(\s*[fFrRbBuU]{0,2}("{3}|'{3}|"|')(.*?)\1""", re.DOTALL)
    for m in pat.finditer(source):
        text = m.group(2)
        if not _EXEC_PREFIX.match(text):
            found.append(RawSql(source.count("\n", 0, m.start()) + 1, "execute_literal", _snippet(text)))
    return found


def find_raw_sql(source: str) -> list[RawSql]:
    """All raw-SQL sites in a Python module's source. [] means clean."""
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return _find_with_regex(source)

    docstrings = _docstring_nodes(tree)
    found: dict[tuple[int, str], RawSql] = {}
    execute_args: set[int] = set()

    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr in ("execute", "executemany")
            and node.args
        ):
            text = _literal_text(node.args[0])
            if text is not None:
                execute_args.add(id(node.args[0]))
                if not _EXEC_PREFIX.match(text):
                    found[(node.lineno, "execute_literal")] = RawSql(node.lineno, "execute_literal", _snippet(text))

    # f-string pieces are visited as Constants too; judge the whole JoinedStr only
    fstring_parts = {id(v) for n in ast.walk(tree) if isinstance(n, ast.JoinedStr) for v in n.values}
    skip = docstrings | execute_args | fstring_parts

    for node in ast.walk(tree):
        if id(node) in skip:
            continue
        text = _literal_text(node)
        if text is None:
            continue
        if _SQL_STATEMENT.match(text):
            line = getattr(node, "lineno", 0)
            if (line, "execute_literal") not in found:
                found[(line, "sql_literal")] = RawSql(line, "sql_literal", _snippet(text))

    return sorted(found.values(), key=lambda r: (r.line, r.kind))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

_EXCLUDED_DIRS = {"venv", ".venv", "__pycache__", ".git", "node_modules"}
_EXCLUDED_PATHS = (os.path.join("sql", "migration") + os.sep,)


def _python_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in _EXCLUDED_DIRS)
        for name in sorted(filenames):
            if name.endswith(".py"):
                path = os.path.relpath(os.path.join(dirpath, name), root)
                if not path.startswith(_EXCLUDED_PATHS):
                    yield path


def main(argv: list[str]) -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    paths = argv or list(_python_files(root))
    hits = 0
    for path in paths:
        full = path if os.path.isabs(path) else os.path.join(root, path)
        with open(full, encoding="utf-8", errors="ignore") as fh:
            for hit in find_raw_sql(fh.read()):
                hits += 1
                print(f"{path}:{hit.line}: raw SQL ({hit.kind}): {hit.snippet}")
    if hits:
        print(f"\n{hits} raw SQL statement(s). Only EXEC [dbo].[sp_*] calls are allowed "
              "-- add or extend a stored procedure instead.")
        return 1
    print(f"OK: no raw SQL in {len(paths)} file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
