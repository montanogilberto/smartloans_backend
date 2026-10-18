# Pantalla de selección de ciclo.
#
# VERSIÓN PROVISIONAL: mientras no conectemos la pantalla real, el ciclo se
# escoge con el botón BOOT de la placa (GPIO 0) y se muestra en la consola de
# Thonny. Cada pulsación pasa al siguiente ciclo; el ciclo marcado es el que se
# cobra al escanear el QR.
#
# Cuando tengamos la pantalla (táctil o LCD + botones), sólo se reemplaza este
# archivo: main.py usa set_cycles(), selected() y message().

import time
from machine import Pin

_button = Pin(0, Pin.IN, Pin.PULL_UP)
_cycles = []
_index = 0
_last_press = 0


def set_cycles(cycles):
    """cycles = [{productOptionChoiceId, name, priceMXN, cycleMinutes}] del heartbeat."""
    global _cycles, _index
    current = selected()
    _cycles = cycles or []
    ids = [c["productOptionChoiceId"] for c in _cycles]
    _index = ids.index(current["productOptionChoiceId"]) if current and current["productOptionChoiceId"] in ids else 0
    _show()


def selected():
    """El ciclo marcado, o None si aún no hay ciclos."""
    return _cycles[_index] if _cycles else None


def poll():
    """Llamar en cada vuelta del bucle: avanza de ciclo con el botón."""
    global _index, _last_press
    if _cycles and _button.value() == 0 and time.ticks_diff(time.ticks_ms(), _last_press) > 300:
        _last_press = time.ticks_ms()
        _index = (_index + 1) % len(_cycles)
        _show()


def message(text):
    print("[pantalla]", text)


def _show():
    c = selected()
    if c:
        message("Ciclo: {} — ${} — {} min. Escanea tu QR".format(c["name"], c["priceMXN"], c["cycleMinutes"]))
    else:
        message("Sin ciclos: revisa productId del dispositivo")
