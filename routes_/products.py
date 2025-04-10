from fastapi import APIRouter
from modules.products import products_sp, all_products_sp, one_products_sp, food_products_sp, food_categories_products_sp


router = APIRouter()

# Read products  docstring from the file
with open("./docs_description/products.txt", "r") as file:
    products_docstring = file.read()
@router.post("/products",  summary="products CRUD", description=products_docstring)
def products(json: dict):
    return  products_sp(json)


# Read all products docstring from the file
with open("./docs_description/products_all.txt", "r") as file:
    products_all_docstring = file.read()
@router.get("/all_products",  summary="all products", description=products_all_docstring)
def all_products():
    return  all_products_sp()


# Read one user docstring from the file
with open("./docs_description/products_one.txt", "r") as file:
    product_one_docstring = file.read()
@router.post("/one_products",  summary="one product", description=product_one_docstring)
def one_products(json: dict):
    return  one_products_sp(json)


# Read one user docstring from the file
with open("./docs_description/products_food.txt", "r") as file:
    product_food_docstring = file.read()
@router.get("/food_products",  summary="food product", description=product_food_docstring)
def food_products():
    return  food_products_sp()


# Read one user docstring from the file
with open("./docs_description/products_food_categories.txt", "r") as file:
    product_food_docstring = file.read()
@router.get("/food_categories_products",  summary="food categories product", description=product_food_docstring)
def food_categories_products():
    return  food_categories_products_sp()