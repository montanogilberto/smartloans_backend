# Prueba de las 5 páginas (main diseño v3), sin backend.
# Ejecútalo en Thonny (NO lo guardes como main.py). Toca la pantalla para avanzar.

import time
from nextion import Nextion, RED_D, STEP_PENDING, STEP_ACTIVE, STEP_DONE, STEP_ERROR

lcd = Nextion(uart_id=1, tx=27, rx=26, baud=9600)
T = "LAVADORA 01"


def wait(events, seconds=30):
    t = time.time()
    while time.time() - t < seconds:
        ev = lcd.poll()
        if ev:
            print("Evento:", ev)
            if ev in events or (ev.startswith("SEL") and "SEL" in events):
                return ev
        time.sleep_ms(20)
    return None


cards = [
    {"name": "Básico", "detail": "Agua baja · 45 min", "price": "$40", "icon": 0},
    {"name": "Medio", "detail": "Agua media · 45 min", "price": "$50", "icon": 1},
    {"name": "Carga Alta", "detail": "Agua alta · 45 min", "price": "$70", "icon": 2},
    {"name": "Colcha Grandes", "detail": "Agua máxima · 45 min", "price": "$100", "icon": 3},
]

print("1) main: toca un ciclo (Cancelar quita la selección)")
lcd.show_main(T, cards, ["Lavado", "Secado"], 0)
lcd.step(1, STEP_ACTIVE, "Elige tu ciclo")
lcd.step(2, STEP_PENDING, "Escanea tu QR")
lcd.status("Toca Lavado o Secado y luego tu ciclo")
ev = wait(("SEL",))
if ev:
    i = int(ev[3:])
    lcd.select(i)
    lcd.step(1, STEP_DONE, "%s · %s" % (cards[i]["name"], cards[i]["price"]))
    lcd.step(2, STEP_ACTIVE, "Escanea tu QR")
    lcd.qr_panel(True)
    time.sleep(2)
    lcd.step(2, STEP_ERROR, "QR no válido")
    if wait(("CANCEL",), 10):
        lcd.select(None)
        lcd.qr_panel(False)
        lcd.step(1, STEP_ACTIVE, "Elige tu ciclo")
        lcd.step(2, STEP_PENDING, "Escanea tu QR")
    time.sleep(2)

print("2) confirm: toca Confirmar o Cancelar")
lcd.show_confirm(T, "Hola, Juan", "Saldo disponible: $250", "$40",
                 "Básico · Agua baja · 45 min", "Se cancela en 30 s")
wait(("OK", "CANCEL"))

print("3) inuse (avanza solo)")
lcd.show_inuse(T, "Pago confirmado · Saldo restante: $210", "Gira la perilla a agua BAJA",
               "Tienes 5 min para presionar INICIO", "Básico · 45 min", "45:00", "Termina 21:45", 0)
for p in range(0, 101, 20):
    lcd.update_timer("%02d:00" % (45 - 45 * p // 100), p)
    time.sleep(1)

print("4) nofunds: toca Volver")
lcd.show_nofunds(T, "Juan, te faltan $20", "Saldo: $20 · Ciclo: $40",
                 "https://example.com", "Volviendo en 20 s")
wait(("BACK",))

print("5) msg")
lcd.show_msg(T, "Ciclo terminado", "Retira tu ropa. ¡Gracias!", "Soporte: WhatsApp")
time.sleep(3)
lcd.show_msg(T, "Fuera de servicio", "Sin conexión. Reintentando...", "", RED_D)
time.sleep(3)
print("Fin de la prueba")
