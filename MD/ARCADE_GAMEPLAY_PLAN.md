# Arcade — plan de profundización de juego (Fase 1)

Plan previo a escribir código, según el brief. Cubre los cinco juegos de mayor
impacto: **Minas · Mayor o Menor · Penales · Boliche · Topo**.

Regla que atraviesa todo: **lo que cambia probabilidad o pago se modela y se
simula en el backend antes de exponerse**. Lo que solo cambia presentación no
toca el motor.

---

## Resumen: qué exige backend y qué no

| Juego | Cambio | ¿Motor? | ¿RTP? | ¿Semilla/catálogo? |
|---|---|---|---|---|
| **Minas** | escalera visual, presets, tablero rico | **No** | sin cambio | no |
| **Mayor o Menor** | mostrar probabilidad real, escalera | **Sí** (exponer `chance`) | sin cambio | no |
| **Penales** | estilos de tiro con trade-off real | **Sí** (probabilidad por estilo) | sin cambio* | **sí** (`maxMultiplier`) |
| **Boliche** | dirección + potencia + efecto | **Sí** (modelo nuevo) | sin cambio* | **sí** (`maxMultiplier`) |
| **Topo** | fases, combo, tipos de blanco | **Sí** (schedule + validación) | **recalibrar** | no |

\* RTP objetivo se conserva; hay que **demostrarlo por simulación**, no asumirlo.

---

## 1. Minas — el más barato y de mayor retorno

**Hoy:** 25 casillas, elegir minas (1–24), destapar, retirar. Multiplicador
combinatorio con RTP aplicado una vez. Las minas se fijan al abrir y solo se
revelan al liquidar.

**Propuesto:** tablero 5×5 con estados ricos, escalera de multiplicador
prominente (`1 segura → 1.10x`, `5 seguras → 2.41x`), presets
**Principiante 3 / Equilibrado 7 / Extremo 15**, y el botón de retiro como
centro emocional.

**Backend:** *ninguno*. El motor ya acepta `mines` de 1 a 24; los presets son
etiquetas del frontend sobre la misma opción. No inventar modos que el backend
no conozca.

**Frontend:** reescribir `MinesView`. Escalera derivada de `nextMultiplier` que
ya manda el servidor — **no recalcular la combinatoria en React**.

**RTP:** sin cambio (0.97 sobre el justo acumulado).

**Anti-trampa:** sin cambio. `mineTiles` sigue en `null` hasta liquidar. **No**
mapas de calor, proximidad ni "casillas con suerte".

**Cashout parcial:** **descartado por ahora**. El backend no lo soporta y
fingir saldos parciales en el cliente rompería la liquidación. Requiere
rediseñar `sp_arcadeRounds_settle`; queda fuera de Fase 1.

**Pruebas:** `mineTiles` nulo con ronda abierta · escalera coincide con
`mines_multiplier` · destapar casilla repetida da `bad_tile`.

---

## 2. Mayor o Menor — información honesta

**Hoy:** baraja de 52 sin reposición, probabilidades recalculadas con las
cartas restantes. El estado público expone `higherPays` / `lowerPays` pero **no
las probabilidades**.

**Propuesto:** mostrar `Mayor 42% · Menor 58%` con el número real, escalera de
rondas y la decisión retirar/continuar como momento central.

**Backend:** añadir `higherChance` / `lowerChance` a `hl_public`. Es solo
exponer lo que `hl_chances()` ya calcula.

> **¿Filtra algo?** No. Se derivan de las cartas **no salidas**, y el jugador ya
> vio cuáles salieron: puede calcularlo con papel. Exponerlo iguala el
> conocimiento sin revelar la baraja.

**Frontend:** escalera + porcentajes. **No aproximar la probabilidad en React**
— un número que contradiga al backend es peor que no mostrarlo.

**RTP:** sin cambio.

**Anti-trampa:** sin cambio; `impossible_bet` sigue del lado servidor y el botón
sigue deshabilitado.

**Pruebas:** `higherChance + lowerChance + p(empate) = 1` · el porcentaje
mostrado corresponde al pago (`pago ≈ 0.96/chance`).

---

## 3. Penales — estilos de tiro con trade-off real

**Hoy:** 5 zonas, portero uniforme, p(gol) = 0.8 fijo, racha con retiro, tope 3×.

**Propuesto:** tres estilos con intercambio genuino:

| Estilo | p(gol) | Paso (justo × 0.95) | Sensación |
|---|---|---|---|
| **Colocado** | 0.90 | 1.056× | seguro, avanza poco |
| **Potente** | 0.80 | 1.188× | equilibrado (el actual) |
| **Panenka** | 0.60 | 1.583× | arriesgado, salta el marcador |

**Por qué el RTP no cambia:** cada paso acumula el **justo** (`1/p`) y el RTP se
aplica una sola vez al final. Con estilos mezclados:

```
EV = (Π pᵢ) × (Π 1/pᵢ) × 0.95 = 0.95
```

El estilo mueve la **varianza**, no el retorno. Eso es exactamente lo que hace
interesante la decisión.

**Backend:** `PENALTY_STYLES` con su `prob`; validar `style` en el payload como
ya se valida `zone`; guardar el estilo en `state["last"]` para la animación.

**Anti-trampa:** estilo inválido → `bad_style` (mismo patrón que `bad_zone`). La
zona sigue siendo obligatoria.

**Catálogo:** con panenka el justo crece rápido: 3 seguidas dan `(1/0.6)³ × 0.95
= 4.40×`, por encima del tope actual de 3.00 — **se recortaría un premio
legítimo** (el mismo error del doble en blackjack). Subir `maxMultiplier` a
**6.00** y ajustar `PENALTY_MAX_MULT`.

**Pruebas:** RTP simulado por estilo y mezclado ≈ 0.95 · `bad_style` rechaza ·
el tope no recorta rachas normales.

---

## 4. Boliche — identidad propia

**Hoy:** clon estructural de penales con otra probabilidad. El brief pide
explícitamente arreglarlo.

**Propuesto:** tiro de tres controles — **dirección**, **potencia**, **efecto**.

Modelo honesto, evitando el pozo del "skill = RTP incalculable":

1. La semilla genera la **condición de pista** de cada tiro (dónde está el
   *pocket* y cuánto aceite hay) y **se muestra ANTES de lanzar**.
2. **Dirección + efecto** deben compensar esa condición. Es una decisión
   *legible*, no un test de reflejos.
3. **Potencia** elige el nivel de riesgo:

| Potencia | p(chuza) si apuntas bien | Paso |
|---|---|---|
| Suave | 0.72 | 1.319× |
| Normal | 0.62 | 1.532× |
| Fuerte | 0.48 | 1.979× |

4. Apuntar mal reduce p; la penalización sale de la distancia al *pocket*.

> **El RTP declarado supone tiro correcto**, igual que el 99.5% de blackjack
> supone estrategia básica. Un jugador que ignora la condición de pista rinde
> por debajo — eso es habilidad real, no una casa que hace trampa. Hay que
> **decirlo en la hoja de juego limpio**.

**Backend:** motor propio (dejar de reusar `_STREAK_GAMES` para boliche);
`bowl_new_round` genera la condición por tiro; validar `direction` `power`
`spin`.

**Catálogo:** `maxMultiplier` 10.00 sigue sirviendo; verificar contra el tope
real por simulación.

**Pruebas:** RTP con tiro óptimo ≈ 0.95 por nivel de potencia · RTP con tiro
aleatorio **debe salir menor** (prueba de que la habilidad importa) · payload
inválido rechazado.

---

## 5. Topo — fases, combo y tipos

**Hoy:** 24 topos, 9 hoyos, ventana de 1100→620 ms, escalera por aciertos,
validación estricta de cada golpe.

**Propuesto:** cinco fases (calentamiento → frenesí), combo visible, y tipos de
blanco:

| Tipo | Efecto |
|---|---|
| Normal | acierto estándar |
| Bonus | cuenta doble |
| Especial | ventana más corta, cuenta triple |
| Peligro | **no se debe golpear**; pegarle rompe el combo |

**Backend:** el schedule ya se genera entero antes de la ronda — se le añaden
`phase` y `type` a cada spawn. El **combo se recalcula en el servidor** desde
los golpes válidos; nunca se acepta el combo que reporte el cliente.

**RTP — el punto delicado:** la escalera actual **ya está sin calibrar**
(`MOLE_PAYOUT_LADDER` dice explícitamente que es una calibración inicial).
Bonus/Especial/Peligro cambian la distribución de puntaje, así que la escalera
**debe re-derivarse**.

> Un juego de habilidad no tiene RTP cerrado: depende de qué tan bien juega la
> gente. Plan honesto: simular con perfiles de jugador (malo / medio / bueno),
> fijar la escalera para que el jugador **medio** quede en 0.96, y retunear con
> telemetría real. Esto se documenta, no se esconde.

**Anti-trampa:** se conserva íntegra —blanco existió, sin repetir, reacción
entre 120 ms y la ventana, `too_early`— y se **añade**: pegarle a un Peligro es
válido como evento pero **no suma**; el combo lo calcula el servidor.

**Pruebas:** golpes fabricados siguen rechazados · combo del servidor ignora el
del cliente · RTP por perfil de jugador.

---

## 6. Orden y criterio de "terminado"

1. **Minas** — sin riesgo de motor, valida el lenguaje visual nuevo.
2. **Mayor o Menor** — cambio de backend mínimo.
3. **Penales** — primer cambio real de matemáticas.
4. **Boliche** — motor nuevo, el más grande.
5. **Topo** — el que necesita recalibrar.

Un juego está terminado cuando: tiene identidad propia · el jugador toma una
decisión con consecuencia · el RTP simulado coincide con el anunciado · el
cliente no puede alterar el resultado · y la ronda se puede retomar.

---

## 7. Riesgos y lo que NO se hará

- **No** cashout parcial en Minas (exige rediseñar la liquidación).
- **No** pistas de proximidad de minas.
- **No** cerca-fallas falsas en la ruleta ni en el raspadito.
- **No** psicología de "va a salir": el volado seguirá diciendo que cada tiro es
  independiente.
- **No** mover autoridad al frontend por fluidez de animación.
- **No** tocar la separación fichas / puntos / MXN.

**Bloqueante previo:** la corrección de `arcade_bet_sp` (el bug
`name 'action' is not defined`) **sigue sin desplegar**. Producción tiene el
arcade caído; eso va primero.
