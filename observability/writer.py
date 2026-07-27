"""
Log write path.

Tiered by durability:
  * enqueue(log)   — best-effort. Workflow / application / integration logs go
                     onto an in-memory queue drained by a background daemon
                     thread that batch-inserts via sp_observability_logBatch.
                     Uses ONE persistent pymssql connection to avoid the
                     per-call connect churn (databases.connection() has no pool).
  * write_now(log) — durable. Audit + SECURITY events are inserted synchronously
                     via their single-row SP before the caller continues.

Hard rule: logging must NEVER raise into the request path. Every failure here is
swallowed and counted (`dropped`), never propagated.
"""

from __future__ import annotations

import json
import queue
import threading
import time
from typing import Optional

from databases import connection

_QUEUE_MAXSIZE = 10_000
_BATCH_SIZE = 100
_FLUSH_INTERVAL_SEC = 2.0

_SP_BY_TYPE = {
    "workflow": "sp_workflowLog",
    "audit": "sp_auditLog",
    "application": "sp_applicationLog",
    "integration": "sp_integrationLog",
}


class _Writer:
    def __init__(self) -> None:
        self._q: "queue.Queue[dict]" = queue.Queue(maxsize=_QUEUE_MAXSIZE)
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._conn = None
        self.dropped = 0

    # ── lifecycle ──────────────────────────────────────────────────────────
    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="obs-writer", daemon=True)
        self._thread.start()

    def flush_and_stop(self, timeout: float = 5.0) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=timeout)
        self._close_conn()

    # ── best-effort path ───────────────────────────────────────────────────
    def enqueue(self, log: dict) -> None:
        try:
            self._q.put_nowait(log)
        except queue.Full:
            self.dropped += 1  # shed load rather than block a request

    # ── durable path ───────────────────────────────────────────────────────
    def write_now(self, log_type: str, log: dict) -> None:
        sp = _SP_BY_TYPE.get(log_type)
        if not sp:
            return
        conn = None
        try:
            conn = connection()
            cur = conn.cursor()
            cur.execute(
                f"EXEC [dbo].[{sp}] @pjsonfile = %s",
                (json.dumps({"logs": [log]}, default=str),),
            )
            try:
                cur.fetchone()
            except Exception:
                pass
        except Exception:
            self.dropped += 1
        finally:
            if conn:
                try:
                    conn.close()
                except Exception:
                    pass

    # ── background worker ──────────────────────────────────────────────────
    def _run(self) -> None:
        while not self._stop.is_set():
            batch = self._drain(_BATCH_SIZE, _FLUSH_INTERVAL_SEC)
            if batch:
                self._write_batch(batch)
        # final drain on shutdown
        remaining = self._drain(_QUEUE_MAXSIZE, 0.0)
        if remaining:
            self._write_batch(remaining)

    def _drain(self, max_items: int, max_wait: float) -> list:
        batch: list = []
        deadline = time.monotonic() + max_wait
        while len(batch) < max_items:
            timeout = max(0.0, deadline - time.monotonic())
            try:
                batch.append(self._q.get(timeout=timeout if max_wait else 0.05))
            except queue.Empty:
                break
        return batch

    def _ensure_conn(self):
        if self._conn is None:
            self._conn = connection()
        return self._conn

    def _close_conn(self) -> None:
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
            self._conn = None

    def _write_batch(self, batch: list) -> None:
        payload = json.dumps({"logs": batch}, default=str)
        for attempt in (1, 2):  # one reconnect retry
            try:
                conn = self._ensure_conn()
                cur = conn.cursor()
                cur.execute(
                    "EXEC [dbo].[sp_observability_logBatch] @pjsonfile = %s",
                    (payload,),
                )
                try:
                    cur.fetchone()
                except Exception:
                    pass
                return
            except Exception:
                self._close_conn()  # force reconnect next attempt
                if attempt == 2:
                    self.dropped += len(batch)


writer = _Writer()
