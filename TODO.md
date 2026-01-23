# Fix pymssql Connection AttributeError

## Issue
The `pymssql._pymssql.Connection` object doesn't have `server` and `database` attributes, causing AttributeError when the code tries to access `conn.server` and `conn.database` for logging.

## Root Cause
In `modules/mercadolibre.py`, the `_get_conn()` function returns a raw `pymssql.Connection` object. The code then tries to access `conn.server` and `conn.database` attributes which don't exist on pymssql connections.

## Solution
Create a wrapper class in `databases.py` that extends the connection object and adds `server` and `database` properties.

## Steps
1. [x] Modify `databases.py` to create a `DatabaseConnection` wrapper class
2. [x] The wrapper class:
     - Stores the raw pymssql connection and connection details
     - Exposes `server` and `database` properties
     - Implements all necessary methods (cursor, close, commit, rollback, context manager)
     - Uses `__getattr__` to forward any other attribute access to the underlying connection
3. [x] Backward compatible with all 36 files that use `connection()` from `databases.py`
4. [x] Syntax verified - no errors

