# Copia este archivo como config.py (git lo ignora) y súbelo al ESP32 junto con main.py.

WIFI_SSID = "NOMBRE_DE_TU_WIFI"
WIFI_PASSWORD = "CONTRASENA_DE_TU_WIFI"

API_BASE = "https://smartloansbackend.azurewebsites.net"

DEVICE_ID = "ID_DEL_DISPOSITIVO"
DEVICE_KEY = "LLAVE_QUE_DEVOLVIO_EL_SERVIDOR"   # se entrega una sola vez al crear/rotar

# Hardware
RELAY_PIN = 26          # salida al relé que enciende la lavadora
RELAY_ACTIVE_HIGH = True
LED_PIN = 2             # LED de estado

# Lector de QR por UART (GM65, GM861 y similares)
SCANNER_UART = 2
SCANNER_TX = 17         # TX del ESP32 -> RX del lector
SCANNER_RX = 16         # RX del ESP32 <- TX del lector
SCANNER_BAUD = 9600

HEARTBEAT_SECONDS = 60
DEFAULT_CYCLE_MINUTES = 45   # se reemplaza con lo que mande el servidor
AUTH_MAX_TRIES = 5
