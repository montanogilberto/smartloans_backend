# Wi-Fi y HTTP.
#
# Las redes Wi-Fi ya no van en config.py: se guardan en la placa (wifi.json)
# cuando se escanea el QR de la red en la pantalla de configuración (main.py).
# Si config.py todavía trae WIFI_SSID / WIFI_PASSWORD, se usan como última opción.

import gc
import time
import json
import errno
import network
import requests

import config as C
import hw

wlan = network.WLAN(network.STA_IF)
WIFI_FILE = "wifi.json"
MAX_NETWORKS = 5

HEADERS = {
    "Content-Type": "application/json",
    "X-Device-Id": str(C.DEVICE_ID),
    "X-Device-Key": C.DEVICE_KEY,
}


# ---------- redes guardadas ----------
def saved_networks():
    """[{ssid, password}] en orden de preferencia: las de wifi.json y, al final,
    la de config.py si existe."""
    nets = []
    try:
        with open(WIFI_FILE) as f:
            nets = [n for n in json.load(f) if n.get("ssid")]
    except (OSError, ValueError):
        pass
    ssid = getattr(C, "WIFI_SSID", "")
    if ssid and all(n["ssid"] != ssid for n in nets):
        nets.append({"ssid": ssid, "password": getattr(C, "WIFI_PASSWORD", "")})
    return nets


def save_network(ssid, password):
    """Guarda la red como la primera opción (la última que funcionó)."""
    nets = [n for n in saved_networks() if n["ssid"] != ssid]
    nets.insert(0, {"ssid": ssid, "password": password})
    with open(WIFI_FILE, "w") as f:
        json.dump(nets[:MAX_NETWORKS], f)


def parse_wifi_qr(text):
    """QR de Wi-Fi de iPhone/Android: WIFI:T:WPA;S:<red>;P:<contraseña>;H:false;;
    Devuelve (ssid, password) o None. Respeta los escapes \\; \\, \\: \\\\ \\"."""
    if not text or not text.upper().startswith("WIFI:"):
        return None
    fields, key, val, i, body = {}, "", "", 0, text[5:]
    reading_key = True
    while i < len(body):
        ch = body[i]
        if ch == "\\" and i + 1 < len(body):
            if reading_key:
                key += body[i + 1]
            else:
                val += body[i + 1]
            i += 2
            continue
        if reading_key and ch == ":":
            reading_key = False
        elif not reading_key and ch == ";":
            fields[key.strip().upper()] = val
            key, val, reading_key = "", "", True
        elif reading_key:
            key += ch
        else:
            val += ch
        i += 1
    ssid = fields.get("S", "")
    if not ssid:
        return None
    return ssid, fields.get("P", "")


# ---------- conexión ----------
def try_network(ssid, password, timeout_s=20):
    """Intenta una red. True si conectó."""
    wlan.active(True)
    try:
        wlan.disconnect()
    except OSError:
        pass
    print("Conectando a Wi-Fi", ssid)
    wlan.connect(ssid, password)
    start = time.ticks_ms()
    while not wlan.isconnected():
        if time.ticks_diff(time.ticks_ms(), start) > timeout_s * 1000:
            print("Wi-Fi: no conectó a", ssid)
            return False
        hw.feed()
        time.sleep_ms(250)
    print("Wi-Fi OK:", ssid, wlan.ifconfig()[0])
    sync_time()
    return True


def wifi_connect(timeout_s=20):
    """Conecta con la primera red guardada que responda. False si ninguna."""
    wlan.active(True)
    if wlan.isconnected():
        return True
    for n in saved_networks():
        if try_network(n["ssid"], n.get("password", ""), timeout_s):
            return True
    return False


def current_ssid():
    try:
        return wlan.config("essid") if wlan.isconnected() else ""
    except (OSError, ValueError):
        return ""


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


def diag():
    """Estado de la red y de la memoria, para el log cuando falla una petición.
    TLS (mbedTLS) no usa el heap de Python sino el del sistema (ESP-IDF): lo que
    importa para HTTPS es 'idf_bloque', el bloque libre más grande de ese heap."""
    try:
        connected = wlan.isconnected()
        ip = wlan.ifconfig()[0] if connected else "-"
    except OSError:
        connected, ip = False, "-"
    line = "[diag] wifi=%s red=%s ip=%s py_libre=%d" % (
        "conectado" if connected else "DESCONECTADO", current_ssid() or "-", ip, gc.mem_free())
    try:
        import esp32
        heaps = esp32.idf_heap_info(esp32.HEAP_DATA)   # [(total, libre, bloque_mayor, minimo), ...]
        line += " idf_libre=%d idf_bloque=%d" % (sum(h[1] for h in heaps), max(h[2] for h in heaps))
    except Exception:
        pass
    print(line)


def _post_once(path, payload):
    r = None
    try:
        r = requests.post(C.API_BASE + path, data=payload, headers=HEADERS, timeout=10)
        status = r.status_code
        try:
            data = r.json()
        except Exception:
            data = {}
        return status, data
    finally:
        if r:
            r.close()


def post(path, body):
    """Devuelve (status, dict). status = None si hubo error de red.

    El handshake TLS (HTTPS) necesita un bloque grande y contiguo de RAM: con el
    heap fragmentado falla con ENOMEM aunque haya memoria libre en total. Por
    eso se libera memoria antes de cada petición y, si aun así falla por ENOMEM,
    se reintenta una vez después de otra recolección."""
    payload = json.dumps(body)
    for attempt in (1, 2):
        gc.collect()
        try:
            return _post_once(path, payload)
        except OSError as e:
            if attempt == 1 and e.args and e.args[0] == errno.ENOMEM:
                print("Sin memoria para HTTPS, reintentando")
                diag()
                continue
            print("Error de red en", path, ":", e)
            diag()
            return None, {}
        except Exception as e:
            print("Error de red en", path, ":", e)
            diag()
            return None, {}
        finally:
            hw.feed()
    return None, {}
