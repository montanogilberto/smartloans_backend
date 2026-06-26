import os
import json
import pymssql


class SafeCursor:
    """
    Cursor wrapper that rewrites EXEC SP @pjsonfile = %s calls to use
    a DECLARE + SET pattern, bypassing the FreeTDS tds_dataout_stream_write
    assertion crash that occurs with large NVARCHAR(MAX) parameters.
    """

    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, query: str, args=None):
        # Intercept single-param EXEC ... @pjsonfile = %s calls
        if (
            args
            and len(args) == 1
            and isinstance(args[0], str)
            and "%s" in query
            and "@pjsonfile" in query.lower()
        ):
            json_val = args[0]
            # Use DECLARE + SET to avoid FreeTDS large-string buffer bug.
            # pymssql uses %s placeholders, so pass the value inline after
            # escaping single quotes (no user-controlled injection risk here —
            # this is always a JSON string built internally).
            escaped = json_val.replace("'", "''")
            safe_sql = (
                f"DECLARE @_json NVARCHAR(MAX);\n"
                f"SET @_json = N'{escaped}';\n"
                + query.replace("%s", "@_json")
            )
            return self._cursor.execute(safe_sql)

        # All other queries pass through unchanged
        if args is not None:
            return self._cursor.execute(query, args)
        return self._cursor.execute(query)

    def fetchone(self):
        return self._cursor.fetchone()

    def fetchall(self):
        return self._cursor.fetchall()

    def close(self):
        return self._cursor.close()

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class DatabaseConnection:
    """
    Wrapper around pymssql.Connection.
    Returns SafeCursor from .cursor() to avoid FreeTDS large-payload crash.
    """

    def __init__(self, conn: pymssql.Connection, server: str, database: str):
        self._conn = conn
        self._server = server
        self._database = database

    @property
    def server(self) -> str:
        return self._server

    @property
    def database(self) -> str:
        return self._database

    def cursor(self):
        return SafeCursor(self._conn.cursor())

    def close(self):
        return self._conn.close()

    def commit(self):
        return self._conn.commit()

    def rollback(self):
        return self._conn.rollback()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False

    def __getattr__(self, name):
        return getattr(self._conn, name)


def connection():
    server = os.getenv("LOCAL_DB_SERVER")
    database = os.getenv("LOCAL_DB_NAME")
    username = os.getenv("LOCAL_DB_USER")
    password = os.getenv("LOCAL_DB_PASSWORD")

    missing_vars = [
        name for name, value in {
            "LOCAL_DB_SERVER": server,
            "LOCAL_DB_NAME": database,
            "LOCAL_DB_USER": username,
            "LOCAL_DB_PASSWORD": password,
        }.items() if not value
    ]

    if missing_vars:
        raise ValueError(
            f"Missing required database environment variables: {', '.join(missing_vars)}"
        )

    connection_string = {
        "server": server,
        "database": database,
        "user": username,
        "password": password,
        "autocommit": True,
        "charset": "UTF-8",
        "login_timeout": 10,
        "timeout": 30,
    }

    try:
        raw_conn = pymssql.connect(**connection_string)
        return DatabaseConnection(raw_conn, server, database)
    except Exception as exc:
        raise RuntimeError(
            f"Database connection failed for server '{server}' and database '{database}': {str(exc)}"
        ) from exc
