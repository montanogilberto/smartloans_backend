"""
arcadeGames — los ocho juegos que acompanan a blackjack y al topo.

Todos siguen el MISMO contrato que ENGINES en modules/arcade.py:
    new_round(server_seed, client_seed, options) -> state
    public_state(state) -> dict          (lo que puede ver el navegador)
    apply(state, action, payload) -> (state, finished, outcome, multiplier, detail)

MATEMATICAS DE LA CASA. Cada juego cobra su ventaja de UNA sola forma: el pago
justo (1/probabilidad) multiplicado por el RTP del catalogo. Nunca se trucan
las probabilidades — la barajada y los tiros salen del mismo chorro de bytes
verificable de siempre, y el jugador puede recalcularlos con la semilla. Un
juego que dice 96% y paga 96% es auditable; uno que dice 96% y sesga el dado
no lo es.

Los juegos de RETIRO (mayor/menor, minas, penales, boliche) acumulan el pago
JUSTO (producto de 1/p) y aplican el RTP UNA SOLA VEZ al final. Aplicarlo en
cada paso lo compondria —0.95^8 = 0.66— y el numero que ve el jugador en la
hoja de juego limpio dejaria de ser cierto en cuanto encadenara un par de
aciertos. Con el RTP aplicado una vez, retirarse en cualquier momento tiene
exactamente el retorno anunciado.
"""

from modules.arcadeFair import _byte_stream, _rand_below, shuffle

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

def _stream(state: dict):
    """Rehidrata el chorro de bytes de la ronda a partir de sus semillas."""
    return _byte_stream(state["_ss"], state["_cs"])


def _seeded(server_seed: str, client_seed: str, extra: dict) -> dict:
    """Estado base: guarda las semillas para poder re-derivar sin re-barajar."""
    return {"_ss": server_seed, "_cs": client_seed, "finished": False, **extra}


def _step_multiplier(prob: float, rtp: float) -> float:
    """Pago de UN paso aislado (1/prob recortado por el RTP). Solo para pintar."""
    if prob <= 0:
        return 0.0
    return round(rtp / prob, 4)


def _payout(fair: float, rtp: float, cap: float) -> float:
    """
    Multiplicador que se paga: el JUSTO acumulado por el RTP, una sola vez.

    Multiplicar pagos ya recortados (rtp/p en cada paso) compone la ventaja y
    hunde el retorno real muy por debajo del anunciado.
    """
    return round(min(fair * rtp, cap), 4)


# ---------------------------------------------------------------------------
# Volado — RTP 0.98
# ---------------------------------------------------------------------------
# Moneda JUSTA (50/50) que paga 1.96x en vez de 2x. La alternativa —pagar 2x
# con una moneda cargada al 49%— da el mismo margen pero seria mentir sobre el
# sorteo, y aqui el jugador puede recalcularlo con la semilla.

COINFLIP_RTP = 0.98
COINFLIP_SIDES = ("aguila", "sol")


def coinflip_new(server_seed: str, client_seed: str, options: dict) -> dict:
    pick = (options or {}).get("pick")
    if pick not in COINFLIP_SIDES:
        raise ValueError("bad_pick")
    stream = _byte_stream(server_seed, client_seed)
    result = COINFLIP_SIDES[_rand_below(stream, 2)]
    return _seeded(server_seed, client_seed, {"game": "coinflip", "pick": pick, "result": result})


def coinflip_public(state: dict) -> dict:
    return {"pick": state["pick"], "result": state["result"] if state.get("finished") else None}


def coinflip_apply(state: dict, action: str, payload: dict) -> tuple:
    state["finished"] = True
    won = state["pick"] == state["result"]
    mult = round(2 * COINFLIP_RTP, 4) if won else 0.0
    return state, True, ("win" if won else "lose"), mult, {"result": state["result"]}


# ---------------------------------------------------------------------------
# Dados — RTP 0.97
# ---------------------------------------------------------------------------
# Tiro uniforme 0-99. El jugador elige umbral y direccion; el pago sale de la
# probabilidad real de esa apuesta, asi que apostar "casi seguro" paga poco y
# "casi imposible" paga mucho, sin que la casa cambie de margen.

DICE_RTP = 0.97
DICE_MIN_TARGET = 4
DICE_MAX_TARGET = 96


def dice_new(server_seed: str, client_seed: str, options: dict) -> dict:
    target = (options or {}).get("target")
    direction = (options or {}).get("direction")
    if direction not in ("under", "over"):
        raise ValueError("bad_direction")
    try:
        target = int(target)
    except (TypeError, ValueError):
        raise ValueError("bad_target")
    if target < DICE_MIN_TARGET or target > DICE_MAX_TARGET:
        raise ValueError("bad_target")

    stream = _byte_stream(server_seed, client_seed)
    roll = _rand_below(stream, 100)
    return _seeded(server_seed, client_seed, {
        "game": "dice", "target": target, "direction": direction, "roll": roll,
    })


def dice_win_chance(target: int, direction: str) -> float:
    """under: gana con roll < target. over: gana con roll > target."""
    return (target / 100.0) if direction == "under" else ((99 - target) / 100.0)


def dice_public(state: dict) -> dict:
    chance = dice_win_chance(state["target"], state["direction"])
    return {
        "target": state["target"],
        "direction": state["direction"],
        "winChance": round(chance, 4),
        "payout": _step_multiplier(chance, DICE_RTP),
        "roll": state["roll"] if state.get("finished") else None,
    }


def dice_apply(state: dict, action: str, payload: dict) -> tuple:
    state["finished"] = True
    roll, target = state["roll"], state["target"]
    won = roll < target if state["direction"] == "under" else roll > target
    chance = dice_win_chance(target, state["direction"])
    mult = _step_multiplier(chance, DICE_RTP) if won else 0.0
    return state, True, ("win" if won else "lose"), mult, {"roll": roll}


# ---------------------------------------------------------------------------
# Ruleta de premios — RTP 0.96
# ---------------------------------------------------------------------------
# Rueda de 24 casillas con multiplicadores repetidos. Los pesos se eligieron
# para que la suma de (casillas/24 * multiplicador) de 0.96 exacto; el test de
# RTP lo comprueba en vez de confiar en el calculo a mano.

WHEEL_RTP = 0.96
WHEEL_MAX_MULT = 20.0
# 50 casillas que suman 48.00 -> RTP 0.9600 exacto.
#
# El premio mayor es 20x y NO 50x: con 50 casillas una sola de 50x ya aporta
# 1.00 al retorno, o sea mas que el RTP entero, y no quedaria nada para las
# demas. Un 50x honesto necesitaria 60+ casillas con casi todas en cero, que
# es una rueda peor. Se bajo el tope y se corrigio el catalogo.
WHEEL_SEGMENTS = (
    [0.0] * 32 + [1.0] * 10 + [2.0] * 5 + [4.0] * 2 + [20.0] * 1
)


def wheel_new(server_seed: str, client_seed: str, options: dict) -> dict:
    stream = _byte_stream(server_seed, client_seed)
    index = _rand_below(stream, len(WHEEL_SEGMENTS))
    return _seeded(server_seed, client_seed, {
        "game": "wheel", "index": index, "segments": WHEEL_SEGMENTS,
    })


def wheel_public(state: dict) -> dict:
    return {
        "segments": state["segments"],
        "index": state["index"] if state.get("finished") else None,
    }


def wheel_apply(state: dict, action: str, payload: dict) -> tuple:
    state["finished"] = True
    mult = float(WHEEL_SEGMENTS[state["index"]])
    return state, True, ("win" if mult > 0 else "lose"), mult, {
        "index": state["index"], "segment": mult,
    }


# ---------------------------------------------------------------------------
# Raspadito — RTP 0.94
# ---------------------------------------------------------------------------
# Se sortea PRIMERO el premio con una tabla de pesos y DESPUES se acomodan las
# nueve casillas para que cuenten esa historia. Al reves —generar casillas al
# azar y ver que sale— el RTP dependeria de coincidencias y seria imposible de
# fijar.

SCRATCH_RTP = 0.94
SCRATCH_SYMBOLS = ("🍒", "🔔", "⭐", "💎", "7️⃣", "🍀")
# (peso, multiplicador). Los pesos suman 1000.
# Pesos sobre 1000 que aportan 940 -> RTP 0.9400 exacto.
SCRATCH_TABLE = (
    (796, 0.0),
    (140, 2.0),
    (40, 5.0),
    (20, 12.0),
    (3, 40.0),
    (1, 100.0),
)


def _scratch_prize(stream) -> float:
    total = sum(w for w, _ in SCRATCH_TABLE)
    roll = _rand_below(stream, total)
    acc = 0
    for weight, mult in SCRATCH_TABLE:
        acc += weight
        if roll < acc:
            return mult
    return 0.0


def scratch_new(server_seed: str, client_seed: str, options: dict) -> dict:
    stream = _byte_stream(server_seed, client_seed)
    prize = _scratch_prize(stream)

    symbols = list(SCRATCH_SYMBOLS)
    if prize > 0:
        # Premio: tres iguales del simbolo que corresponde al escalon.
        idx = next(i for i, (_, m) in enumerate(SCRATCH_TABLE) if m == prize)
        win_symbol = symbols[min(idx, len(symbols) - 1)]
        others = [s for s in symbols if s != win_symbol]
        cells = [win_symbol] * 3
        # El resto NO puede formar otro trio: como mucho dos de cada uno.
        for i in range(6):
            cells.append(others[i % len(others)])
    else:
        # Sin premio: como mucho dos iguales en toda la carta.
        cells = []
        for i in range(9):
            cells.append(symbols[i % len(symbols)])
        cells = cells[:9]

    cells = shuffle(cells, server_seed, client_seed + ":cells")
    return _seeded(server_seed, client_seed, {
        "game": "scratch", "cells": cells, "prize": prize,
    })


def scratch_public(state: dict) -> dict:
    return {"cells": state["cells"] if state.get("finished") else None, "size": 9}


def scratch_apply(state: dict, action: str, payload: dict) -> tuple:
    state["finished"] = True
    mult = float(state["prize"])
    return state, True, ("win" if mult > 0 else "lose"), mult, {
        "cells": state["cells"], "prize": mult,
    }


# ---------------------------------------------------------------------------
# Mayor o Menor — RTP 0.96
# ---------------------------------------------------------------------------
# Baraja de 52 SIN reposicion: al ir saliendo cartas las probabilidades
# cambian, y el pago de cada paso se recalcula con las que quedan. Usar
# probabilidades fijas seria explotable contando cartas.

HL_RTP = 0.96
HL_RANKS = list(range(2, 15))   # 2..14 (14 = As)
HL_MAX_MULT = 20.0


def _hl_deck() -> list:
    return [r for r in HL_RANKS for _ in range(4)]


def hl_new(server_seed: str, client_seed: str, options: dict) -> dict:
    deck = shuffle(_hl_deck(), server_seed, client_seed)
    return _seeded(server_seed, client_seed, {
        "game": "higherlower",
        "deck": deck,
        "cursor": 1,
        "current": deck[0],
        "fair": 1.0,          # producto de 1/p, sin recortar
        "multiplier": 1.0,
        "streak": 0,
    })


def hl_chances(state: dict) -> tuple:
    """(p_mayor, p_menor) con las cartas que QUEDAN por salir."""
    rest = state["deck"][state["cursor"]:]
    if not rest:
        return 0.0, 0.0
    cur = state["current"]
    higher = sum(1 for r in rest if r > cur)
    lower = sum(1 for r in rest if r < cur)
    n = len(rest)
    return higher / n, lower / n


def hl_public(state: dict) -> dict:
    p_hi, p_lo = hl_chances(state)
    return {
        "current": state["current"],
        "multiplier": round(state["multiplier"], 4),
        "streak": state["streak"],
        "cardsLeft": len(state["deck"]) - state["cursor"],
        # Adonde subiria el acumulado si acierta, no el pago del paso suelto.
        "higherPays": _payout(state["fair"] / p_hi, HL_RTP, HL_MAX_MULT) if p_hi > 0 else 0.0,
        "lowerPays": _payout(state["fair"] / p_lo, HL_RTP, HL_MAX_MULT) if p_lo > 0 else 0.0,
        "canCashOut": state["streak"] > 0,
        "last": state.get("last"),
    }


def hl_apply(state: dict, action: str, payload: dict) -> tuple:
    if action == "cashout":
        if state["streak"] == 0:
            raise ValueError("nothing_to_cash_out")
        state["finished"] = True
        return state, True, "win", round(state["multiplier"], 4), {"streak": state["streak"]}

    if action not in ("higher", "lower"):
        raise ValueError("unknown_action")

    p_hi, p_lo = hl_chances(state)
    prob = p_hi if action == "higher" else p_lo
    if prob <= 0:
        # Apostar a algo imposible (mayor que un As) no se cobra: se rechaza.
        raise ValueError("impossible_bet")

    nxt = state["deck"][state["cursor"]]
    state["cursor"] += 1
    prev = state["current"]
    state["current"] = nxt
    state["last"] = {"from": prev, "to": nxt, "guess": action}

    won = nxt > prev if action == "higher" else nxt < prev
    if not won:
        # El empate tambien pierde; va dicho en las reglas de la pantalla.
        state["finished"] = True
        return state, True, "lose", 0.0, {"streak": state["streak"]}

    state["streak"] += 1
    state["fair"] = state["fair"] / prob
    state["multiplier"] = _payout(state["fair"], HL_RTP, HL_MAX_MULT)

    # Tope del catalogo: al alcanzarlo se liquida solo, no se puede seguir.
    if state["multiplier"] >= HL_MAX_MULT or state["cursor"] >= len(state["deck"]):
        state["finished"] = True
        return state, True, "win", min(state["multiplier"], HL_MAX_MULT), {"streak": state["streak"]}

    return state, False, None, None, None


# ---------------------------------------------------------------------------
# Minas — RTP 0.97
# ---------------------------------------------------------------------------
# 25 casillas, el jugador elige cuantas minas. Tras k destapadas seguras el
# pago justo es C(25,k)/C(25-m,k); recortado por el RTP da el multiplicador.

MINES_RTP = 0.97
MINES_TILES = 25
MINES_MIN = 1
MINES_MAX = 24
MINES_MAX_MULT = 24.0


def _comb(n: int, k: int) -> float:
    if k < 0 or k > n:
        return 0.0
    out = 1.0
    for i in range(k):
        out = out * (n - i) / (i + 1)
    return out


def mines_multiplier(mines: int, revealed: int) -> float:
    safe = MINES_TILES - mines
    if revealed <= 0 or revealed > safe:
        return 1.0
    fair = _comb(MINES_TILES, revealed) / _comb(safe, revealed)
    return round(min(fair * MINES_RTP, MINES_MAX_MULT), 4)


def mines_new(server_seed: str, client_seed: str, options: dict) -> dict:
    mines = (options or {}).get("mines", 3)
    try:
        mines = int(mines)
    except (TypeError, ValueError):
        raise ValueError("bad_mines")
    if mines < MINES_MIN or mines > MINES_MAX:
        raise ValueError("bad_mines")

    # Las minas quedan fijadas AL ABRIR, no al tocar: si se sortearan sobre la
    # marcha el servidor podria decidir a posteriori donde poner la que mata.
    board = shuffle(list(range(MINES_TILES)), server_seed, client_seed)
    return _seeded(server_seed, client_seed, {
        "game": "mines",
        "mines": mines,
        "mineTiles": sorted(board[:mines]),
        "revealed": [],
        "multiplier": 1.0,
    })


def mines_public(state: dict) -> dict:
    done = state.get("finished", False)
    revealed = state["revealed"]
    return {
        "tiles": MINES_TILES,
        "mines": state["mines"],
        "revealed": revealed,
        "multiplier": round(state["multiplier"], 4),
        "nextMultiplier": mines_multiplier(state["mines"], len(revealed) + 1),
        "canCashOut": len(revealed) > 0,
        # Las minas SOLO se revelan cuando la ronda termino.
        "mineTiles": state["mineTiles"] if done else None,
    }


def mines_apply(state: dict, action: str, payload: dict) -> tuple:
    if action == "cashout":
        if not state["revealed"]:
            raise ValueError("nothing_to_cash_out")
        state["finished"] = True
        return state, True, "win", round(state["multiplier"], 4), {
            "revealed": len(state["revealed"]), "mineTiles": state["mineTiles"],
        }

    if action != "reveal":
        raise ValueError("unknown_action")

    tile = (payload or {}).get("tile")
    try:
        tile = int(tile)
    except (TypeError, ValueError):
        raise ValueError("bad_tile")
    if tile < 0 or tile >= MINES_TILES or tile in state["revealed"]:
        raise ValueError("bad_tile")

    if tile in state["mineTiles"]:
        state["finished"] = True
        return state, True, "lose", 0.0, {
            "hitMine": tile, "mineTiles": state["mineTiles"],
        }

    state["revealed"].append(tile)
    state["multiplier"] = mines_multiplier(state["mines"], len(state["revealed"]))

    if len(state["revealed"]) >= MINES_TILES - state["mines"]:
        state["finished"] = True
        return state, True, "win", state["multiplier"], {
            "revealed": len(state["revealed"]), "mineTiles": state["mineTiles"],
        }

    return state, False, None, None, None


# ---------------------------------------------------------------------------
# Penales y Boliche — rachas con retiro
# ---------------------------------------------------------------------------
# Mismo motor, distinta probabilidad y distinto tope: en los dos el jugador
# repite un intento con probabilidad FIJA y se lleva el producto acumulado si
# se retira a tiempo. Se comparte el codigo porque la unica diferencia real es
# la tabla de constantes; duplicarlo seria dos sitios donde equivocarse.

PENALTY_RTP = 0.95
PENALTY_ZONES = 5          # el portero cubre una de cinco
PENALTY_MAX_MULT = 3.0

BOWLING_RTP = 0.95
BOWLING_STRIKE_CHANCE = 0.62
BOWLING_MAX_MULT = 10.0

_STREAK_GAMES = {
    "penalty": {
        "rtp": PENALTY_RTP,
        # El portero adivina 1 de 5: el tiro entra 4 de cada 5 veces.
        "prob": (PENALTY_ZONES - 1) / PENALTY_ZONES,
        "max_mult": PENALTY_MAX_MULT,
        "attempt": "kick",
        "zones": PENALTY_ZONES,
    },
    "bowling": {
        "rtp": BOWLING_RTP,
        "prob": BOWLING_STRIKE_CHANCE,
        "max_mult": BOWLING_MAX_MULT,
        "attempt": "roll",
        "zones": 0,
    },
}


def _streak_new(game: str):
    cfg = _STREAK_GAMES[game]

    def _new(server_seed: str, client_seed: str, options: dict) -> dict:
        return _seeded(server_seed, client_seed, {
            "game": game,
            "streak": 0,
            "fair": 1.0,          # producto de 1/p, sin recortar
            "multiplier": 1.0,
            "attempts": 0,
            "zones": cfg["zones"],
        })

    return _new


def _streak_public(game: str):
    cfg = _STREAK_GAMES[game]

    def _public(state: dict) -> dict:
        return {
            "streak": state["streak"],
            "multiplier": round(state["multiplier"], 4),
            "nextMultiplier": _payout(state["fair"] / cfg["prob"], cfg["rtp"], cfg["max_mult"]),
            "successChance": round(cfg["prob"], 4),
            "zones": cfg["zones"],
            "canCashOut": state["streak"] > 0,
            "last": state.get("last"),
        }

    return _public


def _streak_apply(game: str):
    cfg = _STREAK_GAMES[game]

    def _apply(state: dict, action: str, payload: dict) -> tuple:
        if action == "cashout":
            if state["streak"] == 0:
                raise ValueError("nothing_to_cash_out")
            state["finished"] = True
            return state, True, "win", round(state["multiplier"], 4), {"streak": state["streak"]}

        if action != cfg["attempt"]:
            raise ValueError("unknown_action")

        # Cada intento consume bytes NUEVOS del chorro (nonce = numero de
        # intento), asi que repetir la misma jugada no repite el resultado.
        stream = _byte_stream(state["_ss"], f"{state['_cs']}:{state['attempts']}")
        state["attempts"] += 1

        detail = {"streak": state["streak"]}

        if game == "penalty":
            # Duelo real: el tirador elige esquina, el portero elige lado, y
            # solo ataja si coinciden. Ofrecer la eleccion sin que influyera en
            # nada seria agencia de mentira. Con el portero uniforme la
            # probabilidad de gol es 1 - 1/zonas = la misma cfg["prob"], asi
            # que el RTP no cambia: cambia que la jugada sea de verdad.
            zone = (payload or {}).get("zone")
            try:
                zone = int(zone)
            except (TypeError, ValueError):
                raise ValueError("bad_zone")
            if zone < 0 or zone >= cfg["zones"]:
                raise ValueError("bad_zone")

            keeper = _rand_below(stream, cfg["zones"])
            success = keeper != zone
            state["last"] = {"keeper": keeper, "zone": zone, "scored": success}
            detail["keeper"] = keeper
            detail["zone"] = zone
        else:
            roll = _rand_below(stream, 10_000) / 10_000.0
            success = roll < cfg["prob"]
            state["last"] = {"strike": success}

        if not success:
            state["finished"] = True
            return state, True, "lose", 0.0, detail

        state["streak"] += 1
        state["fair"] = state["fair"] / cfg["prob"]
        state["multiplier"] = _payout(state["fair"], cfg["rtp"], cfg["max_mult"])

        if state["multiplier"] >= cfg["max_mult"]:
            state["finished"] = True
            return state, True, "win", cfg["max_mult"], {"streak": state["streak"]}

        return state, False, None, None, None

    return _apply


# ---------------------------------------------------------------------------
# Registro
# ---------------------------------------------------------------------------
# 'instant' marca los juegos de un solo tiro: el resultado ya quedo fijado por
# la semilla al abrir, asi que arcade_bet_sp los liquida en el mismo viaje y
# no dejan ronda abierta.

GAME_ENGINES = {
    "coinflip": {
        "new_round": coinflip_new, "public_state": coinflip_public,
        "apply": coinflip_apply, "actions": ("reveal",), "instant": True,
    },
    "dice": {
        "new_round": dice_new, "public_state": dice_public,
        "apply": dice_apply, "actions": ("reveal",), "instant": True,
    },
    "wheel": {
        "new_round": wheel_new, "public_state": wheel_public,
        "apply": wheel_apply, "actions": ("reveal",), "instant": True,
    },
    "scratch": {
        "new_round": scratch_new, "public_state": scratch_public,
        "apply": scratch_apply, "actions": ("reveal",), "instant": True,
    },
    "higherlower": {
        "new_round": hl_new, "public_state": hl_public,
        "apply": hl_apply, "actions": ("higher", "lower", "cashout"),
    },
    "mines": {
        "new_round": mines_new, "public_state": mines_public,
        "apply": mines_apply, "actions": ("reveal", "cashout"),
    },
    "penalty": {
        "new_round": _streak_new("penalty"), "public_state": _streak_public("penalty"),
        "apply": _streak_apply("penalty"), "actions": ("kick", "cashout"),
    },
    "bowling": {
        "new_round": _streak_new("bowling"), "public_state": _streak_public("bowling"),
        "apply": _streak_apply("bowling"), "actions": ("roll", "cashout"),
    },
}
