# Imágenes de la página main del Nextion (800x480), diseño v3:
# "1 Elige tu ciclo > 2 Escanea tu QR", tabs Lavado | Secado y 4 tarjetas por tab.
#
# Corre en la Mac (CPython + Pillow), no en el ESP32:
#     python3 esp32/design/make_main.py
# Escribe en esp32/design/assets/ (el número es el ID de imagen en el Editor):
#     0_main.png       fondo: encabezado, flecha entre pasos, panel QR, renglón de abajo
#     1_main_sel.png   tarjetas marcadas y panel QR resaltado (el ESP32 copia regiones con picq)
#     6_main_card.png  tarjetas sin marcar
#     7_icons.png      íconos de ciclo 48x48; renglón 0 sobre tarjeta normal, 1 sobre marcada
#     8_steps.png      los 2 pasos en sus 5 estados (pendiente, activo, pulso, listo, error)
#     9_tabs.png       tab encendido / apagado
# Los textos (pasos, tabs, tarjetas) los escribe el ESP32 encima: aquí sólo van las formas.
# Para ver el resultado con el firmware real: python3 esp32/design/simulate.py
#
# Las coordenadas y colores de aquí deben coincidir con esp32/nextion.py.

import os
import random

from PIL import Image, ImageDraw, ImageFont

W, H = 800, 480
S = 3                                  # se dibuja a 3x y se reduce: bordes suaves
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "assets")
FONTS = "/System/Library/Fonts/Supplemental/"

BG = "#f3f8fe"
WHITE = "#ffffff"
BLUE = "#1462d6"
BLUE_D = "#0b3a8f"
NAVY = "#0b2a6b"
DETAIL = "#4b6a96"
LINE = "#d3e3f5"
CARD_BORDER = "#d5e3f3"
CARD_SEL = "#e4f0ff"
PANEL = "#0f2f66"
PANEL_IN = "#1b4a90"
GLOW = "#5fb0ff"
GREEN = "#14833f"
GREEN_BG = "#e0f4ea"
SKIN = "#f2b48c"
CYAN = "#38bdf8"

# Estados de un paso: (fondo de la píldora, círculo, borde del círculo, texto)
STEP_STATES = [
    ("#d3e6fb", "#8fb3e3", WHITE, DETAIL),        # 0 pendiente
    (BLUE, BLUE, WHITE, WHITE),                   # 1 activo
    ("#3d8bff", "#3d8bff", "#bfe0ff", WHITE),     # 2 pulso (alterna con activo)
    ("#dcf3e6", "#16a34a", WHITE, "#0f6b34"),     # 3 listo
    ("#fde4e4", "#d92d20", WHITE, "#b42318"),     # 4 error
]
TABS_STATES = [(BLUE, WHITE), (WHITE, NAVY)]      # (fondo, texto): encendido, apagado

# Misma geometría que nextion.py
STEP_BOXES = [(16, 64), (418, 64)]
STEP_W, STEP_H = 366, 44
TABS = [(16, 116), (288, 116)]
TAB_W, TAB_H = 264, 40
CARDS = [(16, 164), (288, 164), (16, 292), (288, 292)]
CARD_W, CARD_H = 264, 122
PANEL_BOX = (564, 116, 220, 298)
CANCEL = (604, 428, 180, 44)
ICON = 48


def font(name, size):
    return ImageFont.truetype(FONTS + name, int(size * S))


def s(*v):
    return [int(round(x * S)) for x in v]


def box(x, y, w, h):
    return s(x, y, x + w, y + h)


def text_c(d, cx, cy, txt, f, fill):
    d.text((cx * S, cy * S), txt, font=f, fill=fill, anchor="mm")


def rgb565(hexcolor):
    r, g, b = (int(hexcolor[i:i + 2], 16) for i in (1, 3, 5))
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def shrink(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


# ---------- fondo ----------

def header(d):
    d.rectangle(box(0, 0, W, 54), fill=WHITE)
    d.rectangle(box(0, 54, W, 2), fill=LINE)
    # gota del logo
    d.ellipse(box(16, 18, 30, 30), fill=BLUE)
    d.polygon(s(18, 28, 31, 4, 44, 28), fill=BLUE)
    d.ellipse(box(23, 29, 11, 11), fill="#7cc0ff")
    d.text((52 * S, 2 * S), "GMO", font=font("Arial Rounded Bold.ttf", 34), fill=BLUE)
    f = font("Arial Bold.ttf", 11)
    x = 54
    for ch in "LAVANDERÍA":
        d.text((x * S, 38 * S), ch, font=f, fill=NAVY)
        x += f.getlength(ch) / S + 2.6
    # Disponible
    d.rounded_rectangle(box(642, 10, 142, 36), radius=18 * S, fill=GREEN_BG, outline="#bfe6d3", width=S)
    text_c(d, 698, 28, "Disponible", font("Arial Rounded Bold.ttf", 17), GREEN)
    d.ellipse(box(752, 16, 24, 24), fill="#16a34a")
    d.line(s(758, 28, 762, 33, 770, 22), fill=WHITE, width=3 * S, joint="curve")


def chevron(d):
    d.line(s(394, 76, 404, 86, 394, 96), fill="#7a9cc8", width=4 * S, joint="curve")


def card(d, i, on):
    x, y = CARDS[i]
    if on:
        d.rounded_rectangle(box(x, y, CARD_W, CARD_H), radius=12 * S, fill=CARD_SEL, outline=BLUE, width=4 * S)
    else:
        d.rounded_rectangle(box(x, y, CARD_W, CARD_H), radius=12 * S, fill=WHITE, outline=CARD_BORDER, width=2 * S)


def qr_modules(d, x, y, size):
    n = 21
    m = size / n
    rnd = random.Random(7)
    cells = [[rnd.random() < 0.5 for _ in range(n)] for _ in range(n)]
    for fx, fy in ((0, 0), (n - 7, 0), (0, n - 7)):
        for r in range(-1, 8):
            for c in range(-1, 8):
                if 0 <= fy + r < n and 0 <= fx + c < n:
                    inside = 0 <= r < 7 and 0 <= c < 7
                    edge = r in (0, 6) or c in (0, 6)
                    core = 2 <= r <= 4 and 2 <= c <= 4
                    cells[fy + r][fx + c] = inside and (edge or core)
    for r in range(n):
        for c in range(n):
            if cells[r][c]:
                d.rectangle(s(x + c * m, y + r * m, x + (c + 1) * m, y + (r + 1) * m), fill="#111827")


def panel(d, glow):
    x, y, w, h = PANEL_BOX
    d.rounded_rectangle(box(x, y, w, h), radius=16 * S, fill=PANEL,
                        outline=GLOW if glow else PANEL, width=4 * S)
    cx = x + w / 2
    text_c(d, cx, y + 26, "Lector de QR", font("Arial Rounded Bold.ttf", 22), WHITE)
    # visor con esquinas
    fx, fy, fs = cx - 78, y + 48, 156
    d.rounded_rectangle(box(fx + 8, fy + 8, fs - 16, fs - 16), radius=10 * S, fill=PANEL_IN)
    k = 26
    for (ax, ay, dx, dy) in ((fx, fy, 1, 1), (fx + fs, fy, -1, 1), (fx, fy + fs, 1, -1), (fx + fs, fy + fs, -1, -1)):
        d.line(s(ax, ay + dy * k, ax, ay, ax + dx * k, ay), fill=WHITE, width=5 * S, joint="curve")
    # celular con QR, sostenido por una mano
    px, py, pw, ph = cx - 30, fy + 22, 60, 106
    d.ellipse(box(px - 26, py + 64, 62, 70), fill=SKIN)                 # palma
    d.rounded_rectangle(box(px, py, pw, ph), radius=10 * S, fill="#1f2937")
    d.rounded_rectangle(box(px + 5, py + 8, pw - 10, ph - 16), radius=5 * S, fill=WHITE)
    qr_modules(d, px + 9, py + 32, pw - 18)
    for i, fy2 in enumerate((py + 40, py + 54, py + 68)):                # dedos
        d.rounded_rectangle(box(px + pw - 6, fy2, 18 - i * 2, 11), radius=5 * S, fill=SKIN)
    d.rounded_rectangle(box(px - 10, py + 58, 22, 13), radius=6 * S, fill=SKIN)   # pulgar
    for (a, b) in (((px + pw + 18, py + 12), (px + pw + 28, py + 2)),
                   ((px + pw + 22, py + 26), (px + pw + 36, py + 22)),
                   ((px + pw + 20, py + 40), (px + pw + 34, py + 44))):
        d.line(s(*a, *b), fill=CYAN, width=4 * S)
    f = font("Arial.ttf", 15)
    text_c(d, cx, y + 236, "Acerca el QR de tu", f, WHITE)
    text_c(d, cx, y + 256, "celular al lector", f, WHITE)


def footer(d):
    top = 420
    for i in range(H - top):
        t = i / (H - top)
        c = tuple(int(a + (b - a) * t) for a, b in ((0xdc, 0xae), (0xec, 0xd6), (0xfc, 0xf8)))
        d.rectangle(s(0, top + i, W, top + i + 1), fill=c)
    d.ellipse(box(16, 436, 28, 28), fill=BLUE)
    text_c(d, 30, 450, "i", font("Arial Rounded Bold.ttf", 18), WHITE)
    x, y, w, h = CANCEL
    d.rounded_rectangle(box(x, y, w, h), radius=22 * S, fill=WHITE, outline=BLUE, width=3 * S)
    hx, hy = x + 34, y + 22                                             # casita
    d.polygon(s(hx - 13, hy - 1, hx, hy - 13, hx + 13, hy - 1), fill=BLUE_D)
    d.rectangle(box(hx - 9, hy - 2, 18, 13), fill=BLUE_D)
    d.rectangle(box(hx - 3, hy + 4, 6, 7), fill=WHITE)
    text_c(d, x + 108, y + 22, "Cancelar", font("Arial Rounded Bold.ttf", 20), BLUE_D)


def background(cards_on=None):
    """cards_on: None = sin tarjetas (fondo), False = normales, True = marcadas."""
    img = Image.new("RGB", (W * S, H * S), BG)
    d = ImageDraw.Draw(img)
    header(d)
    chevron(d)
    if cards_on is not None:
        for i in range(len(CARDS)):
            card(d, i, cards_on)
    panel(d, glow=bool(cards_on))
    footer(d)
    return shrink(img, W, H)


# ---------- pasos y tabs ----------

def step_sprite():
    """2 pasos x 5 estados, uno debajo de otro: renglón = (paso - 1) * 5 + estado."""
    sheet = Image.new("RGB", (STEP_W, STEP_H * 10), BG)
    for n in (1, 2):
        for st, (pill, circle, ring, _) in enumerate(STEP_STATES):
            img = Image.new("RGB", (STEP_W * S, STEP_H * S), BG)
            d = ImageDraw.Draw(img)
            d.rounded_rectangle(box(18, 4, STEP_W - 18, 36), radius=18 * S, fill=pill)
            d.ellipse(box(1, 1, 42, 42), fill=circle, outline=ring, width=3 * S)
            if st == 3:
                d.line(s(12, 22, 19, 29, 31, 15), fill=WHITE, width=4 * S, joint="curve")
            else:
                text_c(d, 22, 22.5, "!" if st == 4 else str(n), font("Arial Rounded Bold.ttf", 22), WHITE)
            sheet.paste(shrink(img, STEP_W, STEP_H), (0, ((n - 1) * 5 + st) * STEP_H))
    return sheet


def tab_sprite():
    sheet = Image.new("RGB", (TAB_W, TAB_H * 2), BG)
    for row, (bg, _) in enumerate(TABS_STATES):
        img = Image.new("RGB", (TAB_W * S, TAB_H * S), BG)
        ImageDraw.Draw(img).rounded_rectangle(box(1, 1, TAB_W - 2, TAB_H - 2), radius=12 * S, fill=bg,
                                              outline=BLUE if row == 0 else LINE, width=2 * S)
        sheet.paste(shrink(img, TAB_W, TAB_H), (0, row * TAB_H))
    return sheet


# ---------- íconos (48x48) ----------

def washer(d, k, extra=None):
    d.rounded_rectangle(s(4 * k, 2 * k, 40 * k, 46 * k), radius=int(5 * k * S), fill="#eaf3ff", outline=BLUE, width=int(3 * k * S))
    d.rectangle(s(5.5 * k, 3.5 * k, 38.5 * k, 12 * k), fill="#cfe2fb")
    d.line(s(4 * k, 12 * k, 40 * k, 12 * k), fill=BLUE, width=int(2 * k * S))
    for cx in (28, 33):
        d.ellipse(s((cx - 1.6) * k, 6 * k, (cx + 1.6) * k, 9.2 * k), fill=BLUE_D)
    d.ellipse(s(10 * k, 16 * k, 34 * k, 40 * k), fill=WHITE, outline=BLUE_D, width=int(3 * k * S))
    d.chord(s(13 * k, 19 * k, 31 * k, 37 * k), 10, 170, fill="#3b8cf0")
    if extra == "shirt":
        d.polygon(s(30 * k, 30 * k, 35 * k, 27 * k, 41 * k, 27 * k, 46 * k, 30 * k, 44 * k, 35 * k,
                    42 * k, 34 * k, 42 * k, 46 * k, 34 * k, 46 * k, 34 * k, 34 * k, 32 * k, 35 * k),
                  fill=WHITE, outline=BLUE, width=int(2 * k * S))
    if extra == "stack":
        for i in range(3):
            yy = (30 + i * 5.5) * k
            d.rounded_rectangle(s(28 * k, yy, 47 * k, yy + 5 * k), radius=int(2.5 * k * S), fill="#8cc4ff", outline=BLUE, width=int(1.5 * k * S))


def blanket(d, k):
    for i, yy in enumerate((26, 16, 6)):
        d.rounded_rectangle(s(4 * k, yy * k, 44 * k, (yy + 14) * k), radius=int(7 * k * S),
                            fill=("#5aa9f5", "#7cbcf8", "#a3d1fb")[i], outline=BLUE, width=int(2 * k * S))
    d.line(s(14 * k, 9 * k, 34 * k, 9 * k), fill=WHITE, width=int(1.5 * k * S))


def dryer(d, k, heat):
    d.rounded_rectangle(s(6 * k, 2 * k, 42 * k, 46 * k), radius=int(5 * k * S), fill="#eaf3ff", outline=BLUE, width=int(3 * k * S))
    d.line(s(6 * k, 12 * k, 42 * k, 12 * k), fill=BLUE, width=int(2 * k * S))
    for cx in (30, 35):
        d.ellipse(s((cx - 1.6) * k, 6 * k, (cx + 1.6) * k, 9.2 * k), fill=BLUE_D)
    if heat:
        d.rounded_rectangle(s(12 * k, 17 * k, 36 * k, 41 * k), radius=int(4 * k * S), fill=WHITE, outline=BLUE_D, width=int(2.5 * k * S))
        for xx in (18, 24, 30):
            pts = []
            for j in range(9):
                yy = 22 + j * 2.2
                pts += [(xx + (1.6 if j % 2 else -1.6)) * k, yy * k]
            d.line(s(*pts), fill=BLUE, width=int(2 * k * S), joint="curve")
    else:
        d.ellipse(s(12 * k, 17 * k, 36 * k, 41 * k), fill=WHITE, outline=BLUE_D, width=int(3 * k * S))
        for a in (0, 120, 240):
            d.pieslice(s(16 * k, 21 * k, 32 * k, 37 * k), a, a + 50, fill=BLUE)
        d.ellipse(s(22 * k, 27 * k, 26 * k, 31 * k), fill=BLUE_D)


ICONS = [
    lambda d, k: washer(d, k),
    lambda d, k: washer(d, k, "shirt"),
    lambda d, k: washer(d, k, "stack"),
    lambda d, k: blanket(d, k),
    lambda d, k: dryer(d, k, heat=False),
    lambda d, k: dryer(d, k, heat=True),
]


def icon_sheet():
    k = 4                                   # dibujo a 4x de 48 px (y luego S)
    sheet = Image.new("RGB", (ICON * len(ICONS), ICON * 2), WHITE)
    for row, bg in enumerate((WHITE, CARD_SEL)):
        for i, draw in enumerate(ICONS):
            big = Image.new("RGB", (ICON * k * S, ICON * k * S), bg)
            draw(ImageDraw.Draw(big), k)
            sheet.paste(shrink(big, ICON, ICON), (i * ICON, row * ICON))
    return sheet


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in os.listdir(OUT):
        if name.endswith(".png"):
            os.remove(os.path.join(OUT, name))
    background().save(os.path.join(OUT, "0_main.png"))
    background(True).save(os.path.join(OUT, "1_main_sel.png"))
    background(False).save(os.path.join(OUT, "6_main_card.png"))
    icon_sheet().save(os.path.join(OUT, "7_icons.png"))
    step_sprite().save(os.path.join(OUT, "8_steps.png"))
    tab_sprite().save(os.path.join(OUT, "9_tabs.png"))
    # para copiar a nextion.py si cambian los colores
    print("STEP_COLORS =", [(rgb565(p), rgb565(t)) for p, _, _, t in STEP_STATES])
    print("TAB_COLORS =", [(rgb565(b), rgb565(t)) for b, t in TABS_STATES])


if __name__ == "__main__":
    main()
