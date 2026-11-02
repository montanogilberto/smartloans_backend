# Driver de la pantalla Nextion GMO (main diseño v3, otras páginas v2) para MicroPython.
#
# MODO DIBUJO: el proyecto del Editor sólo tiene fuentes, imágenes y 5 páginas
# con su fondo (sta=image), sin componentes. Todo el texto lo dibuja el ESP32
# con xstr, las tarjetas con picq, los íconos, pasos y tabs con xpic (recortes de
# una imagen con todas las variantes) y la barra con fill. Los toques llegan como
# coordenadas (sendxy=1 en el Preinitialize de main) y aquí se traducen a
# eventos: SEL0..SEL3, TAB0/TAB1, STEP1, OK, CANCEL, BACK.
#
# Para mover un texto o cambiar un color, edita las tablas de abajo: no hace
# falta volver a compilar ni cargar el .tft. Las imágenes de main salen de
# esp32/design/make_main.py, con la misma geometría y colores que aquí.
#
# Páginas e imágenes (deben coincidir con el proyecto del Editor):
#   main=0 (main_sel=1, main_card=6, icons=7, steps=8, tabs=9), confirm=2, inuse=3, nofunds=4, msg=5
# Fuentes (IDs del Editor):
#   0 r16, 1 r18, 2 b24, 3 b36, 4 b30, 5 b72

from machine import UART

END = b"\xff\xff\xff"

# Colores en formato Nextion (RGB565), iguales a los del diseño
NAVY = 4425
SEC = 23375
GREEN = 7146
GREEN_D = 4936
AMBER_D = 39616
RED_D = 45315
WHITE = 65535
BAR_BG = 57117
# main v3 (los mismos colores que esp32/design/make_main.py)
INK = 2381           # #0b2a6b nombre del ciclo, textos
PRICE = 2513         # #0b3a8f precio
DETAIL = 19282       # #4b6a96 detalle, nombre de la máquina

LEFT, CENTER, RIGHT = 0, 1, 2
SLOTS = 4            # tarjetas por tab

PAGES = {"main": 0, "confirm": 2, "inuse": 3, "nofunds": 4, "msg": 5}
PIC_MAIN_SEL = 1     # tarjetas marcadas y panel QR resaltado
PIC_MAIN_CARD = 6    # tarjetas sin marcar
PIC_ICONS = 7        # íconos 48x48: renglón 0 sobre tarjeta normal, renglón 1 sobre marcada
PIC_STEPS = 8        # renglón (paso - 1) * 5 + estado
PIC_TABS = 9         # renglón 0 encendido, 1 apagado

# Cajas de texto: (x, y, w, h, fuente, alineación, color)
TITLE = (200, 16, 260, 26, 1, LEFT, SEC)

# Pasos "1 Elige tu ciclo > 2 Escanea tu QR". El texto va en la parte plana de la
# píldora con fondo de color sólido, así cambia sin redibujar la forma.
STEP_PENDING, STEP_ACTIVE, STEP_PULSE, STEP_DONE, STEP_ERROR = range(5)
STEPS = [(16, 64), (418, 64)]
STEP_W, STEP_H = 366, 44
STEP_TEXT = (50, 9, 294, 26, 2, CENTER)
STEP_COLORS = [(55103, 19282), (4890, 65535), (15455, 65535), (57244, 2886), (65340, 45315)]  # (píldora, texto)

# Tabs del servicio (Lavado | Secado) en una máquina combo
TABS = [(16, 116), (288, 116)]
TAB_W, TAB_H = 264, 40
TAB_TEXT = (16, 6, 232, 28, 2, CENTER)
TAB_COLORS = [(4890, 65535), (65535, 2381)]     # (fondo, texto): encendido, apagado

# Rejilla de 2x2 tarjetas (esquina de cada una)
CARDS = [(16, 164), (288, 164), (16, 292), (288, 292)]
CARD_W, CARD_H = 264, 122
# dentro de la tarjeta, relativo a su esquina
CARD_ICON = (14, 37)
ICON = 48
CARD_NAME = (74, 12, 182, 28, 2, LEFT)
CARD_DETAIL = (74, 42, 182, 22, 0, LEFT)
CARD_PRICE = (74, 66, 182, 44, 3, LEFT)

QR_PANEL = (564, 116, 220, 298)   # se resalta (main_sel) mientras el paso 2 está activo

MAIN = {
    "status": (52, 428, 540, 44, 1, LEFT, INK),   # renglón de abajo, junto a la (i)
}
MAIN_CANCEL = (604, 428, 180, 44)
CONFIRM = {
    "hello": (170, 108, 460, 44, 4, CENTER, NAVY),
    "bal": (170, 152, 460, 28, 1, CENTER, SEC),
    "total": (170, 226, 460, 80, 5, CENTER, NAVY),
    "detail": (170, 308, 460, 28, 1, CENTER, NAVY),
    "timeout": (170, 338, 460, 26, 0, CENTER, SEC),
}
INUSE = {
    "paid": (84, 102, 676, 40, 2, LEFT, GREEN_D),
    "step1": (92, 218, 316, 36, 1, LEFT, NAVY),
    "warn": (60, 344, 330, 40, 0, LEFT, AMBER_D),
    "cycle": (48, 404, 352, 28, 0, LEFT, SEC),
    "timer": (452, 212, 304, 88, 5, CENTER, NAVY),
    "ends": (452, 346, 304, 28, 1, CENTER, SEC),
}
BAR = (468, 318, 272, 14)
NOFUNDS = {
    "head": (28, 104, 470, 44, 4, LEFT, NAVY),
    "detail": (28, 150, 470, 30, 1, LEFT, SEC),
    "timeout": (236, 404, 264, 32, 0, LEFT, SEC),
    "url": (546, 150, 200, 160, 0, CENTER, SEC),   # sólo si el QR no está en el fondo
}
MSG = {
    "head": (170, 166, 460, 48, 4, CENTER, NAVY),
    "sub": (170, 222, 460, 64, 1, CENTER, SEC),
    "foot": (28, 420, 744, 32, 0, CENTER, SEC),
}

# Botones de confirm (mismas zonas que los toques)
BTN_CANCEL = (150, 388, 180, 64)
BTN_OK = (346, 388, 304, 64)
BTN_FONT = 2

# Zonas táctiles por página: (x, y, w, h, evento)
TOUCH = {
    "main": [(x, y, CARD_W, CARD_H, "SEL%d" % i) for i, (x, y) in enumerate(CARDS)]
            + [(x, y, TAB_W, TAB_H, "TAB%d" % i) for i, (x, y) in enumerate(TABS)]
            + [STEPS[0] + (STEP_W, STEP_H, "STEP1"), MAIN_CANCEL + ("CANCEL",)],
    "confirm": [BTN_CANCEL + ("CANCEL",), BTN_OK + ("OK",)],
    "nofunds": [(28, 388, 192, 64, "BACK")],
}


class Nextion:
    def __init__(self, uart_id=1, tx=27, rx=26, baud=9600):
        self.uart = UART(uart_id, baudrate=baud, tx=tx, rx=rx, timeout=10)
        self._buf = b""
        self.page = None
        self.used = 0          # tarjetas con ciclo en main
        self.tabs = 0          # tabs dibujados (0 = máquina de un solo servicio)
        self.selected = None
        self._cards = []
        self.uart.write(END)   # limpia cualquier comando a medias
        self.cmd("thsp=0")     # nunca entrar en reposo
        self.cmd("dim=100")
        self.cmd("sendxy=1")   # por si el .tft no lo trae en Preinitialize

    # ---------- bajo nivel ----------
    def cmd(self, s):
        self.uart.write(s.encode("utf-8") + END)

    @staticmethod
    def _q(text):
        # comillas escapadas; salto de línea real -> \r de Nextion
        return str(text).replace('"', '\\"').replace("\n", "\\r")

    def text(self, box, value, pco=None, pic=None):
        """Dibuja `value` en la caja, borrando lo anterior con el recorte del fondo."""
        x, y, w, h, font, xcen = box[:6]
        color = pco if pco is not None else box[6]
        bg = pic if pic is not None else PAGES[self.page]
        self.cmd('xstr %d,%d,%d,%d,%d,%d,%d,%d,1,0,"%s"'
                 % (x, y, w, h, font, color, bg, xcen, self._q(value)))

    def goto(self, page, title=None):
        """Cambia de página y pinta su fondo. El fondo se pinta aquí también (no sólo
        con el pic de la página en el Editor), así una página mal configurada en el
        .tft no deja el fondo de otra debajo de los textos."""
        self.cmd("page " + page)
        self.cmd("pic 0,0,%d" % PAGES[page])
        self.page = page
        if title is not None:
            self.text(TITLE, title)

    # ---------- página main: elegir ciclo ----------
    def show_main(self, title, cards, tabs=(), active=0):
        """cards: lista de dicts {name, detail, price, icon} (máximo 4).
        tabs: etiquetas de servicio (["Lavado", "Secado"]); con una sola, se dibuja como
        etiqueta (no se puede tocar). Los pasos los dibuja quien llama (step), después de esto."""
        self.goto("main", title)
        self.used = 0
        self.tabs = len(tabs) if len(tabs) > 1 else 0
        for i in range(len(tabs[:len(TABS)])):
            self.tab(i, tabs[i], i == active)
        self.show_cards(cards)

    def tab(self, i, label, on):
        x, y = TABS[i]
        self.cmd("xpic %d,%d,%d,%d,0,%d,%d" % (x, y, TAB_W, TAB_H, 0 if on else TAB_H, PIC_TABS))
        bg, color = TAB_COLORS[0 if on else 1]
        self._solid(x, y, TAB_TEXT, label, color, bg)

    def step(self, n, state, text):
        """Paso n (1 o 2) en un estado STEP_*, con su texto."""
        x, y = STEPS[n - 1]
        self.cmd("xpic %d,%d,%d,%d,0,%d,%d" % (x, y, STEP_W, STEP_H, ((n - 1) * 5 + state) * STEP_H, PIC_STEPS))
        bg, color = STEP_COLORS[state]
        self._solid(x, y, STEP_TEXT, text, color, bg)

    def qr_panel(self, ready):
        """Panel del lector resaltado cuando ya se puede escanear."""
        x, y, w, h = QR_PANEL
        self.cmd("picq %d,%d,%d,%d,%d" % (x, y, w, h, PIC_MAIN_SEL if ready else PAGES["main"]))

    def _solid(self, x, y, box, text, color, bg):
        bx, by, w, h, font, xcen = box
        self.cmd('xstr %d,%d,%d,%d,%d,%d,%d,%d,1,1,"%s"'
                 % (x + bx, y + by, w, h, font, color, bg, xcen, self._q(text)))

    def show_cards(self, cards):
        """Redibuja las tarjetas. Las que sobran quedan como fondo vacío."""
        old = self.used
        self._cards = list(cards)[:SLOTS]
        self.used = len(self._cards)
        self.selected = None
        for i in range(max(old, self.used)):
            if i < self.used:
                self._card(i, False)
            else:
                x, y = CARDS[i]
                self.cmd("picq %d,%d,%d,%d,%d" % (x, y, CARD_W, CARD_H, PAGES["main"]))

    def _card(self, i, on):
        x, y = CARDS[i]
        pic = PIC_MAIN_SEL if on else PIC_MAIN_CARD
        self.cmd("picq %d,%d,%d,%d,%d" % (x, y, CARD_W, CARD_H, pic))
        c = self._cards[i]
        ix, iy = CARD_ICON
        self.cmd("xpic %d,%d,%d,%d,%d,%d,%d"
                 % (x + ix, y + iy, ICON, ICON, int(c.get("icon") or 0) * ICON, ICON if on else 0, PIC_ICONS))
        for box, key, color in ((CARD_NAME, "name", INK), (CARD_PRICE, "price", PRICE),
                                (CARD_DETAIL, "detail", DETAIL)):
            bx, by, w, h, font, xcen = box
            self.text((x + bx, y + by, w, h, font, xcen), c[key], color, pic)

    def select(self, index):
        """Marca la tarjeta `index` (o ninguna con None). Sólo repinta lo que cambia."""
        if index == self.selected:
            return
        if self.selected is not None and self.selected < self.used:
            self._card(self.selected, False)
        if index is not None and index < self.used:
            self._card(index, True)
        self.selected = index

    def status(self, text, pco=INK):
        """Renglón de abajo de main, junto a la (i) (1-2 renglones)."""
        self.text(MAIN["status"], text, pco)

    # ---------- página confirm ----------
    def show_confirm(self, title, hello, balance, total, detail, timeout):
        self.goto("confirm", title)
        self.text(CONFIRM["hello"], hello)
        self.text(CONFIRM["bal"], balance)
        self.text(CONFIRM["total"], total)
        self.text(CONFIRM["detail"], detail)
        self.text(CONFIRM["timeout"], timeout)

    def confirm_timeout(self, text):
        self.text(CONFIRM["timeout"], text)

    def confirm_busy(self, text="Procesando pago..."):
        """Al tocar Confirmar: el botón verde pasa a gris con el texto y Cancelar
        se apaga, en el mismo instante, antes de la llamada al servidor."""
        x, y, w, h = BTN_CANCEL
        self.cmd("fill %d,%d,%d,%d,%d" % (x, y, w, h, BAR_BG))
        self.cmd('xstr %d,%d,%d,%d,%d,%d,%d,1,1,1,"Cancelar"' % (x, y, w, h, BTN_FONT, SEC, BAR_BG))
        x, y, w, h = BTN_OK
        self.cmd("fill %d,%d,%d,%d,%d" % (x, y, w, h, SEC))
        self.cmd('xstr %d,%d,%d,%d,%d,%d,%d,1,1,1,"%s"' % (x, y, w, h, BTN_FONT, WHITE, SEC, self._q(text)))
        self.text(CONFIRM["timeout"], "Recibimos tu confirmación. Procesando el pago...", GREEN_D)

    def flush_touches(self):
        """Descarta los toques que llegaron mientras el ESP32 esperaba al servidor."""
        self._buf = b""
        while self.uart.any():
            self.uart.read()

    # ---------- página inuse ----------
    def show_inuse(self, title, paid, step1, warn, cycle, timer, ends, progress=0):
        self.goto("inuse", title)
        self.text(INUSE["paid"], paid)
        self.text(INUSE["step1"], step1)
        self.text(INUSE["warn"], warn)
        self.text(INUSE["cycle"], cycle)
        self.text(INUSE["ends"], ends)
        self.update_timer(timer, progress)

    def update_timer(self, timer, progress, warn=None):
        self.text(INUSE["timer"], timer)
        x, y, w, h = BAR
        done = w * max(0, min(100, int(progress))) // 100
        self.cmd("fill %d,%d,%d,%d,%d" % (x, y, w, h, BAR_BG))
        if done:
            self.cmd("fill %d,%d,%d,%d,%d" % (x, y, done, h, GREEN))
        if warn is not None:
            self.text(INUSE["warn"], warn)

    # ---------- página nofunds ----------
    def show_nofunds(self, title, head, detail, qr_url, timeout):
        """qr_url: si el QR de la app ya está en la imagen de fondo, pásalo vacío;
        si no, se escribe el enlace como texto en el recuadro."""
        self.goto("nofunds", title)
        self.text(NOFUNDS["head"], head)
        self.text(NOFUNDS["detail"], detail)
        if qr_url:
            self.text(NOFUNDS["url"], qr_url)
        self.text(NOFUNDS["timeout"], timeout)

    def nofunds_timeout(self, text):
        self.text(NOFUNDS["timeout"], text)

    # ---------- página msg ----------
    def show_msg(self, title, head, sub="", foot="", pco=NAVY):
        self.goto("msg", title)
        self.text(MSG["head"], head, pco)
        self.text(MSG["sub"], sub)
        self.text(MSG["foot"], foot)

    # ---------- lectura de toques ----------
    def _event_at(self, x, y):
        for zx, zy, zw, zh, ev in TOUCH.get(self.page, ()):
            if zx <= x < zx + zw and zy <= y < zy + zh:
                if ev.startswith("SEL") and int(ev[3:]) >= self.used:
                    return None
                if ev.startswith("TAB") and int(ev[3:]) >= self.tabs:
                    return None
                return ev
        return None

    def poll(self):
        """Devuelve 'SEL0'..'SEL3', 'TAB0'/'TAB1', 'STEP1', 'OK', 'CANCEL', 'BACK' o None. No bloquea."""
        if self.uart.any():
            self._buf += self.uart.read() or b""
        while self._buf:
            # Toque: 0x67 xH xL yH yL evento FF FF FF (evento 0 = soltar)
            if self._buf[0] == 0x67:
                if len(self._buf) < 9:
                    return None
                frame, self._buf = self._buf[:9], self._buf[9:]
                if frame[6:9] != END:
                    self._resync()
                    continue
                x = (frame[1] << 8) | frame[2]
                y = (frame[3] << 8) | frame[4]
                if frame[5] == 0:
                    ev = self._event_at(x, y)
                    if ev:
                        return ev
                continue
            ff = self._buf.find(END)
            if ff == -1:
                if len(self._buf) > 256:
                    self._buf = b""
                return None
            frame, self._buf = self._buf[:ff], self._buf[ff + 3:]
            if frame and frame[0] not in (0x00, 0x88, 0x66):   # arranque / listo / id de página
                print("[nextion] respuesta:", frame)          # 0x1A/0x1B/0x1C = comando inválido
        return None

    def _resync(self):
        ff = self._buf.find(END)
        self._buf = self._buf[ff + 3:] if ff != -1 else b""


def money(v):
    try:
        v = float(v)
        return ("$%d" % v) if v == int(v) else ("$%.2f" % v)
    except (TypeError, ValueError):
        return "$" + str(v)
