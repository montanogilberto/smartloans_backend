"""
arcadeFair — primitivas de juego limpio (provably fair).

Vive aparte de arcade.py para ROMPER EL CICLO de imports: arcadeGames.py
necesita el chorro de bytes y la barajada, y arcade.py necesita el registro de
motores de arcadeGames. Con las primitivas aqui, los dos importan de este
modulo y ninguno del otro.

El ciclo no era teorico: `except ImportError` lo tragaba y, segun quien se
cargara primero, los ocho juegos extra simplemente no quedaban registrados.
"""

import hashlib
import hmac
import secrets


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


