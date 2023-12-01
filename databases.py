import os
import pymssql
import os

    #server = "sql.bsite.net\MSSQL2016"
    #database = "montanogilberto_smartloans"
    #username = "montanogilberto_smartloans"
    #password = "Admin#1914"

def connection():
    server = os.getenv("LOCAL_DB_SERVER")
    database = os.getenv("LOCAL_DB_NAME")
    username = os.getenv("LOCAL_DB_USER")
    password = os.getenv("LOCAL_DB_PASSWORD")

    print(f"server: {server}, database: {database}, username: {username}, password: {password}")

    if None in (server, database, username, password):
        raise ValueError("One or more required environment variables are missing.")

    connection_string = {
        "server": server,
        "database": database,
        "user": username,
        "password": password,
        "autocommit": True,
    }

    return pymssql.connect(**connection_string)
