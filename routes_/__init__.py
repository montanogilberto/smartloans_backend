from .login import router as login_router
from .utils import router as utils_router
from .swagger import router as swagger_router
from .users import router as users_router
from .symptoms import router as symptoms_router
from .scannertext import router as scannertext_router
from .products import router as products_router

__all__ = [
    "login_router",
    "utils_router",
    "swagger_router",
    "users_router",
    "symptoms_router",
    "scannertext_router",
    "products_router",
]
