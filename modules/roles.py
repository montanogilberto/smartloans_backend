"""
roles — the application's authorization/UI configuration layer: role
identity (dbo.roles) plus the uiFeatures and signupGroups catalogs each
role is linked to via roleUiFeatures / roleGroups. Replaces the frontend's
previously hardcoded roles.ts (RoleCode / ROLE_LABELS / ROLE_DESCRIPTIONS /
ROLE_EMOJI / ROLE_UI / ROLE_GROUPS) with a DB-backed read.

Spec: sql/sp_roles.sql
Does not touch role assignment (dbo.roles.code is still what sp_login /
userCompanies.roleId key off of) -- this is a read-only catalog endpoint.

sp_roles returns the raw role array (not the app's {"result":[...]}
envelope) -- that wrapping happens here, so the SQL side stays a plain
data contract and doesn't hand-build response envelope JSON.
"""

import json
from fastapi.responses import JSONResponse
from databases import connection


def all_roles_sp():
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_roles]")
        roles_json = cursor.fetchone()[0]
        roles = json.loads(roles_json) if roles_json else []
        return JSONResponse(
            content={"result": [{"roles": roles, "msg": "OK", "error": "0"}]},
            status_code=200,
        )
    except Exception as e:
        return JSONResponse(
            content={"result": [{"error": "1", "msg": str(e)}]},
            status_code=500,
        )
    finally:
        if conn:
            conn.close()
