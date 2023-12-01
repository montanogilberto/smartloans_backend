import pymssql
import os

def connection():
    # Server

    #server = os.getenv("DB_SERVER")
    #database = os.getenv("DB_NAME")
    #username = os.getenv("DB_USER")
    #password = os.getenv("DB_PASSWORD")


    server = "sql.bsite.net\MSSQL2016"
    database = "montanogilberto_smartloans"
    username = "montanogilberto_smartloans"
    password = "Admin#1914"

    connection_string = {
        "server": server,
        "database": database,
        "user": username,
        "password": password,
        "autocommit": True,
    }

    return pymssql.connect(**connection_string)
