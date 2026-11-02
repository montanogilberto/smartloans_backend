# Pantalla main v3: pasos interactivos + tabs Lavado | Secado

Página **main** del Nextion (NX8048P070, 800×480). Las otras páginas (confirm, inuse,
nofunds, msg) siguen con los fondos v2.

- `make_main.py` genera las imágenes (`python3 esp32/design/make_main.py`, necesita Pillow).
- `simulate.py` corre el `screen.py` real con un UART falso y guarda en `preview/` cómo se
  ve cada momento (elige, pulso, escanea, consultando, error, secado, solo lavado), sin la
  pantalla: `python3 esp32/design/simulate.py`.
- `assets/`: lo que se importa en el Nextion Editor.

La geometría y los colores de `make_main.py` y de `esp32/nextion.py` (STEPS, TABS, CARDS,
QR_PANEL, STEP_COLORS...) tienen que ser iguales: si cambias uno, cambia el otro.

## Cómo funciona

- **Pasos** "1 Elige tu ciclo › 2 Escanea tu QR": cada paso tiene 5 estados en `8_steps.png`
  (pendiente, activo, pulso, listo ✓, error !). El ESP32 pone la forma con `xpic` y escribe el
  texto encima, así el texto cambia en vivo: "✓ Básico · $40", "Consultando tu saldo...",
  "QR no válido". El paso activo pulsa cada 0.7 s; un error se queda 4 s en rojo y vuelve solo.
  Tocar el paso 1 ya listo quita la selección (igual que Cancelar).
- **Tabs** Lavado | Secado (`9_tabs.png`) cuando la máquina es combo; 4 tarjetas por tab.
  Con un solo servicio se dibuja el nombre del servicio como etiqueta, sin tab.
- **Tarjetas** normales (`6_main_card.png`) y marcadas (`1_main_sel.png`) con `picq`; ícono por
  ciclo desde `7_icons.png`.
- **Panel QR**: se resalta (borde azul claro) cuando ya hay ciclo y se puede escanear.

## Qué cambia en el proyecto del Editor (`gmo_v2`)

Pestaña **Picture**. Los IDs importan.

| ID | Archivo | Acción |
|---|---|---|
| 0 | `0_main.png` | **Reemplazar** (doble clic en la imagen 0 → elegir el archivo nuevo) |
| 1 | `1_main_sel.png` | **Reemplazar** |
| 2–5 | confirm, inuse, nofunds, msg | sin cambios |
| 6 | `6_main_card.png` | **Agregar** (botón +, queda al final) |
| 7 | `7_icons.png` | **Agregar** |
| 8 | `8_steps.png` | **Agregar** |
| 9 | `9_tabs.png` | **Agregar** |

Fuentes y páginas: sin cambios. Después: **Compile**, **File → TFT file output** y carga
el `.tft` a la pantalla (microSD o USB-TTL), como la vez anterior.

## Firmware

`sh esp32/build_mpy.sh` y sube todo `esp32/dist/` a la placa.

**Orden:** primero el `.tft` nuevo, luego el firmware. El firmware nuevo con el `.tft` viejo
no tiene las imágenes 6–9 y la pantalla se ve rota (tarjetas vacías, bloques de color).

Antes de instalar en la lavandería, prueba con `nextion_test.py` en Thonny: toca un ciclo
(paso 1 pasa a ✓, paso 2 se activa, el panel QR se resalta, luego el paso 2 se pone en rojo)
y después **Cancelar** (vuelve al paso 1).
