from fastapi import APIRouter
from modules.orders import orders_sp, all_orders_sp, one_orders_sp


router = APIRouter()

# Read orders  docstring from the file
with open("./docs_description/orders.txt", "r") as file:
    orders_docstring = file.read()
@router.post("/orders",  summary="orders CRUD", description=orders_docstring)
def orders(json: dict):
    return  orders_sp(json)


# Read all orders docstring from the file
with open("./docs_description/orders_all.txt", "r") as file:
    orders_all_docstring = file.read()
@router.get("/all_orders",  summary="all orders", description=orders_all_docstring)
def all_orders():
    return  all_orders_sp()


# Read one user docstring from the file
with open("./docs_description/orders_one.txt", "r") as file:
    order_one_docstring = file.read()
@router.post("/one_orders",  summary="one order", description=order_one_docstring)
def one_orders(json: dict):
    return  one_orders_sp(json)