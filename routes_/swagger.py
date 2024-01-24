from fastapi import APIRouter
from fastapi.openapi.docs import get_redoc_html, get_swagger_ui_html
from fastapi.openapi.utils import get_openapi
from starlette.responses import JSONResponse

router = APIRouter()


# Swagger UI and ReDoc modules
@router.get("/docs", include_in_schema=False)
async def custom_swagger_ui_html():
    # Remove specific sections
    config = {
        "swagger_ui": {"excluded_menu_items": ["settings", "auth"]},
        "swagger_ui_init_oauth": {
            "scopes": {
                "read:items": "Read items",
                "write:items": "Create or update items",
            }
        },
    }
    return get_swagger_ui_html(
        openapi_url="/openapi.json",
        title="docs",
        oauth2_redirect_url="/docs/oauth2-redirect",
        config=config,
    )


@router.get("/redoc", include_in_schema=False)
async def redoc_html():
    return get_redoc_html(openapi_url="/openapi.json", title="redoc")


@router.get("/openapi.json", include_in_schema=False)
async def openapi_json():
    return JSONResponse(content=get_openapi(title="SmartLoans", version="1.0.0", routes=router.routes))
