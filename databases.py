import os

def connection():
    server = os.getenv("DB_SERVER")
    database = os.getenv("DB_NAME")
    username = os.getenv("DB_USER")
    password = os.getenv("DB_PASSWORD")

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
