"""
roles — the application's authorization/UI configuration layer: role
identity (dbo.roles) plus the uiFeatures and signupGroups catalogs each
role is linked to via roleUiFeatures / roleGroups. Replaces the frontend's
previously hardcoded roles.ts (RoleCode / ROLE_LABELS / ROLE_DESCRIPTIONS /
ROLE_EMOJI / ROLE_UI / ROLE_GROUPS) with a DB-backed read.

Spec: sql/sp_roles.sql
Does not touch role assignment (dbo.roles.code is still what sp_login /
userCompanies.roleId key off of). Writes: update_role_ui_features_sp
(sql/sp_roleUiFeatures_update.sql) replaces one role's uiFeatures, for the
frontend /setting screen.

sp_roles returns the raw role array (not the app's {"result":[...]}
envelope) -- that wrapping happens here, so the SQL side stays a plain
data contract and doesn't hand-build response envelope JSON.
"""

import json
from fastapi.responses import JSONResponse
from databases import connection
from observability.logger import log_audit


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


def _role_features(role_code: str) -> list:
    """The role's current active features as sp_roles returns them ([] if unknown)."""
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_roles]")
        raw = cursor.fetchone()[0]
        for role in json.loads(raw) if raw else []:
            if role.get("code") == role_code:
                return role.get("uiFeatures") or []
        return []
    finally:
        if conn:
            conn.close()


def update_role_ui_features_sp(json_file: dict):
    """Replace one role's UI features. json_file:
    {"roleUiFeatures": [{"roleCode": str, "features": [str, ...]}]}.
    Global: dbo.roleUiFeatures has no companyId, so this applies to the role
    in every company."""
    conn = None
    try:
        rows = json_file.get("roleUiFeatures") if isinstance(json_file, dict) else None
        if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict) \
                or not isinstance(rows[0].get("features"), list):
            return JSONResponse(
                content={"result": [{"error": "1", "msg": "Expected one roleUiFeatures row with a features array"}]},
                status_code=400,
            )
        role_code = str(rows[0].get("roleCode") or "").strip().lower()
        before = _role_features(role_code)

        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_roleUiFeatures_update] @pjsonfile = %s",
                       (json.dumps({"roleUiFeatures": [{"roleCode": role_code,
                                                        "features": rows[0]["features"]}]}),))
        value, msg, error = cursor.fetchone()
        if str(error) == "1":
            return JSONResponse(content={"result": [{"error": "1", "msg": msg}]}, status_code=400)

        conn.close()
        conn = None
        after = _role_features(role_code)
        log_audit("roleUiFeatures", None, role_code, sorted(before), sorted(after))
        return JSONResponse(
            content={"result": [{"roleCode": role_code, "uiFeatures": after, "value": value,
                                 "msg": "OK", "error": "0"}]},
            status_code=200,
        )
    except Exception as e:
        return JSONResponse(content={"result": [{"error": "1", "msg": str(e)}]}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_ui_features_sp():
    """The module/feature registry (dbo.uiFeatures, sql/sp_uiFeatures.sql): every
    active feature with label/section/icon/route/sortOrder. Read-only, open like
    GET /roles — it holds UI metadata, no customer data."""
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_uiFeatures_all]")
        raw = "".join(r[0] for r in cursor.fetchall() if r and r[0])
        features = json.loads(raw) if raw else []
        return JSONResponse(
            content={"result": [{"uiFeatures": features, "msg": "OK", "error": "0"}]},
            status_code=200,
        )
    except Exception as e:
        return JSONResponse(content={"result": [{"error": "1", "msg": str(e)}]}, status_code=500)
    finally:
        if conn:
            conn.close()
