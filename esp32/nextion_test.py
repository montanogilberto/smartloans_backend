# Prueba de las 5 páginas del diseño v2, sin backend.
# Ejecútalo en Thonny (NO lo guardes como main.py). Toca la pantalla para avanzar.

import time
from nextion import Nextion, RED_D

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
    {"name": "Básico", "detail": "Agua baja", "minutes": "45 min", "price": "$40"},
    {"name": "Medio", "detail": "Agua media", "minutes": "45 min", "price": "$50"},
    {"name": "Carga Alta", "detail": "Agua alta", "minutes": "45 min", "price": "$70"},
    {"name": "Colcha Grandes", "detail": "Agua máxima", "minutes": "45 min", "price": "$100"},
]

print("1) main: toca un ciclo")
lcd.show_main(T, cards)
lcd.select(0, "Básico · 45 min", "$40")
lcd.status("Escanea tu QR\npara continuar")
ev = wait(("SEL",))
if ev:
    i = int(ev[3:])
    lcd.select(i, "%s · 45 min" % cards[i]["name"], cards[i]["price"])
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
