# Pantalla de selección de ciclo: Nextion NX8048P070 por UART.
#
# Misma interfaz que la versión provisional, así que main.py no cambia:
#   set_cycles(cycles), selected(), poll(), message(text)
#
# Requiere nextion.py en la placa y el diseño de NEXTION_DISENO.md cargado
# en la pantalla (componentes tTitle, b0..b3, tStatus, tTimer).

import config as C
from nextion import Nextion, COLOR_INFO

_lcd = Nextion(
    uart_id=getattr(C, "NEXTION_UART", 1),
    tx=getattr(C, "NEXTION_TX", 27),
    rx=getattr(C, "NEXTION_RX", 26),
    baud=getattr(C, "NEXTION_BAUD", 9600),
)
_cycles = []
_index = 0

_title = getattr(C, "MACHINE_NAME", "")
if _title:
    _lcd.set_title(_title)


def set_cycles(cycles):
    """cycles = [{productOptionChoiceId, name, priceMXN, cycleMinutes}] del heartbeat."""
    global _cycles, _index
    current = selected()
    new = list(cycles or [])
    if len(new) > _lcd.max:
        print("[pantalla] Aviso: hay %d ciclos, sólo caben %d" % (len(new), _lcd.max))
        new = new[: _lcd.max]

    # Si no cambió nada, no redibujar (el heartbeat llega cada minuto)
    if [c["productOptionChoiceId"] for c in new] == [c["productOptionChoiceId"] for c in _cycles] \
            and [(c["name"], c["priceMXN"], c["cycleMinutes"]) for c in new] \
            == [(c["name"], c["priceMXN"], c["cycleMinutes"]) for c in _cycles]:
        return

    _cycles = new
    ids = [c["productOptionChoiceId"] for c in _cycles]
    if current and current["productOptionChoiceId"] in ids:
        _index = ids.index(current["productOptionChoiceId"])
    else:
        _index = 0

    _lcd.show_cycles([(c["name"], c["priceMXN"], c["cycleMinutes"]) for c in _cycles])
    _show()


def selected():
    """El ciclo marcado, o None si aún no hay ciclos."""
    return _cycles[_index] if _cycles else None


def poll():
    """Llamar en cada vuelta del bucle: lee los toques de la pantalla."""
    global _index
    i = _lcd.poll()
    if i is not None and i < len(_cycles):
        _index = i
        _show()


def message(text, color=COLOR_INFO):
    print("[pantalla]", text)
    _lcd.set_status(str(text)[:80], color)


def _show():
    c = selected()
    if c:
        _lcd.select(_index)
        message("{}: ${} - {} min. Escanea tu QR".format(c["name"], c["priceMXN"], c["cycleMinutes"]))
    else:
        message("Sin ciclos: revisa el productId del dispositivo")
