from fastapi import APIRouter
from modules.arcade import (
    arcade_games_all_sp, arcade_wallet_one_sp, arcade_daily_bonus_sp,
    arcade_bet_sp, arcade_action_sp, arcade_rounds_all_sp, arcade_transactions_all_sp,
    arcade_round_one_sp, arcade_live_wins_sp,
)

router = APIRouter()


@router.post(
    "/all_arcadeGames",
    summary="Catalogo del arcade",
    description="""
Los 10 mini-juegos de fichas virtuales para el dashboard. Los que traen
comingSoon = "1" se pintan bloqueados y sp_arcadeRounds_open los rechaza.

Body: { "arcadeGames": [{ "companyId": int, "isActive"?: "1" }] }
Returns: { "arcadeGames": ArcadeGame[] }
""",
)
def all_arcade_games(json: dict):
    return arcade_games_all_sp(json)


@router.post(
    "/one_arcadeWallet",
    summary="Monedero de fichas del jugador",
    description="""
Saldo, acumulados y limite diario. Crea el monedero con fichas de bienvenida
la primera vez que el jugador entra al arcade.

FICHAS, NO DINERO: este saldo no se canjea ni toca las rutas de pago reales.

Body: { "arcadeWallets": [{ "companyId": int, "clientId": int }] }
Returns: { "arcadeWallets": [ArcadeWallet] }
""",
)
def one_arcade_wallet(json: dict):
    return arcade_wallet_one_sp(json)


@router.post(
    "/arcade/dailyBonus",
    summary="Bono diario de fichas",
    description="""
Acredita el bono una vez cada 24 h. Si aun no toca, responde granted = false
con nextBonusAt en vez de error.

Body: { "arcadeWallets": [{ "companyId": int, "clientId": int }] }
Returns: { "granted": bool, "amount": int, "coinBalance": int, "nextBonusAt": str }
""",
)
def arcade_daily_bonus(json: dict):
    return arcade_daily_bonus_sp(json)


@router.post(
    "/arcade/bet",
    summary="Abrir ronda y apostar fichas",
    description="""
Debita la apuesta y abre la ronda de forma atomica. Devuelve serverSeedHash
(el compromiso de juego limpio, ANTES de jugar) y el estado visible del juego.

En blackjack la mano se reparte aqui; si sale un natural, la ronda se liquida
en la misma respuesta y llega con roundStatus = "settled".

Body: { "arcadeRounds": [{ "companyId": int, "clientId": int, "gameKey": str,
        "betAmount": int, "clientSeed"?: str }] }
Returns: { "roundId": int, "roundStatus": str, "serverSeedHash": str,
           "clientSeed": str, "nonce": int, "coinBalance": int, "state": object }

409 insufficient_coins / daily_limit / round_in_progress / wallet_locked
400 bad_bet / bet_out_of_range / game_unavailable
""",
)
def arcade_bet(json: dict):
    return arcade_bet_sp(json)


@router.post(
    "/arcade/action",
    summary="Jugar una accion sobre una ronda abierta",
    description="""
El cliente declara la INTENCION; el servidor resuelve con el estado que guardo
al abrir. Al liquidar revela serverSeed para que el jugador verifique el hash.

blackjack: action = "hit" | "stand" | "double"
mole:      action = "finish", payload = { "hits": [{ "i": int, "reactionMs": int }] }
           — cada golpe se valida contra el topo que de verdad existio; los
           inventados se descartan y se cuentan en result.rejectedHits.

Body: { "arcadeRounds": [{ "roundId": int, "clientId": int, "action": str,
        "payload"?: object }] }
Returns: { "roundStatus": str, "state": object, "result"?: object,
           "serverSeed"?: str, "coinBalance"?: int }

409 round_not_open   400 unknown_action / cannot_double / too_early
""",
)
def arcade_action(json: dict):
    return arcade_action_sp(json)


@router.post(
    "/one_arcadeRound",
    summary="Una ronda con su estado visible",
    description="""
Sirve para RETOMAR una ronda que quedo abierta (la app se fue a segundo plano
a media mano). Devuelve el estado ya recortado — nunca el zapato completo.

Body: { "arcadeRounds": [{ "roundId": int, "clientId": int }] }
Returns: { "arcadeRounds": [{ roundId, gameKey, betAmount, roundStatus, state, ... }] }
""",
)
def one_arcade_round(json: dict):
    return arcade_round_one_sp(json)


@router.post(
    "/all_arcadeRounds",
    summary="Historial de rondas del jugador",
    description="""
serverSeed solo viene en rondas liquidadas — revelarla con la ronda abierta
le entregaria la baraja al jugador.

Body: { "arcadeRounds": [{ "companyId": int, "clientId": int, "gameKey"?: str, "top"?: int }] }
Returns: { "arcadeRounds": ArcadeRound[] }
""",
)
def all_arcade_rounds(json: dict):
    return arcade_rounds_all_sp(json)


@router.post(
    "/arcade/liveWins",
    summary="Ganancias recientes (ticker del dashboard)",
    description="""
Rondas ganadoras recientes de la compania, ANONIMAS: no sale clientId ni
nombre. Es una app de prestamos y publicar quien juega revelaria algo que el
ticker no necesita.

Body: { "arcadeRounds": [{ "companyId": int, "top"?: int }] }   (top max 50)
Returns: { "arcadeRounds": [{ roundId, gameKey, gameName, betAmount,
           payoutAmount, multiplier, settledAt }] }
""",
)
def arcade_live_wins(json: dict):
    return arcade_live_wins_sp(json)


@router.post(
    "/all_arcadeTransactions",
    summary="Libro mayor de fichas del jugador",
    description="""
Body: { "arcadeTransactions": [{ "companyId": int, "clientId": int, "top"?: int }] }
Returns: { "arcadeTransactions": ArcadeTransaction[] }
""",
)
def all_arcade_transactions(json: dict):
    return arcade_transactions_all_sp(json)
