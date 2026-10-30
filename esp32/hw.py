# Hardware: watchdog, relé, LED y lector QR.

import time
from machine import Pin, UART, WDT

import config as C

# Reinicia el ESP32 si algo se cuelga más de 2 min (p. ej. un saludo TLS).
# Para pruebas en Thonny puedes comentar esta línea y usar: wdt = None
wdt = WDT(timeout=120000)


def feed():
    if wdt:
        wdt.feed()


# ---------- Relé y LED ----------
relay = Pin(C.RELAY_PIN, Pin.OUT)
led = Pin(C.LED_PIN, Pin.OUT)


def relay_set(on):
    relay.value(1 if on == C.RELAY_ACTIVE_HIGH else 0)


relay_set(False)   # al arrancar, la máquina siempre apagada


def blink(times, ms=120):
    for _ in range(times):
        led.on(); time.sleep_ms(ms)
        led.off(); time.sleep_ms(ms)


# ---------- Lector QR ----------
scanner = UART(C.SCANNER_UART, baudrate=C.SCANNER_BAUD,
               tx=C.SCANNER_TX, rx=C.SCANNER_RX, timeout=10)
_buffer = b""
_last_byte = 0
QR_IDLE_MS = 150    # sin bytes nuevos por este tiempo = código completo


def _take(raw):
    """bytes -> texto del QR, o None si es basura (respuestas del lector, ruido)."""
    try:
        text = raw.decode().strip()
    except UnicodeError:
        return None
    text = "".join(ch for ch in text if " " <= ch <= "~")   # sólo caracteres imprimibles
    return text or None


def read_qr():
    """Devuelve un QR completo (str) o None.

    Algunos lectores terminan cada código con \r o \n; otros (GM65/GM861 en modo
    serial, según su configuración) no mandan terminador. Por eso el código se da
    por completo con el salto de línea O cuando el lector deja de mandar bytes
    durante QR_IDLE_MS."""
    global _buffer, _last_byte
    now = time.ticks_ms()
    if scanner.any():
        chunk = scanner.read() or b""
        if chunk:
            print("[qr] llegaron", len(chunk), "bytes")
            _buffer += chunk
            _last_byte = now
    if not _buffer:
        return None

    for sep in (b"\r", b"\n"):
        if sep in _buffer:
            line, _, rest = _buffer.partition(sep)
            _buffer = rest.lstrip(b"\r\n")
            text = _take(line)
            if text:
                print("[qr] leído,", len(text), "caracteres")
                return text
            return None

    if time.ticks_diff(now, _last_byte) >= QR_IDLE_MS or len(_buffer) > 512:
        line, _buffer = _buffer, b""
        text = _take(line)
        if text:
            print("[qr] leído sin terminador,", len(text), "caracteres")
        return text
    return None


def flush_qr():
    """Descarta lecturas que llegaron mientras esperábamos al servidor."""
    global _buffer
    _buffer = b""
    while scanner.any():
        scanner.read()
