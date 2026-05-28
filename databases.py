import os
import pymssql


class DatabaseConnection:
    """
    Wrapper class for pymssql.Connection that adds server and database properties.
    This is needed because pymssql connections don't expose these attributes directly.
    """
    
    def __init__(self, conn: pymssql.Connection, server: str, database: str):
        self._conn = conn
        self._server = server
        self._database = database
    
    @property
    def server(self) -> str:
        """Server address."""
        return self._server
    
    @property
    def database(self) -> str:
        """Database name."""
        return self._database
    
    def cursor(self):
        """Return a cursor object."""
        return self._conn.cursor()
    
    def close(self):
        """Close the connection."""
        return self._conn.close()
    
    def commit(self):
        """Commit the current transaction."""
        return self._conn.commit()
    
    def rollback(self):
        """Rollback the current transaction."""
        return self._conn.rollback()
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()
        return False
    
    def __getattr__(self, name):
        """Forward any other attribute access to the underlying connection."""
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
    }

    try:
        raw_conn = pymssql.connect(**connection_string)
        return DatabaseConnection(raw_conn, server, database)
    except Exception as exc:
        raise RuntimeError(
            f"Database connection failed for server '{server}' and database '{database}': {str(exc)}"
        ) from exc
