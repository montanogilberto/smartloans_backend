from fastapi import APIRouter
from modules.utils import select_all_tables, select_one_row, select_elements_with_one_filter, select_info_tables

router = APIRouter()

# Read the content of the file and assign it to the utils_doc variable as a string
with open("./docs_description/utils_database_info_tables.txt", "r") as file:
    utils_doc_database = file.read()
@router.get("/select_info_tables", summary="select information about the all tables", description=utils_doc_database)  # Return all the elements from the selected table, one selected field, and its value
def select_info_tables_():
    return select_info_tables()

@router.get("/select_all_tables/{table_name}", summary="get all data from specific table",
            description="Endpoint to get all data for each table")
def select_all_tables_(table_name: str):
    """
    Body format:
    url/select_all_tables/users (as example)
    """
    return select_all_tables(table_name)

# Read the content of the file and assign it to the utils_doc variable as a string
with open("./docs_description/utils_select_one_row.txt", "r") as file:
    utils_doc_one_row = file.read()
@router.post("/select_one_row", summary="select all information from the table by identifier field", description=utils_doc_one_row)  # Return one row from the selected table with the selected id number
def select_one_row_(json: dict):
    return select_one_row(json)

# Read the content of the file and assign it to the utils_doc variable as a string
with open("./docs_description/utils_select_elements_with_filter.txt", "r") as file:
    utils_doc_filter = file.read()
@router.post("/select_elements_with_filter", summary="select all information from the table by specific field", description=utils_doc_filter)  # Return all the elements from the selected table, one selected field, and its value
def select_elements_with_filter(json: dict):
    return select_elements_with_one_filter(json)