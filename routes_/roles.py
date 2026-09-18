from fastapi import APIRouter
from modules.roles import all_roles_sp

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
