# Driver mínimo para pantalla Nextion en MicroPython (ESP32).
# Protocolo:
#   ESP32 -> Nextion : comandos de texto terminados en FF FF FF
#   Nextion -> ESP32 : líneas de texto "SEL0".."SEL3" + "\n" al tocar un ciclo

from machine import UART

END = b"\xff\xff\xff"

COLOR_NORMAL = 50712    # gris claro
COLOR_SELECTED = 2016   # verde
COLOR_OK = 2016         # verde
COLOR_ERROR = 63488     # rojo
COLOR_INFO = 0          # negro


class Nextion:
    def __init__(self, uart_id=1, tx=27, rx=26, baud=9600, max_cycles=4):
        self.uart = UART(uart_id, baudrate=baud, tx=tx, rx=rx, timeout=10)
        self.max = max_cycles
        self.cycles = []
        self.selected = None
        self._buf = b""
        self.uart.write(END)           # limpia cualquier comando a medias
        self.cmd("page main")
        self.cmd("thsp=0")             # nunca entrar en reposo
        self.cmd("dim=100")

    # ---------- bajo nivel ----------
    def cmd(self, s):
        self.uart.write(s.encode("utf-8") + END)

    @staticmethod
    def _q(text):
        # comillas escapadas; salto de línea real -> \r de Nextion
        return str(text).replace('"', '\\"').replace("\n", "\\r")

    def set_text(self, comp, text):
        self.cmd('%s.txt="%s"' % (comp, self._q(text)))

    # ---------- alto nivel ----------
    def set_title(self, text):
        self.set_text("tTitle", text)

    def show_cycles(self, cycles):
        """cycles: lista de (nombre, precio, minutos). Máximo 4."""
        self.cycles = list(cycles)[: self.max]
        for i in range(self.max):
            b = "b%d" % i
            if i < len(self.cycles):
                name, price, minutes = self.cycles[i]
                self.set_text(b, "%s\n$%s - %s min" % (name, _money(price), minutes))
                self.cmd("vis %s,1" % b)
            else:
                self.cmd("vis %s,0" % b)
        self.select(None)

    def select(self, index):
        self.selected = index
        for i in range(len(self.cycles)):
            color = COLOR_SELECTED if i == index else COLOR_NORMAL
            self.cmd("b%d.bco=%d" % (i, color))
            self.cmd("b%d.bco2=%d" % (i, color))

    def set_status(self, text, color=COLOR_INFO):
        self.set_text("tStatus", text)
        self.cmd("tStatus.pco=%d" % color)

    def set_timer(self, text):
        self.set_text("tTimer", text)

    def lock(self, locked):
        """Bloquea/desbloquea el toque de todos los botones."""
        self.cmd("tsw 255,%d" % (0 if locked else 1))

    # ---------- lectura ----------
    def poll(self):
        """Devuelve el índice del ciclo tocado, o None. No bloquea."""
        if self.uart.any():
            self._buf += self.uart.read() or b""
        while self._buf:
            nl = self._buf.find(b"\n")
            ff = self._buf.find(END)
            if ff != -1 and (nl == -1 or ff < nl):
                frame = self._buf[:ff]
                self._buf = self._buf[ff + 3:]
                if frame:
                    print("[nextion] respuesta:", frame)   # p. ej. 1A = nombre inválido
                continue
            if nl == -1:
                if len(self._buf) > 256:
                    self._buf = b""
                return None
            line = self._buf[:nl].strip()
            self._buf = self._buf[nl + 1:]
            if line.startswith(b"SEL"):
                try:
                    i = int(line[3:])
                except ValueError:
                    continue
                if i < len(self.cycles):
                    self.select(i)
                    return i
        return None


def _money(v):
    try:
        v = float(v)
        return ("%d" % v) if v == int(v) else ("%.2f" % v)
    except (TypeError, ValueError):
        return str(v)
