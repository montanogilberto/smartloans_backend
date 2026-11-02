# Pantalla de selección de ciclo: Nextion GMO, diseño v3 (página main).
#
# Todo lo que se muestra viene del heartbeat del backend:
#   deviceName            -> título ("LAVADORA 1")
#   groups                -> tabs de una máquina combo ("Lavado", "Secado")
#   cycles[].name/priceMXN/cycleMinutes/productId
#   cycles[].description  -> línea de detalle ("Agua baja"); se edita en el POS
#
# Los pasos guían al cliente y cambian con lo que hace:
#   elige    "1 Elige tu ciclo" activo (pulsa)       "2 Escanea tu QR" pendiente
#   escanea  "1 ✓ Básico · $40" listo                "2 Escanea tu QR" activo (pulsa)
#   ocupado  "1 ✓ Básico · $40"                      "2 Consultando tu saldo..."
#   error    el paso que falló en rojo unos segundos, luego vuelve solo
# Al iniciar (y con cada nuevo cliente) no hay ciclo marcado. Cambiar de tab,
# Cancelar o tocar el paso 1 quitan la selección.
#
# Las otras páginas (confirm, inuse, nofunds, msg) las maneja main.py con screen.lcd.
# config.py: MACHINE_NAME sólo se usa si el servidor todavía no mandó deviceName.

import time

import config as C
from nextion import (Nextion, INK, RED_D, SLOTS, money,
                     STEP_PENDING, STEP_ACTIVE, STEP_PULSE, STEP_DONE, STEP_ERROR)

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

PULSE_MS = 700     # el paso activo alterna de tono para llamar la atención
ERROR_MS = 4000    # un error se queda en rojo este tiempo
_phase = "choose"  # choose | scan | busy | error
_busy_text = ""
_error = (2, "")   # (paso, texto)
_error_until = 0
_pulse = False
_pulse_at = 0
_panel_ready = False

# Íconos de esp32/design/make_main.py (columna de 7_icons.png)
ICON_WASH, ICON_WASH_MID, ICON_WASH_BIG, ICON_BLANKET, ICON_DRY, ICON_DRY_BIG = range(6)


def _group_label(c):
    label = c.get("groupLabel")
    if not label:
        for g in _groups:
            if g.get("productId") == c.get("productId"):
                label = g.get("label")
    return str(label or "")


def _icon(c):
    name = c["name"].lower()
    group = _group_label(c).lower()
    big = "grande" in name or "alta" in name
    if "colch" in name or "cobij" in name or "edred" in name:
        return ICON_BLANKET
    if "secad" in group or "secad" in name:
        return ICON_DRY_BIG if big else ICON_DRY
    if "medi" in name:
        return ICON_WASH_MID
    return ICON_WASH_BIG if big or "carga" in name else ICON_WASH


def _card(c):
    minutes = "%s min" % c["cycleMinutes"]
    return {
        "name": c["name"],
        "detail": "%s · %s" % (c["description"], minutes) if c.get("description") else minutes,
        "price": money(c["priceMXN"]),
        "icon": _icon(c),
    }


def _key(c):
    return (c["productOptionChoiceId"], c["name"], c["priceMXN"], c["cycleMinutes"],
            c.get("description"), c.get("productId"), c.get("groupLabel"))


def _visible():
    """Ciclos del tab activo (todos si no hay tabs), máximo SLOTS."""
    if len(_groups) > 1:
        pid = _groups[_tab]["productId"]
        return [c for c in _cycles if c.get("productId") == pid][:SLOTS]
    return _cycles[:SLOTS]


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
    global _dirty, _index, _tab, _phase, _panel_ready
    _dirty = False
    if clear:
        _index, _tab = None, 0
    _phase = "scan" if selected() else "choose"
    lcd.show_main(title, [_card(c) for c in _visible()], [g["label"] for g in _groups], _tab)
    lcd.select(_index)
    _panel_ready = False
    _redraw()


def selected():
    """El ciclo marcado, o None si el cliente aún no toca ninguno."""
    vis = _visible()
    return vis[_index] if _index is not None and _index < len(vis) else None


def has_cycles():
    return bool(_cycles)


def busy(text):
    """El servidor está trabajando (p. ej. consultando el saldo): se muestra en el paso 2
    antes de la llamada, que bloquea, para que nadie escanee dos veces."""
    global _phase, _busy_text
    _phase, _busy_text = "busy", text
    _redraw()


def error(step, text):
    """Error del paso 1 (falta elegir ciclo) o 2 (QR rechazado, sin conexión).
    El paso queda en rojo ERROR_MS y luego vuelve solo."""
    global _phase, _error, _error_until
    lines = str(text).split("\n")
    _phase = "error"
    _error = (step, lines[0])
    _error_until = time.ticks_add(time.ticks_ms(), ERROR_MS)
    _redraw()
    # el paso ya dice qué pasó; abajo va qué hacer
    hint = " ".join(lines[1:]) or ("Toca una tarjeta y luego escanea tu QR" if step == 1
                                   else "Intenta otra vez o pide ayuda en caja")
    message(hint, RED_D)


def poll():
    """Llamar en cada vuelta del bucle. Devuelve el evento de la pantalla (o None);
    los toques de ciclo, tab, paso 1 y Cancelar en main ya se aplican aquí,
    y aquí también pulsa el paso activo."""
    global _index, _tab, _phase
    ev = lcd.poll()
    if lcd.page != "main":
        return ev
    _tick()
    if not ev or _phase == "busy":
        return ev
    if ev.startswith("SEL"):
        i = int(ev[3:])
        if i < len(_visible()) and (i != _index or _phase == "error"):
            _index, _phase = i, "scan"
            lcd.select(_index)
            _redraw()
    elif ev.startswith("TAB"):
        i = int(ev[3:])
        if i < len(_groups) and i != _tab:
            _tab, _index, _phase = i, None, "choose"
            show_main()
    elif ev in ("CANCEL", "STEP1") and _index is not None:
        _index, _phase = None, "choose"
        lcd.select(None)
        _redraw()
    return ev


def message(text, pco=INK):
    """Mensaje en el renglón de abajo de la página main."""
    print("[pantalla]", text)
    if lcd.page == "main":
        lcd.status(str(text)[:90], pco)


def _chosen(c):
    return "%s · %s" % (c["name"], money(c["priceMXN"]))


def _tick():
    global _phase, _pulse, _pulse_at
    now = time.ticks_ms()
    if _phase == "error" and time.ticks_diff(now, _error_until) >= 0:
        _phase = "scan" if selected() else "choose"
        _redraw()
    elif _phase in ("choose", "scan") and _cycles and time.ticks_diff(now, _pulse_at) >= PULSE_MS:
        _pulse, _pulse_at = not _pulse, now
        state = STEP_PULSE if _pulse else STEP_ACTIVE
        if _phase == "choose":
            lcd.step(1, state, "Elige tu ciclo")
        else:
            lcd.step(2, state, "Escanea tu QR")


def _redraw():
    """Pasos, panel QR y renglón de abajo según la fase."""
    global _panel_ready, _pulse, _pulse_at
    c = selected()
    _pulse, _pulse_at = False, time.ticks_ms()
    if not _cycles:
        lcd.step(1, STEP_ERROR, "Sin ciclos")
        lcd.step(2, STEP_PENDING, "Escanea tu QR")
        foot = ("Revisa el productId del dispositivo", RED_D)
    elif _phase == "busy":
        lcd.step(1, STEP_DONE, _chosen(c) if c else "Elige tu ciclo")
        lcd.step(2, STEP_ACTIVE, _busy_text)
        foot = ("Espera un momento, no vuelvas a escanear", INK)
    elif _phase == "error":
        n, text = _error
        if n == 1:
            lcd.step(1, STEP_ERROR, text)
            lcd.step(2, STEP_PENDING, "Escanea tu QR")
        else:
            lcd.step(1, STEP_DONE if c else STEP_ACTIVE, _chosen(c) if c else "Elige tu ciclo")
            lcd.step(2, STEP_ERROR, text)
        foot = None          # error() ya escribió en rojo qué hacer
    elif c:
        lcd.step(1, STEP_DONE, _chosen(c))
        lcd.step(2, STEP_ACTIVE, "Escanea tu QR")
        foot = (_card(c)["detail"] + " · Se cobra de tu saldo al confirmar", INK)
    else:
        lcd.step(1, STEP_ACTIVE, "Elige tu ciclo")
        lcd.step(2, STEP_PENDING, "Escanea tu QR")
        foot = ("Toca Lavado o Secado y luego tu ciclo" if len(_groups) > 1 else "Toca el ciclo que quieres", INK)
    ready = bool(c) and _phase in ("scan", "busy")
    if ready != _panel_ready:
        lcd.qr_panel(ready)
        _panel_ready = ready
    if foot:
        message(*foot)
