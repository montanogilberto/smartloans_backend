import pymssql


def connection():
    # Server
    server = "smartloans.database.windows.net"
    database = "smartloan"
    username = "adminsmart"
    password = "Admin#8605"

    connection_string = {
        "server": server,
        "database": database,
        "user": username,
        "password": password,
        "autocommit": True,
    }

    return pymssql.connect(**connection_string)
