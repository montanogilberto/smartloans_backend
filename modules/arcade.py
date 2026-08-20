"""
arcade — mini-juegos de apuesta con FICHAS VIRTUALES (house-banked).

FICHAS, NO DINERO. El saldo vive en arcadeWallets y no toca
walletTransactions, Stripe ni SPEI: no hay ruta de canje. Esa
separacion es deliberada — es lo que mantiene al modulo fuera del
permiso SEGOB de la Ley Federal de Juegos y Sorteos. Abrir el canje
seria un cambio regulatorio, no una feature.

EL SERVIDOR ES LA AUTORIDAD. El cliente nunca reporta un resultado,
solo una intencion: "pido carta", "pegue al topo 3 a los 412 ms".
La baraja y el calendario de topos se derivan aqui de la semilla y
viven en arcadeRounds.stateJson; el navegador solo recibe la vista
recortada que le toca ver.

JUEGO LIMPIO (provably fair). Al abrir la ronda el jugador recibe
serverSeedHash = SHA256(serverSeed) y aporta su clientSeed; al
liquidar se revela serverSeed y puede comprobar el hash. Como cada
ronda estrena serverSeed, el nonce es solo contador de auditoria y
no entra en la derivacion.
"""

import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone

from fastapi.responses import JSONResponse

from databases import connection
from observability import log_audit, log_workflow_step

# El arcade NO es "money_trail": son fichas. Se le da su propio flujo
# para que las consultas de dinero real no se contaminen con juego.
WORKFLOW = "arcade"


def _conn():
    return connection()


# ---------------------------------------------------------------------------
# Motor de juego limpio (provably fair)
# ---------------------------------------------------------------------------

def new_server_seed() -> str:
    """32 bytes de entropia criptografica en hex (64 chars)."""
    return secrets.token_hex(32)


def seed_hash(server_seed: str) -> str:
    """El compromiso que ve el jugador ANTES de jugar."""
    return hashlib.sha256(server_seed.encode()).hexdigest()


def _byte_stream(server_seed: str, client_seed: str):
    """
    Chorro determinista e ilimitado de bytes: HMAC-SHA256(serverSeed, clientSeed:n)
    concatenado sobre n. Mismas semillas -> misma secuencia, que es justo lo que
    permite al jugador re-derivar la partida y auditarla.
    """
    counter = 0
    while True:
        block = hmac.new(
            server_seed.encode(),
            f"{client_seed}:{counter}".encode(),
            hashlib.sha256,
        ).digest()
        for byte in block:
            yield byte
        counter += 1


def _rand_below(stream, n: int) -> int:
    """
    Entero uniforme en [0, n) por muestreo con rechazo.
    El `% n` directo sobre 32 bits sesga los valores bajos: con n=52 el sesgo es
    minusculo pero real, y en un juego con ventaja de casa declarada no se vale
    meter un sesgo que nadie audito.
    """
    if n <= 1:
        return 0
    limit = (2 ** 32 // n) * n
    while True:
        value = int.from_bytes(bytes(next(stream) for _ in range(4)), "big")
        if value < limit:
            return value % n


def shuffle(items: list, server_seed: str, client_seed: str) -> list:
    """Fisher-Yates con el chorro de la semilla — barajada reproducible y sin sesgo."""
    stream = _byte_stream(server_seed, client_seed)
    deck = list(items)
    for i in range(len(deck) - 1, 0, -1):
        j = _rand_below(stream, i + 1)
        deck[i], deck[j] = deck[j], deck[i]
    return deck


def verify_round(server_seed: str, server_seed_hash: str) -> bool:
    """Lo mismo que puede correr el jugador con los datos que le devolvimos."""
    return hmac.compare_digest(seed_hash(server_seed), server_seed_hash)


# ---------------------------------------------------------------------------
# Blackjack — 6 barajas, crupier se planta en 17 (incluido soft 17),
# blackjack paga 3:2, doblar permitido con dos cartas. Sin split todavia.
# Con estrategia basica eso da ~99.5% de RTP, el valor sembrado en arcadeGames.
# ---------------------------------------------------------------------------

BJ_DECKS = 6
BJ_RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
BJ_SUITS = ["S", "H", "D", "C"]
BJ_BLACKJACK_PAYS = 1.5


def _bj_shoe() -> list:
    return [f"{rank}{suit}" for _ in range(BJ_DECKS) for suit in BJ_SUITS for rank in BJ_RANKS]


def bj_hand_value(hand: list) -> tuple:
    """(mejor total, es_blanda). El As vale 11 mientras no pase de 21."""
    total, aces = 0, 0
    for card in hand:
        rank = card[:-1]
        if rank == "A":
            total += 11
            aces += 1
        elif rank in ("10", "J", "Q", "K"):
            total += 10
        else:
            total += int(rank)
    while total > 21 and aces:
        total -= 10
        aces -= 1
    return total, aces > 0


def _bj_is_blackjack(hand: list) -> bool:
    return len(hand) == 2 and bj_hand_value(hand)[0] == 21


def bj_new_round(server_seed: str, client_seed: str) -> dict:
    """
    Reparte la mano inicial. El zapato COMPLETO queda en el estado del servidor;
    el jugador solo vera su mano y la carta destapada del crupier.
    """
    shoe = shuffle(_bj_shoe(), server_seed, client_seed)
    player = [shoe[0], shoe[2]]
    dealer = [shoe[1], shoe[3]]
    return {
        "game": "blackjack",
        "shoe": shoe,
        "cursor": 4,          # siguiente carta a repartir
        "player": player,
        "dealer": dealer,
        "doubled": False,
        "finished": False,
    }


def bj_public_state(state: dict) -> dict:
    """Lo que puede ver el navegador. Nunca el zapato ni la carta tapada."""
    player_total, player_soft = bj_hand_value(state["player"])
    finished = state.get("finished", False)
    dealer = state["dealer"] if finished else state["dealer"][:1]
    dealer_total = bj_hand_value(dealer)[0]
    return {
        "player": state["player"],
        "playerTotal": player_total,
        "playerSoft": player_soft,
        "dealer": dealer,
        "dealerTotal": dealer_total,
        "dealerHidden": not finished,
        "doubled": state.get("doubled", False),
        "canHit": not finished and player_total < 21,
        "canDouble": not finished and len(state["player"]) == 2 and not state.get("doubled", False),
        "cardsLeft": len(state["shoe"]) - state["cursor"],
    }


def _bj_draw(state: dict) -> str:
    card = state["shoe"][state["cursor"]]
    state["cursor"] += 1
    return card


def _bj_dealer_play(state: dict) -> None:
    """El crupier pide hasta 17 duro o blando."""
    while bj_hand_value(state["dealer"])[0] < 17:
        state["dealer"].append(_bj_draw(state))


def _bj_resolve(state: dict) -> tuple:
    """
    (outcome, multiplicador sobre la apuesta ORIGINAL).
    El multiplicador es RETORNO TOTAL: perder=0, empate=1, ganar=2, blackjack=2.5.
    Doblar duplica la exposicion, asi que la escala se duplica tambien (ganar
    doblado = 4.0). La segunda apuesta se cobra en sp_arcadeRounds_double antes
    de aplicar la jugada; si no se cobrara, doblar seria dinero gratis.
    """
    stake = 2.0 if state.get("doubled") else 1.0
    player = bj_hand_value(state["player"])[0]
    dealer = bj_hand_value(state["dealer"])[0]

    if _bj_is_blackjack(state["player"]) and not _bj_is_blackjack(state["dealer"]):
        return "blackjack", 1.0 + BJ_BLACKJACK_PAYS
    if player > 21:
        return "lose", 0.0
    if dealer > 21 or player > dealer:
        return "win", 2.0 * stake
    if player < dealer:
        return "lose", 0.0
    return "push", 1.0 * stake


def bj_apply(state: dict, action: str) -> tuple:
    """
    Aplica una accion del jugador. Devuelve (state, finished, outcome, multiplier).
    Si la mano sigue viva, outcome/multiplier vienen en None.
    """
    if state.get("finished"):
        raise ValueError("round_finished")

    if action == "deal":
        # Blackjack natural de cualquiera de los dos cierra la mano de inmediato.
        if _bj_is_blackjack(state["player"]) or _bj_is_blackjack(state["dealer"]):
            state["finished"] = True
            outcome, multiplier = _bj_resolve(state)
            return state, True, outcome, multiplier
        return state, False, None, None

    if action == "hit":
        state["player"].append(_bj_draw(state))
        if bj_hand_value(state["player"])[0] > 21:
            state["finished"] = True
            return state, True, "lose", 0.0
        return state, False, None, None

    if action == "double":
        if len(state["player"]) != 2 or state.get("doubled"):
            raise ValueError("cannot_double")
        state["doubled"] = True
        state["player"].append(_bj_draw(state))
        state["finished"] = True
        if bj_hand_value(state["player"])[0] > 21:
            return state, True, "lose", 0.0
        _bj_dealer_play(state)
        outcome, multiplier = _bj_resolve(state)
        return state, True, outcome, multiplier

    if action == "stand":
        state["finished"] = True
        _bj_dealer_play(state)
        outcome, multiplier = _bj_resolve(state)
        return state, True, outcome, multiplier

    raise ValueError("unknown_action")


# ---------------------------------------------------------------------------
# Atrapa al Topo — reflejos, pago en escalera por aciertos
# ---------------------------------------------------------------------------
# El calendario de topos se deriva de la semilla ANTES de jugar y se guarda en
# el servidor. Por eso el navegador no puede inventar aciertos: cada golpe se
# valida contra el topo que de verdad existio, en la ventana en la que estuvo
# fuera. Sin este calendario, "atrape 24 de 24" seria una linea de consola.
# ---------------------------------------------------------------------------

MOLE_ROUND_MS = 20_000
MOLE_SPAWNS = 24
MOLE_HOLES = 9
MOLE_UP_MS_START = 1_100      # al inicio el topo se queda mucho fuera
MOLE_UP_MS_END = 620          # al final apenas asoma
MOLE_MIN_REACTION_MS = 120    # por debajo de esto no hay reflejo humano, hay script

# Escalera de pago sobre 24 topos: (aciertos minimos, multiplicador de retorno).
# CALIBRACION INICIAL, no verdad revelada: el RTP real de un juego de habilidad
# depende de que tan bien juega la gente, y eso no se sabe hasta tener rondas.
# Para retunearlo: SELECT SUM(payoutAmount)*1.0/SUM(betAmount) FROM arcadeRounds
# WHERE gameKey='mole' AND roundStatus='settled', y mover la escalera hasta que
# se acerque al rtp sembrado en arcadeGames (0.96).
MOLE_PAYOUT_LADDER = [
    (24, 5.0),
    (23, 4.0),
    (22, 3.0),
    (21, 2.5),
    (19, 2.0),
    (17, 1.5),
    (15, 1.0),
    (12, 0.5),
]


def mole_new_round(server_seed: str, client_seed: str) -> dict:
    """
    Calendario de topos derivado de la semilla: cuando sale cada uno, de que
    hoyo y cuanto aguanta. Dos topos nunca comparten hoyo al mismo tiempo
    porque salen en serie, uno tras otro.
    """
    stream = _byte_stream(server_seed, client_seed)
    gap = MOLE_ROUND_MS // MOLE_SPAWNS
    spawns = []
    last_hole = -1
    for i in range(MOLE_SPAWNS):
        # El topo nunca repite hoyo consecutivo: repetir se ve a bug, no a juego.
        hole = _rand_below(stream, MOLE_HOLES - 1)
        if hole >= last_hole:
            hole += 1
        last_hole = hole

        progress = i / max(MOLE_SPAWNS - 1, 1)
        up_ms = int(MOLE_UP_MS_START + (MOLE_UP_MS_END - MOLE_UP_MS_START) * progress)
        jitter = _rand_below(stream, gap // 3)
        spawns.append({
            "i": i,
            "hole": hole,
            "atMs": i * gap + jitter,
            "upMs": up_ms,
        })
    return {
        "game": "mole",
        "roundMs": MOLE_ROUND_MS,
        "holes": MOLE_HOLES,
        "spawns": spawns,
        "finished": False,
    }


def mole_public_state(state: dict) -> dict:
    """
    El calendario SI se le entrega al navegador — tiene que dibujar los topos.
    Eso no rompe nada: el jugador ya sabe donde sale el topo cuando lo ve. Lo
    que no puede es fabricar el golpe, y de eso se encarga mole_settle.
    """
    return {
        "roundMs": state["roundMs"],
        "holes": state["holes"],
        "spawns": state["spawns"],
        "totalSpawns": len(state["spawns"]),
    }


def mole_settle(state: dict, hits: list) -> tuple:
    """
    Valida los golpes reportados y devuelve (aciertos, multiplicador, detalle).

    Un golpe cuenta solo si: apunta a un topo que existio, no repite topo ya
    contado, y su tiempo de reaccion cae dentro de la ventana en que el topo
    estuvo fuera y por encima del piso humano. Lo demas se descarta en silencio
    y aparece en el detalle para poder auditar despues quien intento que.
    """
    by_index = {spawn["i"]: spawn for spawn in state["spawns"]}
    counted, rejected = set(), 0

    for hit in hits or []:
        if not isinstance(hit, dict):
            rejected += 1
            continue
        index = hit.get("i")
        reaction = hit.get("reactionMs")
        spawn = by_index.get(index)
        if spawn is None or index in counted:
            rejected += 1
            continue
        if not isinstance(reaction, (int, float)):
            rejected += 1
            continue
        if reaction < MOLE_MIN_REACTION_MS or reaction > spawn["upMs"]:
            rejected += 1
            continue
        counted.add(index)

    score = len(counted)
    multiplier = 0.0
    for threshold, payout in MOLE_PAYOUT_LADDER:
        if score >= threshold:
            multiplier = payout
            break

    return score, multiplier, {
        "score": score,
        "totalSpawns": len(state["spawns"]),
        "rejectedHits": rejected,
        "hitRate": round(score / max(len(state["spawns"]), 1), 3),
    }


# ---------------------------------------------------------------------------
# Registro de motores — agregar un juego es agregar una entrada aqui
# ---------------------------------------------------------------------------
# Los ocho juegos que salen con comingSoon='1' en el catalogo aterrizan en este
# diccionario: mientras no tengan motor, sp_arcadeRounds_open ya los rechaza
# con game_unavailable, asi que no hay forma de apostarles por accidente.
ENGINES = {
    "blackjack": {
        "new_round": bj_new_round,
        "public_state": bj_public_state,
        "actions": ("hit", "stand", "double"),
    },
    "mole": {
        "new_round": mole_new_round,
        "public_state": mole_public_state,
        "actions": ("finish",),
    },
}

# Codigos que devuelven las SPs cuando la jugada es invalida por reglas de
# negocio, no por una falla del servidor. 409 y no 500: el cliente puede
# corregir y reintentar.
_CONFLICT_ERRORS = {
    "insufficient_coins", "daily_limit", "round_in_progress", "wallet_locked",
    "round_not_open", "no_wallet",
}
_BAD_REQUEST_ERRORS = {
    "bad_bet", "bet_out_of_range", "unknown_game", "game_unavailable",
    "missing_identity", "unknown_action", "cannot_double", "too_early",
}


def _exec_sp(sp_name: str, payload: dict) -> dict:
    """Ejecuta una SP @pjsonfile y devuelve su jsonResult ya parseado."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{sp_name}] @pjsonfile = %s", (json.dumps(payload),))
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    finally:
        if conn:
            conn.close()


def _error_response(data: dict) -> JSONResponse:
    code = data.get("error")
    if code in _CONFLICT_ERRORS:
        status = 409
    elif code in _BAD_REQUEST_ERRORS:
        status = 400
    else:
        status = 500
    return JSONResponse(content=data, status_code=status)


def _first(json_file: dict, key: str) -> dict:
    items = json_file.get(key) or [{}]
    return items[0] if isinstance(items, list) and items else {}


def _game_row(game_key: str) -> dict:
    """Renglon del catalogo — de ahi salen los limites y el tope de pago."""
    data = _exec_sp("sp_arcadeGames_all", {"arcadeGames": [{}]})
    for game in data.get("arcadeGames", []):
        if game.get("gameKey") == game_key:
            return game
    return {}


def _payout_for(bet: int, multiplier: float, game: dict) -> int:
    """
    Retorno TOTAL en fichas, acotado por el maxMultiplier del catalogo.
    El tope es un cinturon de seguridad, no decoracion: si un motor sale con un
    multiplicador absurdo por un bug, la casa pierde el tope y no el banco.
    """
    cap = float(game.get("maxMultiplier") or 0) or multiplier
    return int(round(bet * min(multiplier, cap)))


# ---------------------------------------------------------------------------
# Lecturas
# ---------------------------------------------------------------------------

def arcade_games_all_sp(json_file: dict):
    """Catalogo de los 10 juegos para el dashboard."""
    try:
        data = _exec_sp("sp_arcadeGames_all", json_file)
        if "error" in data:
            return _error_response(data)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_wallet_one_sp(json_file: dict):
    """Monedero del jugador; lo crea con fichas de bienvenida si es su primera vez."""
    try:
        data = _exec_sp("sp_arcadeWallets_one", json_file)
        if "error" in data:
            return _error_response(data)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_daily_bonus_sp(json_file: dict):
    """Bono diario de fichas, una vez cada 24 h."""
    try:
        data = _exec_sp("sp_arcadeWallets_dailyBonus", json_file)
        if "error" in data:
            return _error_response(data)
        if data.get("granted"):
            log_workflow_step(
                "Arcade Daily Bonus", workflow_name=WORKFLOW, action="daily_bonus",
                entity="arcadeWallets", message=f"+{data.get('amount')} fichas",
            )
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_round_one_sp(json_file: dict):
    """
    Una ronda con su estado YA RECORTADO para el jugador.

    Existe para poder RETOMAR: si la app se va a segundo plano a media mano, la
    ronda queda abierta y sp_arcadeRounds_open rechaza la siguiente con
    round_in_progress. Sin esta lectura el jugador se quedaba encerrado fuera
    del juego para siempre. Nunca devuelve stateJson crudo — ahi va el zapato.
    """
    try:
        data = _exec_sp("sp_arcadeRounds_one", json_file)
        if "error" in data:
            return _error_response(data)

        rounds = data.get("arcadeRounds") or []
        if not rounds:
            return JSONResponse(content={"arcadeRounds": []}, status_code=200)

        row = rounds[0]
        engine = ENGINES.get(row.get("gameKey"))
        state = row.get("state") or {}
        return JSONResponse(content={"arcadeRounds": [{
            "roundId": row["roundId"],
            "gameKey": row["gameKey"],
            "betAmount": row["betAmount"],
            "roundStatus": row["roundStatus"],
            "serverSeedHash": row.get("serverSeedHash"),
            "serverSeed": row.get("serverSeed"),
            "clientSeed": row.get("clientSeed"),
            "nonce": row.get("nonce"),
            "state": engine["public_state"](state) if engine and state else None,
        }]}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_rounds_all_sp(json_file: dict):
    """Historial de rondas del jugador."""
    try:
        data = _exec_sp("sp_arcadeRounds_all", json_file)
        if "error" in data:
            return _error_response(data)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_transactions_all_sp(json_file: dict):
    """Libro mayor de fichas del jugador."""
    try:
        data = _exec_sp("sp_arcadeTransactions_all", json_file)
        if "error" in data:
            return _error_response(data)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------------------------
# Apuesta y jugada
# ---------------------------------------------------------------------------

def _parse_utc(value: str):
    """
    CONVERT(..., 127) sobre datetime2 entrega 7 decimales y sin sufijo de zona;
    fromisoformat solo aguanta 6, y el valor es UTC aunque no lo diga.
    """
    if not value:
        return None
    text = value.rstrip("Z")
    if "." in text:
        head, frac = text.split(".", 1)
        text = f"{head}.{frac[:6]}"
    try:
        return datetime.fromisoformat(text).replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _settle_round(round_row: dict, state: dict, outcome: str, multiplier: float,
                  game: dict, detail: dict | None = None):
    """Liquida en la base y arma la respuesta que revela la semilla."""
    bet = int(round_row["betAmount"])
    payout = _payout_for(bet, multiplier, game)

    settled = _exec_sp("sp_arcadeRounds_settle", {"arcadeRounds": [{
        "roundId": round_row["roundId"],
        "clientId": round_row["clientId"],
        "payoutAmount": payout,
        "outcome": outcome,
        "state": state,
        "result": {"outcome": outcome, "multiplier": multiplier, **(detail or {})},
    }]})
    if "error" in settled:
        return _error_response(settled)

    log_workflow_step(
        "Arcade Round Settled", workflow_name=WORKFLOW, action=round_row["gameKey"],
        entity="arcadeRounds", entity_id=round_row["roundId"],
        message=f"{outcome} x{multiplier} — apuesta {bet}, pago {payout} fichas",
    )
    log_audit(
        "arcadeRounds", round_row["roundId"], "roundStatus", "open", "settled",
        action="SETTLE",
    )

    engine = ENGINES[round_row["gameKey"]]
    return JSONResponse(content={
        "roundStatus": "settled",
        "state": engine["public_state"](state),
        "result": {
            "outcome": outcome,
            "multiplier": multiplier,
            "betAmount": bet,
            "payoutAmount": payout,
            "netAmount": payout - bet,
            **(detail or {}),
        },
        # Se revela AQUI y solo aqui: con esto el jugador comprueba que
        # SHA256(serverSeed) es el hash que le dimos antes de repartir.
        "serverSeed": settled.get("serverSeed"),
        "serverSeedHash": settled.get("serverSeedHash"),
        "clientSeed": settled.get("clientSeed"),
        "nonce": settled.get("nonce"),
        "coinBalance": settled.get("coinBalance"),
    }, status_code=200)


def arcade_bet_sp(json_file: dict):
    """
    Abre una ronda: deriva la partida de la semilla, debita la apuesta de forma
    atomica y devuelve el compromiso de juego limpio con el estado visible.
    """
    try:
        body = _first(json_file, "arcadeRounds")
        game_key = body.get("gameKey")
        engine = ENGINES.get(game_key)
        if engine is None:
            return _error_response({
                "error": "game_unavailable",
                "message": "Ese juego todavia no esta disponible",
            })

        game = _game_row(game_key)
        if not game:
            return _error_response({"error": "unknown_game", "message": "Ese juego no existe"})

        server_seed = new_server_seed()
        client_seed = (body.get("clientSeed") or secrets.token_hex(8))[:64]
        state = engine["new_round"](server_seed, client_seed)

        opened = _exec_sp("sp_arcadeRounds_open", {"arcadeRounds": [{
            "companyId": body.get("companyId"),
            "clientId": body.get("clientId"),
            "gameKey": game_key,
            "betAmount": body.get("betAmount"),
            "serverSeedHash": seed_hash(server_seed),
            "serverSeed": server_seed,
            "clientSeed": client_seed,
            "state": state,
        }]})
        if "error" in opened:
            return _error_response(opened)

        round_row = {
            "roundId": opened["roundId"],
            "clientId": body.get("clientId"),
            "gameKey": game_key,
            "betAmount": int(body.get("betAmount")),
        }

        log_workflow_step(
            "Arcade Round Opened", workflow_name=WORKFLOW, action=game_key,
            entity="arcadeRounds", entity_id=opened["roundId"],
            message=f"apuesta {round_row['betAmount']} fichas",
        )

        # Blackjack se reparte al abrir, asi que un natural cierra la mano sin
        # que el jugador toque nada — se liquida en el mismo viaje.
        if game_key == "blackjack":
            state, finished, outcome, multiplier = bj_apply(state, "deal")
            if finished:
                return _settle_round(round_row, state, outcome, multiplier, game)

        return JSONResponse(content={
            "roundId": opened["roundId"],
            "roundStatus": "open",
            "serverSeedHash": opened["serverSeedHash"],
            "clientSeed": client_seed,
            "nonce": opened["nonce"],
            "coinBalance": opened["coinBalance"],
            "betAmount": round_row["betAmount"],
            "state": engine["public_state"](state),
        }, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_action_sp(json_file: dict):
    """
    Aplica una jugada sobre una ronda abierta. El cliente declara la INTENCION;
    el resultado lo calcula el servidor con el estado que guardo al abrir.
    """
    try:
        body = _first(json_file, "arcadeRounds")
        round_id = body.get("roundId")
        client_id = body.get("clientId")
        action = body.get("action")
        payload = body.get("payload") or {}

        found = _exec_sp("sp_arcadeRounds_one", {"arcadeRounds": [{
            "roundId": round_id, "clientId": client_id,
        }]})
        if "error" in found:
            return _error_response(found)

        rounds = found.get("arcadeRounds") or []
        if not rounds:
            return _error_response({"error": "round_not_open", "message": "Ronda no encontrada"})

        row = rounds[0]
        if row.get("roundStatus") != "open":
            return _error_response({"error": "round_not_open", "message": "Esa ronda ya fue liquidada"})

        game_key = row["gameKey"]
        engine = ENGINES.get(game_key)
        if engine is None or action not in engine["actions"]:
            return _error_response({"error": "unknown_action", "message": "Jugada no valida para este juego"})

        state = row.get("state") or {}
        game = _game_row(game_key)
        round_row = {
            "roundId": row["roundId"],
            "clientId": row["clientId"],
            "gameKey": game_key,
            "betAmount": int(row["betAmount"]),
        }

        if game_key == "blackjack":
            # Doblar cobra una SEGUNDA apuesta. El orden importa: primero se
            # comprueba que la jugada sea LEGAL y solo despues se cobra — al
            # reves, un doble invalido (mano de 3 cartas, o doblar dos veces)
            # dejaria al jugador cobrado por algo que nunca ocurrio.
            if action == "double":
                if len(state.get("player") or []) != 2 or state.get("doubled"):
                    return _error_response({
                        "error": "cannot_double",
                        "message": "Solo puedes doblar con tus dos primeras cartas",
                    })
                charged = _exec_sp("sp_arcadeRounds_double", {"arcadeRounds": [{
                    "roundId": round_id, "clientId": client_id,
                }]})
                if "error" in charged:
                    return _error_response(charged)

            try:
                state, finished, outcome, multiplier = bj_apply(state, action)
            except ValueError as err:
                return _error_response({"error": str(err), "message": "Jugada no valida"})

            if finished:
                return _settle_round(round_row, state, outcome, multiplier, game)

            saved = _exec_sp("sp_arcadeRounds_state", {"arcadeRounds": [{
                "roundId": round_id, "clientId": client_id, "state": state,
            }]})
            if "error" in saved:
                return _error_response(saved)
            return JSONResponse(content={
                "roundStatus": "open",
                "state": engine["public_state"](state),
            }, status_code=200)

        if game_key == "mole":
            # Una ronda de topos dura 20 s de reloj. Si la liquidacion llega
            # antes, nadie jugo: el cliente mando el marcador sin esperar.
            opened_at = _parse_utc(row.get("created_At"))
            if opened_at is not None:
                elapsed = datetime.now(timezone.utc) - opened_at
                if elapsed < timedelta(milliseconds=MOLE_ROUND_MS * 0.8):
                    return _error_response({
                        "error": "too_early",
                        "message": "La ronda todavia no termina",
                    })

            score, multiplier, detail = mole_settle(state, payload.get("hits"))
            state["finished"] = True
            outcome = "win" if multiplier > 0 else "lose"
            return _settle_round(round_row, state, outcome, multiplier, game, detail)

        return _error_response({"error": "unknown_action", "message": "Juego sin motor"})
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
