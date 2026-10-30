# Wi-Fi y HTTP.

import time
import json
import network
import requests

import config as C
import hw

wlan = network.WLAN(network.STA_IF)

HEADERS = {
    "Content-Type": "application/json",
    "X-Device-Id": str(C.DEVICE_ID),
    "X-Device-Key": C.DEVICE_KEY,
}


def wifi_connect(timeout_s=20):
    wlan.active(True)
    if wlan.isconnected():
        return True
    print("Conectando a Wi-Fi", C.WIFI_SSID)
    wlan.connect(C.WIFI_SSID, C.WIFI_PASSWORD)
    start = time.ticks_ms()
    while not wlan.isconnected():
        if time.ticks_diff(time.ticks_ms(), start) > timeout_s * 1000:
            print("Wi-Fi: timeout")
            return False
        hw.feed()
        time.sleep_ms(250)
    print("Wi-Fi OK:", wlan.ifconfig()[0])
    sync_time()
    return True


def sync_time():
    """Pone el reloj del ESP32 en UTC por NTP. main.py lo llama al arrancar aunque
    el Wi-Fi ya esté conectado: Thonny, al conectarse, pone el reloj en la hora
    local de la computadora, y la pantalla sumaría otra vez la zona horaria."""
    try:
        import ntptime
        ntptime.settime()
        return True
    except Exception as e:
        print("NTP falló:", e)
        return False


def ensure_wifi():
    if not wlan.isconnected():
        wifi_connect()


def post(path, body):
    """Devuelve (status, dict). status = None si hubo error de red."""
    r = None
    try:
        r = requests.post(C.API_BASE + path, data=json.dumps(body),
                          headers=HEADERS, timeout=10)
        status = r.status_code
        try:
            data = r.json()
        except Exception:
            data = {}
        return status, data
    except Exception as e:
        print("Error de red en", path, ":", e)
        return None, {}
    finally:
        if r:
            r.close()
        hw.feed()
