# Controlador de lavadora/secadora: ESP32 + MicroPython 1.29
# Flujo: el cliente elige ciclo en la pantalla -> escanea su QR fijo ->
# POST /laundryDevices/authorize -> enciende el relé cycleMinutes.

import time
from machine import reset

import config as C
import hw
import net
import api
import screen

running_until = None          # ticks_ms en que termina el ciclo, o None


def handle_scan(client_qr):
    global running_until
    if running_until is not None:
        screen.message("Máquina en uso")
        hw.blink(2)
        hw.flush_qr()
        return

    cycle = screen.selected()
    if not cycle:
        screen.message("Sin ciclos disponibles")
        hw.blink(6, 80)
        hw.flush_qr()
        return

    screen.message("Cobrando {} (${})...".format(cycle["name"], cycle["priceMXN"]))
    hw.led.on()
    result, data = api.authorize(client_qr, cycle["productOptionChoiceId"])
    hw.led.off()

    if result == "ok":
        minutes = int(data.get("cycleMinutes") or cycle["cycleMinutes"] or C.DEFAULT_CYCLE_MINUTES)
        screen.message("Listo: {} min. Saldo ${}".format(minutes, data.get("balanceAfter")))
        hw.relay_set(True)
        running_until = time.ticks_add(time.ticks_ms(), minutes * 60_000)
    elif result == "sin_saldo":
        screen.message("Saldo insuficiente")
        hw.blink(3, 300)
    else:
        screen.message("No autorizado: {}".format(data.get("reason") or data.get("error") or result))
        hw.blink(6, 80)
    hw.flush_qr()


def do_heartbeat():
    net.ensure_wifi()
    data = api.heartbeat(running_until is not None)
    if data is not None:
        screen.set_cycles(data.get("cycles"))


def main():
    global running_until
    hw.blink(1)
    net.wifi_connect()
    do_heartbeat()
    last_heartbeat = time.ticks_ms()

    while True:
        hw.feed()
        now = time.ticks_ms()

        # Fin del ciclo
        if running_until is not None and time.ticks_diff(now, running_until) >= 0:
            hw.relay_set(False)
            running_until = None
            screen.message("Ciclo terminado")

        # Heartbeat periódico (también actualiza ciclos y precios)
        if time.ticks_diff(now, last_heartbeat) >= C.HEARTBEAT_SECONDS * 1000:
            do_heartbeat()
            last_heartbeat = time.ticks_ms()

        # Selección de ciclo y lecturas de QR
        screen.poll()
        qr = hw.read_qr()
        if qr:
            handle_scan(qr)

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
