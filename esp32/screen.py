# Pantalla de selección de ciclo: Nextion GMO, diseño v2 (página main).
#
# Todo lo que se muestra viene del heartbeat del backend:
#   deviceName            -> título ("LAVADORA 1")
#   cycles[].name/priceMXN/cycleMinutes
#   cycles[].description  -> línea de detalle ("Agua baja"); se edita en el POS
#
# Las otras páginas (confirm, inuse, nofunds, msg) las maneja main.py con screen.lcd.
# config.py: MACHINE_NAME sólo se usa si el servidor todavía no mandó deviceName.

import config as C
from nextion import Nextion, NAVY, money

lcd = Nextion(
    uart_id=getattr(C, "NEXTION_UART", 1),
    tx=getattr(C, "NEXTION_TX", 27),
    rx=getattr(C, "NEXTION_RX", 26),
    baud=getattr(C, "NEXTION_BAUD", 9600),
)
title = str(getattr(C, "MACHINE_NAME", "")).upper()
_cycles = []
_index = 0
_dirty = False     # hay cambios del servidor sin dibujar (llegaron fuera de main)


def _card(c):
    return {
        "name": c["name"],
        "detail": c.get("description") or "",
        "minutes": "%s min" % c["cycleMinutes"],
        "price": money(c["priceMXN"]),
    }


def _key(c):
    return (c["productOptionChoiceId"], c["name"], c["priceMXN"], c["cycleMinutes"], c.get("description"))


def set_cycles(cycles, device_name=None):
    """Datos del heartbeat. Sólo redibuja si algo cambió, y nunca saca al cliente
    de otra página (confirm, inuse...): se dibuja al volver a main."""
    global _cycles, _index, title, _dirty
    new_title = str(device_name).upper() if device_name else title
    new = list(cycles or [])[:4]
    if [_key(c) for c in new] == [_key(c) for c in _cycles] and new_title == title and not _dirty:
        return
    current = selected()
    _cycles, title = new, new_title
    ids = [c["productOptionChoiceId"] for c in _cycles]
    _index = ids.index(current["productOptionChoiceId"]) if current and current["productOptionChoiceId"] in ids else 0
    if lcd.page in (None, "main"):
        show_main()
    else:
        _dirty = True


def show_main():
    """Dibuja la página main completa (también sirve para regresar a ella)."""
    global _dirty
    _dirty = False
    lcd.show_main(title, [_card(c) for c in _cycles])
    _show()


def selected():
    """El ciclo marcado, o None si aún no hay ciclos."""
    return _cycles[_index] if _cycles else None


def poll():
    """Llamar en cada vuelta del bucle. Devuelve el evento de la pantalla (o None);
    los toques de ciclo ya se aplican aquí."""
    global _index
    ev = lcd.poll()
    if ev and ev.startswith("SEL") and lcd.page == "main":
        i = int(ev[3:])
        if i < len(_cycles) and i != _index:
            _index = i
            _show()
    return ev


def message(text, pco=NAVY):
    """Mensaje corto en el panel inferior de la página main."""
    print("[pantalla]", text)
    if lcd.page == "main":
        lcd.status(str(text)[:45], pco)


def _show():
    c = selected()
    if not c:
        lcd.select(None, "Sin ciclos", "")
        message("Revisa el productId del dispositivo")
        return
    lcd.select(_index, "%s · %s min" % (c["name"], c["cycleMinutes"]), money(c["priceMXN"]))
    lcd.status("Escanea tu QR\npara continuar")
