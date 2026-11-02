# Vista previa de la página main SIN la pantalla: corre el screen.py real en la Mac con
# un UART falso y dibuja los comandos que mandaría al Nextion sobre las imágenes de assets/.
#     python3 esp32/design/make_main.py && python3 esp32/design/simulate.py
# Escribe esp32/design/preview/*.png, un PNG por momento del flujo. Las fuentes son Arial
# del sistema, parecidas a las del Editor (r16, r18, b24, b36...), no idénticas.

import os
import re
import sys
import time
import types

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ESP = os.path.dirname(HERE)
OUT = os.path.join(HERE, "preview")
FONTS = "/System/Library/Fonts/Supplemental/"
FONT_IDS = {0: ("Arial.ttf", 14), 1: ("Arial.ttf", 16), 2: ("Arial Bold.ttf", 21), 3: ("Arial Bold.ttf", 32),
            4: ("Arial Bold.ttf", 27), 5: ("Arial Bold.ttf", 64)}

sent = []
clock = [0]


class UART:
    def __init__(self, *a, **k):
        self.inbox = b""

    def write(self, b):
        sent.append(b)

    def any(self):
        return len(self.inbox)

    def read(self):
        b, self.inbox = self.inbox, b""
        return b


# Lo que MicroPython trae y CPython no
sys.modules["machine"] = types.SimpleNamespace(UART=UART)
sys.modules["config"] = types.SimpleNamespace(MACHINE_NAME="Lavadora 1")
time.ticks_ms = lambda: clock[0]
time.ticks_add = lambda a, b: a + b
time.ticks_diff = lambda a, b: a - b
sys.path.insert(0, ESP)
import screen  # noqa: E402

pics = {}
for name in os.listdir(os.path.join(HERE, "assets")):
    pics[int(name.split("_")[0])] = Image.open(os.path.join(HERE, "assets", name)).convert("RGB")


def c565(v):
    return (((v >> 11) & 31) * 255 // 31, ((v >> 5) & 63) * 255 // 63, (v & 31) * 255 // 31)


def render(path):
    img = Image.new("RGB", (800, 480), "black")
    d = ImageDraw.Draw(img)
    for raw in sent:
        s = raw[:-3].decode()
        if s.startswith("pic "):
            x, y, p = map(int, s[4:].split(","))
            img.paste(pics[p], (x, y))
        elif s.startswith("picq "):
            x, y, w, h, p = map(int, s[5:].split(","))
            img.paste(pics[p].crop((x, y, x + w, y + h)), (x, y))
        elif s.startswith("xpic "):
            x, y, w, h, x0, y0, p = map(int, s[5:].split(","))
            img.paste(pics[p].crop((x0, y0, x0 + w, y0 + h)), (x, y))
        elif s.startswith("fill "):
            x, y, w, h, c = map(int, s[5:].split(","))
            d.rectangle((x, y, x + w - 1, y + h - 1), fill=c565(c))
        elif s.startswith("xstr "):
            m = re.match(r'xstr (\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),"(.*)"$', s)
            x, y, w, h, f, pco, bco, xc, yc, sta = map(int, m.groups()[:10])
            txt = m.group(11).replace("\\r", "\n")
            if sta == 0:
                img.paste(pics[bco].crop((x, y, x + w, y + h)), (x, y))
            else:
                d.rectangle((x, y, x + w - 1, y + h - 1), fill=c565(bco))
            font = ImageFont.truetype(FONTS + FONT_IDS[f][0], FONT_IDS[f][1])
            _, _, tw, th = d.multiline_textbbox((0, 0), txt, font=font)
            if tw > w:
                print("  ¡no cabe! %r: %d px > %d" % (txt, tw, w))
            tx = x if xc == 0 else (x + (w - tw) / 2 if xc == 1 else x + w - tw)
            d.multiline_text((tx, y + (h - th) / 2 if yc else y), txt, font=font, fill=c565(pco))
    img.save(os.path.join(OUT, path))
    print("->", path)


def tap(x, y):
    screen.lcd.uart.inbox += bytes([0x67, x >> 8, x & 255, y >> 8, y & 255, 0]) + b"\xff\xff\xff"
    return screen.poll()


def later(ms):
    clock[0] += ms
    screen.poll()


def cyc(i, name, price, minutes, product, desc=None):
    return {"productOptionChoiceId": i, "name": name, "priceMXN": price, "cycleMinutes": minutes,
            "description": desc, "productId": product}


CYCLES = [
    cyc(1, "Basico", 40, 45, 1002, "Agua baja"), cyc(2, "Medio", 50, 45, 1002, "Agua media"),
    cyc(3, "Carga Alta", 70, 45, 1002, "Agua alta"), cyc(4, "Colcha Grandes", 100, 45, 1002, "Agua máxima"),
    cyc(5, "Secado", 60, 45, 1003), cyc(6, "Secado Medio", 70, 50, 1003),
    cyc(7, "Secado Grande", 80, 60, 1003), cyc(8, "Colchas Grandes", 100, 60, 1003),
]
GROUPS = [{"productId": 1002, "label": "Lavado"}, {"productId": 1003, "label": "Secado"}]


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in os.listdir(OUT):
        os.remove(os.path.join(OUT, name))
    screen.set_cycles(CYCLES, "Lavadora 1", GROUPS)
    render("1_elige.png")
    later(700)
    render("2_elige_pulso.png")
    tap(140, 220)                      # Básico
    render("3_escanea.png")
    screen.busy("Consultando tu saldo...")
    render("4_consultando.png")
    screen.error(2, "QR no válido")
    render("5_error_qr.png")
    later(4000)
    render("6_vuelve_a_escanea.png")
    tap(420, 136)                      # tab Secado
    tap(400, 350)                      # Colchas Grandes
    render("7_secado.png")
    tap(690, 450)                      # Cancelar
    screen.error(1, "Primero toca tu ciclo")
    render("8_sin_ciclo.png")
    screen.set_cycles(CYCLES[:4], "Lavadora 2", [GROUPS[0]])
    later(4000)
    render("9_solo_lavado.png")


if __name__ == "__main__":
    main()
