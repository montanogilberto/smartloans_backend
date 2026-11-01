#!/bin/sh
# Precompila el firmware a .mpy para subirlo a la placa.
#
# Por qué: al arrancar, MicroPython compila cada .py en RAM. Ese pico hace
# crecer el heap de Python tomando memoria del sistema (ESP-IDF) que nunca
# devuelve, y el handshake TLS (HTTPS) se queda sin espacio -> ENOMEM en el
# heartbeat. Con .mpy no se compila nada en la placa.
#
# Uso:  sh esp32/build_mpy.sh        (necesita mpy-cross 1.29: pip install mpy-cross==1.29.0.post2)
# Sube TODO lo de esp32/dist/ a la placa y BORRA ahí los .py viejos de los mismos
# módulos (api, hw, net, nextion, screen): si están ambos, MicroPython carga el .py.
# config.py, boot.py y wifi.json se quedan como están en la placa.
set -e
cd "$(dirname "$0")"
MPY_CROSS=${MPY_CROSS:-mpy-cross}
rm -rf dist && mkdir dist
for m in api hw net nextion screen; do
  "$MPY_CROSS" -o "dist/$m.mpy" "$m.py"
done
# main.py tiene que ser .py (la placa lo ejecuta al arrancar): la lógica va en app.mpy.
"$MPY_CROSS" -o dist/app.mpy main.py
printf 'import app  # lógica en app.mpy (precompilado con build_mpy.sh)\n' > dist/main.py
ls -l dist
