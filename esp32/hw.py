# Hardware: watchdog, relé, LED y lector QR.

import time
from machine import Pin, UART, WDT

import config as C

# Reinicia el ESP32 si algo se cuelga más de 2 min (p. ej. un saludo TLS).
# Para pruebas en Thonny puedes cambiarlo por: wdt = None
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


def read_qr():
    """Devuelve un QR completo (str) o None. Los lectores terminan con \\r o \\n."""
    global _buffer
    if scanner.any():
        _buffer += scanner.read() or b""
        for sep in (b"\r", b"\n"):
            if sep in _buffer:
                line, _, rest = _buffer.partition(sep)
                _buffer = rest.lstrip(b"\r\n")
                try:
                    text = line.decode().strip()
                except UnicodeError:
                    text = ""      # ruido en el UART: se ignora
                if text:
                    return text
        if len(_buffer) > 1024:   # basura sin fin de línea
            _buffer = b""
    return None


def flush_qr():
    """Descarta lecturas que llegaron mientras esperábamos al servidor."""
    global _buffer
    _buffer = b""
    while scanner.any():
        scanner.read()
