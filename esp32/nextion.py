# Driver de la pantalla Nextion GMO (diseño v2, 5 páginas) para MicroPython.
#
# MODO DIBUJO: el proyecto del Editor sólo tiene fuentes, imágenes y 5 páginas
# con su fondo (sta=image), sin componentes. Todo el texto lo dibuja el ESP32
# con xstr, la tarjeta seleccionada con picq y la barra con fill. Los toques
# llegan como coordenadas (sendxy=1 en el Preinitialize de main) y aquí se
# traducen a los mismos eventos de antes: SEL0..SEL3, OK, CANCEL, BACK.
#
# Para mover un texto o cambiar un color, edita las tablas de abajo: no hace
# falta volver a compilar ni cargar el .tft.
#
# Páginas e imágenes (deben coincidir con el proyecto del Editor):
#   main=0 (main_sel=1), confirm=2, inuse=3, nofunds=4, msg=5
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
SEL_SEC = 55196
BAR_BG = 57117

LEFT, CENTER, RIGHT = 0, 1, 2
SLOTS = 4

PAGES = {"main": 0, "confirm": 2, "inuse": 3, "nofunds": 4, "msg": 5}
PIC_MAIN_SEL = 1

# Cajas de texto: (x, y, w, h, fuente, alineación, color)
TITLE = (28, 48, 300, 28, 1, LEFT, SEC)

CARDS = [(28, 122), (408, 122), (28, 251), (408, 251)]   # esquina de cada tarjeta
CARD_W, CARD_H = 364, 117
# dentro de la tarjeta, relativo a su esquina
CARD_NAME = (60, 14, 190, 34, 2, LEFT)
CARD_DETAIL = (60, 50, 190, 26, 1, LEFT)
CARD_MIN = (60, 78, 190, 24, 0, LEFT)
CARD_PRICE = (254, 30, 90, 56, 3, RIGHT)

# Tabs de la máquina combo (Lavado / Secado), en la fila de "Selecciona tu ciclo".
# Con un solo producto no se dibujan.
TABS = [(468, 88, 148, 30), (624, 88, 148, 30)]
TAB_FONT = 1

MAIN = {
    "sel": (48, 414, 330, 40, 2, LEFT, NAVY),
    "selp": (400, 396, 160, 56, 3, RIGHT, GREEN),
    "status": (638, 392, 128, 64, 0, LEFT, NAVY),
}
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

# Zonas táctiles por página: (x, y, w, h, evento)
TOUCH = {
    "main": [(x, y, CARD_W, CARD_H, "SEL%d" % i) for i, (x, y) in enumerate(CARDS)]
            + [(x, y, w, h, "TAB%d" % i) for i, (x, y, w, h) in enumerate(TABS)],
    "confirm": [(150, 388, 180, 64, "CANCEL"), (346, 388, 304, 64, "OK")],
    "nofunds": [(28, 388, 192, 64, "BACK")],
}


class Nextion:
    def __init__(self, uart_id=1, tx=27, rx=26, baud=9600):
        self.uart = UART(uart_id, baudrate=baud, tx=tx, rx=rx, timeout=10)
        self._buf = b""
        self.page = None
        self.used = 0          # tarjetas con ciclo en main
        self.tabs = []         # etiquetas de los tabs (vacío = sin tabs)
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
    def show_main(self, title, cards, tabs=None, active=0):
        """cards: lista de dicts {name, detail, minutes, price} (máximo 4).
        tabs: etiquetas (["Lavado", "Secado"]); con menos de 2 no se dibujan."""
        self.goto("main", title)
        self.tabs = list(tabs or [])[:len(TABS)] if tabs and len(tabs) > 1 else []
        self.draw_tabs(active)
        self.show_cards(cards)

    def draw_tabs(self, active):
        for i, label in enumerate(self.tabs):
            x, y, w, h = TABS[i]
            on = (i == active)
            bg = GREEN if on else BAR_BG
            self.cmd("fill %d,%d,%d,%d,%d" % (x, y, w, h, bg))
            self.cmd('xstr %d,%d,%d,%d,%d,%d,%d,1,1,1,"%s"'
                     % (x, y, w, h, TAB_FONT, WHITE if on else NAVY, bg, self._q(label)))

    def show_cards(self, cards):
        """Redibuja las 4 tarjetas (al cambiar de tab). Las que sobran quedan vacías."""
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
        pic = PIC_MAIN_SEL if on else PAGES["main"]
        self.cmd("picq %d,%d,%d,%d,%d" % (x, y, CARD_W, CARD_H, pic))
        c = self._cards[i]
        for box, key, normal, sel in ((CARD_NAME, "name", NAVY, WHITE),
                                      (CARD_DETAIL, "detail", SEC, SEL_SEC),
                                      (CARD_MIN, "minutes", SEC, SEL_SEC),
                                      (CARD_PRICE, "price", NAVY, WHITE)):
            bx, by, w, h, font, xcen = box
            self.text((x + bx, y + by, w, h, font, xcen), c[key], sel if on else normal, pic)

    def select(self, index, sel_text="", sel_price=""):
        """Marca la tarjeta `index` (o ninguna con None) y llena el panel inferior.
        Sólo repinta las tarjetas que cambian."""
        if index != self.selected:
            if self.selected is not None and self.selected < self.used:
                self._card(self.selected, False)
            if index is not None and index < self.used:
                self._card(index, True)
            self.selected = index
        self.text(MAIN["sel"], sel_text)
        self.text(MAIN["selp"], sel_price)

    def status(self, text, pco=NAVY):
        """Texto chico del panel inferior derecho (2-3 renglones)."""
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
                if ev.startswith("TAB") and int(ev[3:]) >= len(self.tabs):
                    return None
                return ev
        return None

    def poll(self):
        """Devuelve 'SEL0'..'SEL3', 'TAB0'/'TAB1', 'OK', 'CANCEL', 'BACK' o None. No bloquea."""
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
