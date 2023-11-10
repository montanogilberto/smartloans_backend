import pyodbc

def connection():
    # Local
    '''
        server = "USPP01-48840917"
    database = "nom035"
    username = "nom035"
    password = "admin035"
    '''


    # Server
    server = "smartloans.database.windows.net"
    database = "smartloan"
    username = "adminsmart"
    password = "Admin#8605"


    ## f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};DATABASE={database};UID={username};PWD={password}"
    connection_string = f"Driver={{ODBC Driver 18 for SQL Server}};Server={server},Database= {database};Uid = {username};Pwd = {password};Encrypt = yes;TrustServerCertificate = no;ConnectionTimeout = 30"

    return pyodbc.connect(connection_string)