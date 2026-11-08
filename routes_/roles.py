from fastapi import APIRouter, Depends, HTTPException, Request
from modules.roles import all_roles_sp, all_ui_features_sp, update_role_ui_features_sp
from security.session_tokens import _bearer, decode

router = APIRouter()


@router.get(
    "/roles",
    summary="Role catalog (labels, descriptions, emoji, UI features, wizard groups)",
    description="""Read-only catalog of active application roles, replacing the previously
hardcoded frontend role config (RoleCode / ROLE_LABELS / ROLE_DESCRIPTIONS / ROLE_EMOJI /
ROLE_UI / ROLE_GROUPS). Labels/descriptions are stored in English.

Returns: { "result": [{ "roles": [{ "roleId": int, "code": str, "name": str,
"description": str, "emoji": str, "active": bool, "uiFeatures": string[],
"groups": string[] }], "msg": "OK", "error": "0" }] }

"uiFeatures" is the set of UI feature codes the role can access (was ROLE_UI).
"groups" is which signup-wizard groups the role appears in: "pos" | "loans" | "custom"
(was ROLE_GROUPS). Does not affect role assignment at login/signup.""",
)
def roles():
    return all_roles_sp()


@router.get(
    "/ui_features",
    summary="Module/feature registry (what /setting can grant per role)",
    description="""Every active UI feature from dbo.uiFeatures with its registry fields.
New factory modules register themselves here via sp_uiFeatures_register.

Returns: { "result": [{ "uiFeatures": [{ "featureId": int, "featureCode": str,
"displayName": str, "label": str|null, "moduleCode": str|null, "section": str|null,
"icon": str|null, "route": str|null, "sortOrder": int|null }], "msg": "OK", "error": "0" }] }

section null = not configurable in /setting (e.g. customer self-service features).""",
)
def ui_features():
    return all_ui_features_sp()


async def _require_admin_session(request: Request) -> None:
    """Role permissions are global (dbo.roleUiFeatures has no companyId), so
    only an 'admin' session may change them — not a manager, and not the
    worker key. The role comes from the signed token, never from the body."""
    claims = decode(_bearer(request), "access")
    if claims is None:
        # 401, not 403: it is what makes the app refresh its token and retry.
        raise HTTPException(status_code=401, detail="Session expired")
    roles = {str(c.get("role") or "").strip().lower() for c in claims.get("companies") or []}
    if "admin" not in roles:
        raise HTTPException(status_code=403, detail="Forbidden")


@router.post(
    "/roles/ui_features",
    summary="Replace the UI features granted to one role (admin only)",
    description="""Body: { "roleUiFeatures": [{ "roleCode": str, "features": string[] }] }.
Replaces the role's active UI features with exactly that list. GLOBAL: applies to the
role in every company. The 'admin' role can't be edited. Unknown feature codes are refused.
Returns: { "result": [{ "roleCode": str, "uiFeatures": string[], "msg": "OK", "error": "0" }] }""",
    dependencies=[Depends(_require_admin_session)],
)
def update_role_ui_features(json: dict):
    return update_role_ui_features_sp(json)
