# Controlador de lavadora/secadora: ESP32 + MicroPython 1.29 + Nextion (diseño v2).
#
# Flujo:
#   main     el cliente elige ciclo y escanea su QR  -> POST /laundryDevices/quote
#   confirm  "Hola, Juan · $40" (30 s)  -> OK -> POST /laundryDevices/authorize
#   nofunds  "te faltan $20" (20 s)     -> Volver
#   inuse    relé encendido, cuenta regresiva
#   msg      "Ciclo terminado" (15 s)   -> main
#
# Todos los textos con datos (nombre, saldo, ciclos, precios, nivel de agua)
# vienen del backend. config.py opcional:
#   TZ_OFFSET_HOURS = -7          hora local para "Termina 21:45" (Hermosillo)
#   APP_URL = "..."                se escribe en "sin saldo" si el QR no está en el fondo
#   SUPPORT_TEXT = "Soporte: WhatsApp ..."

import time
from machine import reset

import config as C
import hw
import net
import api
import screen
from nextion import money, RED_D

lcd = screen.lcd
CONFIRM_SECONDS = 30
NOFUNDS_SECONDS = 20
DONE_SECONDS = 15
START_WARNING_SECONDS = 5 * 60
TZ = getattr(C, "TZ_OFFSET_HOURS", -7)

state = "main"
deadline = None        # ticks_ms en que vence la página actual
last_tick = 0          # último refresco de contador (1 s)
pending = None         # {"qr", "cycle", "quote"} entre quote y authorize
run = None             # {"start", "end", "minutes"} mientras la máquina trabaja


def seconds_left():
    return max(0, time.ticks_diff(deadline, time.ticks_ms()) // 1000)


def go_main():
    global state, deadline, pending
    state, deadline, pending = "main", None, None
    screen.show_main()
    hw.flush_qr()


def detail_line(cycle):
    parts = [cycle["name"]]
    if cycle.get("description"):
        parts.append(cycle["description"])
    parts.append("%s min" % cycle["cycleMinutes"])
    return " · ".join(parts)


def show_nofunds(first_name, balance, price, missing):
    global state, deadline
    state = "nofunds"
    deadline = time.ticks_add(time.ticks_ms(), NOFUNDS_SECONDS * 1000)
    who = (first_name + ", te") if first_name else "Te"
    lcd.show_nofunds(screen.title, "%s faltan %s" % (who, money(missing)),
                     "Saldo: %s · Ciclo: %s" % (money(balance), money(price)),
                     getattr(C, "APP_URL", ""), "Volviendo en %d s" % NOFUNDS_SECONDS)


def show_error(head, sub=""):
    global state, deadline
    state = "done"
    deadline = time.ticks_add(time.ticks_ms(), 5000)
    lcd.show_msg(screen.title, head, sub, getattr(C, "SUPPORT_TEXT", ""), RED_D)
    hw.blink(6, 80)


# ---------- main: QR escaneado ----------
QR_ERRORS = {
    "qr_malformed": "QR no válido para las máquinas",
    "qr_invalid": "QR no válido para las máquinas",
    "qr_wrong_company": "Este QR es de otra sucursal",
    "client_not_found": "Cliente no encontrado",
    "choice_not_for_device": "Ciclo no disponible",
}


def on_qr(client_qr):
    global state, deadline, pending
    cycle = screen.selected()
    if not cycle:
        screen.message("Sin ciclos disponibles", RED_D)
        return
    screen.message("Consultando...")
    hw.led.on()
    status, data = api.quote(client_qr, cycle["productOptionChoiceId"])
    hw.led.off()

    if status != 200:
        reason = data.get("reason") or data.get("error") or ""
        text = QR_ERRORS.get(reason) or ("Sin conexión.\nIntenta de nuevo" if status is None else "Error: %s" % reason)
        screen.message(text, RED_D)
        hw.blink(3, 200)
        return

    pending = {"qr": client_qr, "cycle": cycle, "quote": data}
    if not data.get("enough"):
        show_nofunds(data.get("firstName"), data.get("availableBalance"), data.get("priceMXN"), data.get("missingMXN"))
        return

    state = "confirm"
    deadline = time.ticks_add(time.ticks_ms(), CONFIRM_SECONDS * 1000)
    hello = "Hola, %s" % data["firstName"] if data.get("firstName") else "Hola"
    lcd.show_confirm(screen.title, hello, "Saldo disponible: %s" % money(data.get("availableBalance")),
                     money(data.get("priceMXN")), detail_line(cycle), "Se cancela en %d s" % CONFIRM_SECONDS)


# ---------- confirm: OK ----------
def on_confirm():
    lcd.confirm_timeout("Procesando pago...")
    hw.led.on()
    result, data = api.authorize(pending["qr"], pending["cycle"]["productOptionChoiceId"])
    hw.led.off()
    if result == "ok":
        start_machine(int(data.get("cycleMinutes") or pending["cycle"]["cycleMinutes"] or C.DEFAULT_CYCLE_MINUTES),
                      data.get("balanceAfter"))
    elif result == "sin_saldo":
        show_nofunds(pending["quote"].get("firstName"), data.get("availableBalance"),
                     data.get("amountMXN"), data.get("missingMXN"))
    elif result == "sin_respuesta":
        show_error("Sin conexión", "No se hizo ningún cobro.\nIntenta de nuevo.")
    else:
        show_error("No se pudo cobrar", str(data.get("reason") or data.get("error") or result))


# ---------- inuse ----------
def clock_at(epoch):
    t = time.localtime(epoch + TZ * 3600)
    return "%02d:%02d" % (t[3], t[4]) if t[0] >= 2024 else ""   # sin NTP no hay hora


def start_machine(minutes, balance_after):
    global state, run, pending
    cycle = pending["cycle"]
    hw.relay_set(True)
    state, pending = "inuse", None
    now = time.ticks_ms()
    run = {"start": now, "end": time.ticks_add(now, minutes * 60_000), "minutes": minutes}
    ends = clock_at(time.time() + minutes * 60)
    step = ("Gira la perilla a: %s" % cycle["description"]) if cycle.get("description") else "Elige el ciclo en la máquina"
    lcd.show_inuse(screen.title, "Pago confirmado · Saldo restante: %s" % money(balance_after), step,
                   "Tienes 5 min para presionar INICIO", "%s · %s min" % (cycle["name"], minutes),
                   "%d:00" % minutes, ("Termina " + ends) if ends else "", 0)


def tick_inuse():
    global state, deadline, run
    now = time.ticks_ms()
    left_ms = time.ticks_diff(run["end"], now)
    if left_ms <= 0:
        hw.relay_set(False)
        run = None
        state = "done"
        deadline = time.ticks_add(now, DONE_SECONDS * 1000)
        lcd.show_msg(screen.title, "Ciclo terminado", "Retira tu ropa. ¡Gracias!", getattr(C, "SUPPORT_TEXT", ""))
        return
    elapsed = time.ticks_diff(now, run["start"]) // 1000
    total = run["minutes"] * 60
    left = left_ms // 1000
    warn = None
    if elapsed >= START_WARNING_SECONDS and not run.get("warned"):
        run["warned"] = True
        warn = "Ciclo en curso"
    lcd.update_timer("%d:%02d" % (left // 60, left % 60), elapsed * 100 // total, warn)


# ---------- servidor ----------
def do_heartbeat():
    net.ensure_wifi()
    data = api.heartbeat(state == "inuse")
    if data is not None:
        screen.set_cycles(data.get("cycles"), data.get("deviceName"))


def main():
    global last_tick
    hw.blink(1)
    lcd.show_msg(screen.title, "Iniciando...", "Conectando al servidor")
    if not net.wifi_connect():
        lcd.show_msg(screen.title, "Fuera de servicio", "Sin conexión. Reintentando...", "", RED_D)
    do_heartbeat()
    go_main()
    last_heartbeat = time.ticks_ms()

    while True:
        hw.feed()
        now = time.ticks_ms()

        if time.ticks_diff(now, last_heartbeat) >= C.HEARTBEAT_SECONDS * 1000:
            do_heartbeat()
            last_heartbeat = time.ticks_ms()

        ev = screen.poll()
        qr = hw.read_qr()

        if state == "main":
            if qr:
                on_qr(qr)
        elif state == "confirm":
            if ev == "OK":
                on_confirm()
            elif ev == "CANCEL" or seconds_left() == 0:
                go_main()
        elif state == "nofunds":
            if ev == "BACK" or seconds_left() == 0:
                go_main()
        elif state == "done":
            if seconds_left() == 0:
                go_main()

        # contadores, una vez por segundo
        if time.ticks_diff(now, last_tick) >= 1000:
            last_tick = now
            if state == "inuse":
                tick_inuse()
            elif state == "confirm":
                lcd.confirm_timeout("Se cancela en %d s" % seconds_left())
            elif state == "nofunds":
                lcd.nofunds_timeout("Volviendo en %d s" % seconds_left())

        if qr and state != "main":
            hw.flush_qr()      # fuera de main el QR no hace nada (nunca cobra dos veces)
        time.sleep_ms(20)


try:
    main()
except KeyboardInterrupt:
    hw.relay_set(False)
    print("Detenido")
except Exception as e:
    hw.relay_set(False)
    print("Error fatal:", e)
    time.sleep(5)
    reset()
