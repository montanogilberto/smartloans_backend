# Pantalla de selección de ciclo: Nextion GMO, diseño v2 (página main).
#
# Todo lo que se muestra viene del heartbeat del backend:
#   deviceName            -> título ("LAVADORA 1")
#   groups                -> tabs de una máquina combo ("Lavado", "Secado")
#   cycles[].name/priceMXN/cycleMinutes/productId
#   cycles[].description  -> línea de detalle ("Agua baja"); se edita en el POS
#
# Al iniciar (y con cada nuevo cliente) no hay ciclo marcado: el cliente toca
# uno antes de escanear. Cambiar de tab también quita la selección.
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
_cycles = []       # todos los ciclos del heartbeat
_groups = []       # [{productId, label}] = tabs; uno solo = sin tabs
_tab = 0
_index = None      # índice dentro del tab activo; None = ninguno marcado
_dirty = False     # hay cambios del servidor sin dibujar (llegaron fuera de main)


def _card(c):
    return {
        "name": c["name"],
        "detail": c.get("description") or "",
        "minutes": "%s min" % c["cycleMinutes"],
        "price": money(c["priceMXN"]),
    }


def _key(c):
    return (c["productOptionChoiceId"], c["name"], c["priceMXN"], c["cycleMinutes"],
            c.get("description"), c.get("productId"), c.get("groupLabel"))


def _visible():
    """Ciclos del tab activo (todos si no hay tabs), máximo 4."""
    if len(_groups) > 1:
        pid = _groups[_tab]["productId"]
        return [c for c in _cycles if c.get("productId") == pid][:4]
    return _cycles[:4]


def set_cycles(cycles, device_name=None, groups=None):
    """Datos del heartbeat. Sólo redibuja si algo cambió, y nunca saca al cliente
    de otra página (confirm, inuse...): se dibuja al volver a main."""
    global _cycles, _groups, _tab, _index, title, _dirty
    new_title = str(device_name).upper() if device_name else title
    new = list(cycles or [])
    new_groups = list(groups or [])
    if ([_key(c) for c in new] == [_key(c) for c in _cycles] and new_groups == _groups
            and new_title == title and not _dirty):
        return
    current = selected()
    _cycles, _groups, title = new, new_groups, new_title
    if _tab >= max(len(_groups), 1):
        _tab = 0
    ids = [c["productOptionChoiceId"] for c in _visible()]
    _index = ids.index(current["productOptionChoiceId"]) if current and current["productOptionChoiceId"] in ids else None
    if lcd.page in (None, "main"):
        show_main()
    else:
        _dirty = True


def show_main(clear=False):
    """Dibuja la página main completa (también sirve para regresar a ella).
    clear=True quita la selección y vuelve al primer tab: el siguiente cliente
    empieza sin ciclo marcado."""
    global _dirty, _index, _tab
    _dirty = False
    if clear:
        _index, _tab = None, 0
    lcd.show_main(title, [_card(c) for c in _visible()], [g["label"] for g in _groups], _tab)
    _show()


def selected():
    """El ciclo marcado, o None si el cliente aún no toca ninguno."""
    vis = _visible()
    return vis[_index] if _index is not None and _index < len(vis) else None


def has_cycles():
    return bool(_cycles)


def poll():
    """Llamar en cada vuelta del bucle. Devuelve el evento de la pantalla (o None);
    los toques de ciclo y de tab ya se aplican aquí."""
    global _index, _tab
    ev = lcd.poll()
    if not ev or lcd.page != "main":
        return ev
    if ev.startswith("SEL"):
        i = int(ev[3:])
        if i < len(_visible()) and i != _index:
            _index = i
            _show()
    elif ev.startswith("TAB"):
        i = int(ev[3:])
        if i < len(_groups) and i != _tab:
            _tab, _index = i, None
            lcd.draw_tabs(_tab)
            lcd.show_cards([_card(c) for c in _visible()])
            _show()
    return ev


def message(text, pco=NAVY):
    """Mensaje corto en el panel inferior de la página main."""
    print("[pantalla]", text)
    if lcd.page == "main":
        lcd.status(str(text)[:45], pco)


def _show():
    c = selected()
    if not _cycles:
        lcd.select(None, "Sin ciclos", "")
        message("Revisa el productId del dispositivo")
        return
    if not c:
        lcd.select(None, "Elige tu ciclo", "")
        lcd.status("Toca un ciclo y\nluego escanea tu QR")
        return
    lcd.select(_index, "%s · %s min" % (c["name"], c["cycleMinutes"]), money(c["priceMXN"]))
    lcd.status("Escanea tu QR\npara continuar")
