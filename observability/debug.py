"""
Opt-in debug tracing for the observability layer itself.

Silent unless the env var OBS_DEBUG=1 is set. Lets you watch trace ids and log
rows flow through the middleware/writer before the DB side is deployed. Off by
default → no production noise, no perf cost.
"""

import os

DEBUG = os.getenv("OBS_DEBUG") == "1"


def dbg(*args) -> None:
    if not DEBUG:
        return
    try:
        print("[obs]", *args, flush=True)
    except Exception:
        pass
