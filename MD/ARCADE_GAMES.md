# Arcade — lógica de los juegos

Referencia de los diez mini-juegos de fichas virtuales: cómo funciona cada
uno, de dónde sale su ventaja de casa y qué impide hacer trampa.

**Código:** `modules/arcade.py` (orquestación, blackjack, topo) ·
`modules/arcadeGames.py` (los otros ocho) · `modules/arcadeFair.py` (juego limpio)
**SQL:** `sql/sp_arcade.sql` · `sql/sp_arcadeGames_unlock.sql`
**Frontend:** `src/pages/game/` en el repo POSVending

---

## 1. Las tres reglas que sostienen todo

### 1.1 Fichas, no dinero

`arcadeWallets.coinBalance` **no se canjea**. No toca `walletTransactions`, ni
Stripe, ni SPEI de salida. No existe función, SP ni columna que convierta
fichas en dinero o en puntos de recompensa.

Esa separación es regulatoria, no estética. La Ley Federal de Juegos y Sorteos
exige **apuesta Y premio**: sin ruta de canje no hay premio de valor económico,
y el modelo es el de casino social, no el de casa de apuestas. Abrir el canje
es una decisión de permiso SEGOB, no una feature.

> El puente prohibido es **fichas → puntos**. Los puntos (`rewardPoints`) sí
> valen —dan descuento en préstamos— porque se ganan por conducta (pagar a
> tiempo), no por azar. Mezclarlos convertiría una ganancia de azar en valor.

### 1.2 El servidor es la autoridad

El cliente **nunca reporta un resultado**, solo una intención: "pido carta",
"destapo la casilla 7", "pegué al topo 3 a los 412 ms". La baraja, las minas y
el calendario de topos se derivan en el servidor y viven en
`arcadeRounds.stateJson`. El navegador recibe una vista recortada.

`sp_arcadeRounds_one` devuelve el estado completo **solo al backend**; las
rutas arman la vista pública. Con la ronda abierta nunca salen: el zapato de
blackjack, la posición de las minas, el resultado del dado o de la ruleta.

### 1.3 Juego limpio (provably fair)

1. Al abrir se genera un `serverSeed` de 32 bytes y se entrega
   `serverSeedHash = SHA256(serverSeed)`.
2. El jugador aporta su `clientSeed`.
3. Todo el azar sale de `HMAC-SHA256(serverSeed, clientSeed)`.
4. Al liquidar se revela `serverSeed` y el jugador comprueba el hash.

Cada ronda estrena `serverSeed`, así que el `nonce` es contador de auditoría y
no entra en la derivación. Los enteros usan **muestreo con rechazo**
(`_rand_below`), no `% n`, para no sesgar los valores bajos.

---

## 2. Contrato común de los motores

Agregar un juego es agregar una entrada a `ENGINES`, no otra rama en el
despachador.

```python
{
  "new_round":    (server_seed, client_seed, options) -> state,
  "public_state": (state) -> dict,          # lo que ve el navegador
  "apply":        (state, action, payload) -> (state, finished, outcome, multiplier, detail),
  "actions":      tuple,                    # acciones válidas
  "instant":      bool,                     # se liquida al abrir
  "stake_actions": tuple,                   # cobran apuesta extra (doblar)
  "min_elapsed_ms": int,                    # ventana mínima (reflejos)
}
```

### Ciclo de vida

| Tipo | Juegos | Flujo |
|---|---|---|
| **Instantáneo** | volado, dados, ruleta, raspadito | `/arcade/bet` liquida en el mismo viaje |
| **Por turnos** | blackjack, mayor/menor, minas, penales, boliche | `/arcade/bet` → N× `/arcade/action` → liquida |
| **Reflejos** | topo | `/arcade/bet` → jugar 20 s → `/arcade/action` con los golpes |

`sp_arcadeRounds_open` cobra la apuesta y abre la ronda en **una transacción
con `UPDLOCK`**: sin ese candado dos apuestas simultáneas leerían el mismo
saldo y ambas pasarían (doble gasto). Solo se permite **una ronda abierta por
juego** (`round_in_progress`), o el jugador dejaría manos malas colgadas y
abriría otra hasta que saliera una buena.

`sp_arcadeRounds_settle` exige `roundStatus='open'`, así que un reintento del
cliente no paga dos veces.

---

## 3. Los diez juegos

### 3.1 Blackjack 21 — RTP 99.5%

6 barajas · crupier se planta en 17 (incluido blando) · blackjack paga 3:2 ·
doblar con dos cartas · **sin split**.

| Resultado | Retorno total |
|---|---|
| Blackjack natural | 2.5× |
| Ganar | 2× (4× doblado) |
| Empate | 1× (2× doblado) |
| Perder | 0 |

El multiplicador es **retorno total**: la apuesta ya se debitó al abrir, así
que ganar 1:1 paga 2×.

**Doblar cobra una segunda apuesta** (`sp_arcadeRounds_double`) antes de
aplicar la jugada. Sin ese cobro el jugador arriesgaba una y cobraba como si
hubiera arriesgado dos: doblar siempre saldría a favor y la ventaja se
invertía. El tope del catálogo debe ser **4.00** o un doble ganado se recorta.

**Anti-trampa:** el zapato completo vive en el servidor; solo viajan la mano
del jugador y la carta destapada del crupier.

---

### 3.2 Atrapa al Topo — RTP 96% *(calibración inicial)*

20 s · 24 topos · 9 hoyos · el topo asoma entre 1100 ms y 620 ms (se acelera).

| Aciertos | Pago |
|---|---|
| 24 | 5.0× |
| 23 | 4.0× |
| 22 | 3.0× |
| 21 | 2.5× |
| 19–20 | 2.0× |
| 17–18 | 1.5× |
| 15–16 | 1.0× |
| 12–14 | 0.5× |
| <12 | 0 |

**Anti-trampa** — cada golpe se valida contra el calendario real:
el topo existió · no repetido · `120 ms ≤ reacción ≤ duración`. Los inventados
se descartan y se cuentan en `result.rejectedHits`. Además la liquidación se
rechaza (`too_early`) antes del 80% de la ronda: nadie jugó.

> ⚠️ **La escalera es una calibración, no una verdad.** El RTP real de un juego
> de habilidad depende de qué tan bien juega la gente. Retunear con:
> ```sql
> SELECT SUM(payoutAmount)*1.0/SUM(betAmount) FROM arcadeRounds
> WHERE gameKey='mole' AND roundStatus='settled';
> ```

---

### 3.3 Volado — RTP 98%

Moneda **justa** (50/50) que paga **1.96×** (= 2 × 0.98).

La alternativa —pagar 2× con una moneda cargada al 49%— da el mismo margen
pero sería mentir sobre el sorteo, y el jugador puede re-derivarlo con la
semilla. Se prefiere el pago honesto sobre el sorteo trucado.

`options: { pick: "aguila" | "sol" }`

---

### 3.4 Dados — RTP 97%

Tiro uniforme **0–99**. El jugador elige umbral (**4–96**) y dirección.

```
under:  gana si roll < target     p = target/100
over:   gana si roll > target     p = (99-target)/100
pago    = 0.97 / p
```

El margen es constante: apostar "casi seguro" paga poco y "casi imposible"
paga mucho, sin que la casa cambie de ventaja. Tope real **24.25×**
(umbral 4).

`options: { target: int, direction: "under" | "over" }`

---

### 3.5 Ruleta de Premios — RTP 96%

**50 casillas** que suman 48.00 → 0.9600 exacto.

| Multiplicador | Casillas | Probabilidad |
|---|---|---|
| 0× | 32 | 64% |
| 1× (recuperas) | 10 | 20% |
| 2× | 5 | 10% |
| 4× | 2 | 4% |
| **20×** | 1 | 2% |

> **Por qué el premio mayor es 20× y no 50×:** con 50 casillas, una sola de
> 50× aporta 1.00 al retorno — más que el RTP entero de 0.96 — y no quedaría
> nada para las demás. Un 50× honesto pediría 60+ casillas con casi todas en
> cero, que es una rueda peor de jugar. Se bajó el tope y se corrigió el
> catálogo.

---

### 3.6 Raspadito — RTP 94%

Se sortea **primero el premio** con una tabla de pesos y **después** se acomodan
las nueve casillas para contar esa historia. Al revés —generar casillas al azar
y ver qué sale— el RTP dependería de coincidencias y sería imposible de fijar.

| Premio | Peso /1000 | Probabilidad |
|---|---|---|
| 0× | 796 | 79.6% |
| 2× | 140 | 14.0% |
| 5× | 40 | 4.0% |
| 12× | 20 | 2.0% |
| 40× | 3 | 0.3% |
| **100×** | 1 | 0.1% |

Sin premio, la carta nunca forma un trío accidental (máximo dos iguales).

---

### 3.7 Mayor o Menor — RTP 96%

Baraja de 52 **sin reposición**: al salir cartas las probabilidades cambian y
el pago se recalcula con las que quedan. Probabilidades fijas serían
explotables contando cartas. **El empate pierde.** Tope 20×.

```
p_mayor = cartas mayores restantes / restantes
justo_acumulado *= 1/p          # se acumula SIN recortar
multiplicador   = justo_acumulado × 0.96   # el RTP se aplica UNA vez
```

Apostar a algo imposible (mayor que un As) se **rechaza**, no se cobra
(`impossible_bet`); el frontend además deshabilita ese botón.

---

### 3.8 Minas — RTP 97%

25 casillas, el jugador elige **1–24** minas. Retiro en cualquier momento.

```
justo(k) = C(25,k) / C(25-m,k)
pago(k)  = justo(k) × 0.97      (tope 24×)
```

Ejemplo con 3 minas: 1 destape → 1.10× · 3 → 1.45× · 5 → 1.96× · 10 → 4.90×.

**Las minas quedan fijadas al abrir.** Si se sortearan al tocar, el servidor
podría decidir a posteriori dónde poner la que mata. `mineTiles` solo sale en
el estado público **cuando la ronda terminó**.

`options: { mines: int }`

---

### 3.9 Penales — RTP 95%

Duelo real de 5 zonas: el tirador elige esquina, el portero elige lado, y
**solo ataja si coinciden**. p(gol) = 4/5 = 0.8. Racha con retiro, tope 3×.

Ofrecer la elección sin que influyera en nada sería agencia de mentira. Con el
portero uniforme la probabilidad es la misma, así que el RTP no cambia —
cambia que la jugada sea de verdad.

`payload: { zone: 0..4 }` (obligatorio; sin él → `bad_zone`)

---

### 3.10 Boliche — RTP 95%

Mismo motor que penales, distinta probabilidad: p(chuza) = **0.62**, tope 10×.
Racha con retiro. `action: "roll"`.

---

## 4. La ventaja se aplica UNA vez

En los juegos de retiro (mayor/menor, minas, penales, boliche) se acumula el
pago **justo** (producto de 1/p) y el RTP se aplica **una sola vez al final**.

Aplicarlo en cada paso lo **compone** y hunde el retorno muy por debajo de lo
anunciado:

| Pasos | RTP real si se compone (0.95) |
|---|---|
| 1 | 0.9500 |
| 3 | 0.8574 |
| 5 | 0.7738 |
| 8 | 0.6634 |

Como el número se le muestra al jugador en la hoja de juego limpio, componerlo
sería publicidad falsa. Con el RTP aplicado una vez, **retirarse en cualquier
momento devuelve exactamente lo anunciado**.

---

## 5. RTP medido (120,000 rondas por escenario)

| Juego | Escenario | Medido | Meta |
|---|---|---|---|
| volado | un tiro | 0.9846 | 0.98 |
| dados | under 50 | 0.9690 | 0.97 |
| dados | under 90 | 0.9703 | 0.97 |
| dados | under 10 | 0.9788 | 0.97 |
| ruleta | un giro | 0.9668 | 0.96 |
| raspadito | una carta | 0.9458 | 0.94 |
| mayor/menor | 3 aciertos y retiro | 0.9607 | 0.96 |
| mayor/menor | 6 aciertos y retiro | 0.9440 | 0.96 |
| minas | 3 minas, 5 destapes | 0.9697 | 0.97 |
| minas | 10 minas, 3 destapes | 0.9645 | 0.97 |
| penales | 3 goles y retiro | 0.9506 | 0.95 |
| boliche | 4 chuzas y retiro | 0.9445 | 0.95 |

Motor de blackjack validado por separado: barajada uniforme (χ²=111 sobre 119
gl en las 120 permutaciones de 5 elementos), naturales 4.7402% vs 4.7489%
teórico, crupier se pasa 28.07% vs ~28.3%.

> Quedar **por debajo** de la meta al encadenar muchos pasos es el efecto del
> tope de multiplicador, no un error de la fórmula.

---

## 6. Endpoints

| Ruta | Qué hace |
|---|---|
| `POST /all_arcadeGames` | Catálogo |
| `POST /one_arcadeWallet` | Monedero (lo crea con fichas de bienvenida) |
| `POST /arcade/dailyBonus` | Bono diario (1 cada 24 h) |
| `POST /arcade/bet` | Abre ronda y cobra la apuesta |
| `POST /arcade/action` | Aplica una jugada |
| `POST /one_arcadeRound` | Retomar ronda abierta (semilla oculta) |
| `POST /all_arcadeRounds` | Historial |
| `POST /arcade/liveWins` | Ticker de ganancias (**anónimo**) |
| `POST /all_arcadeTransactions` | Libro de fichas |

### Errores de negocio

`insufficient_coins` · `daily_limit` · `round_in_progress` · `wallet_locked` ·
`round_not_open` → **409**
`bad_bet` · `bet_out_of_range` · `game_unavailable` · `unknown_action` ·
`cannot_double` · `too_early` · `bad_zone` · `bad_tile` · `impossible_bet` → **400**

---

## 7. Añadir un juego nuevo

1. Escribir `new_round` / `public_state` / `apply` en `modules/arcadeGames.py`.
2. Registrarlo en `GAME_ENGINES`.
3. **Simular el RTP** antes de exponerlo.
4. Sembrarlo en `arcadeGames` con su `rtp` y `maxMultiplier` **reales**.
5. Vista en `src/pages/game/`, ruta en `App.tsx`, entrada en `GAME_ROUTES`.
6. Recién entonces poner `comingSoon = '0'`.

> El orden importa: `sp_arcadeRounds_open` rechaza cualquier juego con
> `comingSoon='1'`, así que desbloquear antes de tener motor deja tiles que
> aceptan la apuesta y luego no saben jugarla.

**`maxMultiplier` debe cubrir el tope real del motor.** `_payout_for()` recorta
el pago a ese valor: si se queda corto, un premio legítimo se paga de menos
(pasó con el doble de blackjack, catálogo 2.50 vs real 4.00).

---

## 8. Pendientes conocidos

- **Escalera del topo sin calibrar** contra telemetría real (§3.2).
- **`arcadeChipOrders`** (SPEI) exige puerta de rol en `/arcade/speiConfirm`
  antes de producción — hoy nada valida quién concilia.
- **Datos de prueba en producción**: clientes `999001`–`999029` y `777`
  ensucian cualquier cálculo de RTP; excluirlos o borrarlos.
