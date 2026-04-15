"""
SECCION9 LITE — Audit Log (Stateless)
In-memory ring buffer. No SQLite.
"""

import time
import logging
import threading
from collections import deque

logger = logging.getLogger("seccion9")

_MAX_ENTRIES = 2000
_log: deque = deque(maxlen=_MAX_ENTRIES)
_lock = threading.Lock()
_counter = 0


def init_db():
    logger.info("Audit log: in-memory mode")


def log_action(username: str, role: str, action: str, target: str = "", details: str = "", client_ip: str = ""):
    global _counter
    with _lock:
        _counter += 1
        _log.append({
            "id": _counter,
            "timestamp": time.time(),
            "username": username,
            "role": role,
            "action": action,
            "target": target or "",
            "details": details or "",
            "client_ip": client_ip or "",
        })
    logger.info(f"AUDIT: {username}({role}) -> {action} {target} {details}")


def get_log(hours: int = 24, username: str | None = None, action: str | None = None, limit: int = 200) -> list[dict]:
    since = time.time() - (hours * 3600)
    with _lock:
        results = []
        for entry in reversed(_log):
            if entry["timestamp"] < since:
                continue
            if username and entry["username"] != username:
                continue
            if action and action.lower() not in entry["action"].lower():
                continue
            results.append(dict(entry))
            if len(results) >= limit:
                break
    return results
