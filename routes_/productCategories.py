from fastapi import APIRouter
from modules.productCategories import all_products_categories_sp, products_categories_sp

router = APIRouter()

# Read one user docstring from the file
with open("./docs_description/all_products_categories.txt", "r") as file:
    all_products_categories_docstring = file.read()
@router.post("/all_products_categories",  summary="all product categories", description=all_products_categories_docstring)
def all_products_categories(json: dict):
    return  all_products_categories_sp(json)


# Read products  docstring from the file
with open("./docs_description/products_categories.txt", "r") as file:
    products_categories_docstring = file.read()
@router.post("/products_categories",  summary="products categories CRUD", description=products_categories_docstring)
def products_categories(json: dict):
    return products_categories_sp(json)