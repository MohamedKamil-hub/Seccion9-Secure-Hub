"""
SECCION9 LITE — Stateless Metrics
No SQLite. WireGuard only. In-memory ring buffers.
"""

import re
import subprocess
import time
import logging
import threading
from collections import deque
from config import settings

logger = logging.getLogger("seccion9")

_MAX_EVENTS = 1000
_connection_log: deque = deque(maxlen=_MAX_EVENTS)
_traffic_snapshots: deque = deque(maxlen=5000)
_lock = threading.Lock()

_prev_transfer: dict = {}
_prev_online: dict = {}
POLL_INTERVAL = 30
HANDSHAKE_TIMEOUT = 180


def _run(cmd: list[str]) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception:
        return ""


def _get_peer_map() -> dict:
    peers = {}
    try:
        with open(settings.wg_conf_path) as f:
            conf = f.read()
    except FileNotFoundError:
        return peers
    pattern = re.compile(r"# Cliente: (\S+)\s*\n\[Peer\]\s*\nPublicKey = (.+)\s*\nAllowedIPs = ([\d.]+)/32")
    for m in pattern.finditer(conf):
        peers[m.group(2).strip()] = {"name": m.group(1), "ip": m.group(3)}
    return peers


def _get_transfers() -> dict:
    out = _run(["wg", "show", settings.wg_interface, "transfer"])
    result = {}
    for line in out.split("\n"):
        parts = line.split("\t")
        if len(parts) >= 3:
            try:
                result[parts[0].strip()] = (int(parts[1]), int(parts[2]))
            except ValueError:
                pass
    return result


def _get_handshakes() -> dict:
    out = _run(["wg", "show", settings.wg_interface, "latest-handshakes"])
    result = {}
    for line in out.split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2:
            try:
                result[parts[0].strip()] = int(parts[1])
            except ValueError:
                pass
    return result


def _poll_wireguard():
    global _prev_transfer, _prev_online
    now = time.time()
    peer_map = _get_peer_map()
    transfers = _get_transfers()
    handshakes = _get_handshakes()

    with _lock:
        for pubkey, info in peer_map.items():
            name = info["name"]
            ip = info["ip"]
            hs = handshakes.get(pubkey, 0)
            is_online = hs > 0 and (now - hs) < HANDSHAKE_TIMEOUT

            rx, tx = transfers.get(pubkey, (0, 0))
            prev = _prev_transfer.get(pubkey)
            delta_rx, delta_tx = 0, 0
            if prev:
                delta_rx = max(0, rx - prev["rx"])
                delta_tx = max(0, tx - prev["tx"])
                if delta_rx > 0 or delta_tx > 0:
                    _traffic_snapshots.append({
                        "timestamp": now, "client_name": name,
                        "delta_rx": delta_rx, "delta_tx": delta_tx,
                    })
            _prev_transfer[pubkey] = {"rx": rx, "tx": tx}

            was_online = _prev_online.get(pubkey, False)
            if is_online and not was_online:
                _connection_log.append({
                    "id": int(now * 1000), "client_name": name, "client_ip": ip,
                    "connected_at": now, "disconnected_at": None,
                    "bytes_rx": 0, "bytes_tx": 0, "active": True, "duration_seconds": 0,
                })
            elif not is_online and was_online:
                for ev in reversed(_connection_log):
                    if ev["client_name"] == name and ev["active"]:
                        ev["active"] = False
                        ev["disconnected_at"] = now
                        ev["duration_seconds"] = int(now - ev["connected_at"])
                        ev["bytes_rx"] += delta_rx
                        ev["bytes_tx"] += delta_tx
                        break
            elif is_online and was_online and (delta_rx > 0 or delta_tx > 0):
                for ev in reversed(_connection_log):
                    if ev["client_name"] == name and ev["active"]:
                        ev["bytes_rx"] += delta_rx
                        ev["bytes_tx"] += delta_tx
                        ev["duration_seconds"] = int(now - ev["connected_at"])
                        break

            _prev_online[pubkey] = is_online


def _polling_loop():
    logger.info(f"Metrics polling started (every {POLL_INTERVAL}s)")
    while True:
        try:
            _poll_wireguard()
        except Exception as e:
            logger.error(f"Metrics poll error: {e}")
        time.sleep(POLL_INTERVAL)


def start_polling():
    t = threading.Thread(target=_polling_loop, daemon=True)
    t.start()


def init_db():
    pass


def get_connection_log(hours: int = 24, client_name: str | None = None) -> list[dict]:
    since = time.time() - (hours * 3600)
    now = time.time()
    with _lock:
        result = []
        for ev in _connection_log:
            if ev["connected_at"] < since:
                continue
            if client_name and ev["client_name"] != client_name:
                continue
            entry = dict(ev)
            if entry["active"]:
                entry["duration_seconds"] = int(now - entry["connected_at"])
            result.append(entry)
    return sorted(result, key=lambda x: x["connected_at"], reverse=True)


def get_traffic_hourly(hours: int = 24) -> list[dict]:
    since = time.time() - (hours * 3600)
    hourly: dict[int, dict] = {}
    with _lock:
        for snap in _traffic_snapshots:
            if snap["timestamp"] < since:
                continue
            h = int((snap["timestamp"] - since) / 3600)
            if h not in hourly:
                hourly[h] = {"hour": h, "timestamp": since + h * 3600, "total_rx": 0, "total_tx": 0}
            hourly[h]["total_rx"] += snap["delta_rx"]
            hourly[h]["total_tx"] += snap["delta_tx"]

    result = []
    for h in range(hours):
        result.append(hourly.get(h, {"hour": h, "timestamp": since + h * 3600, "total_rx": 0, "total_tx": 0}))
    return result


def get_traffic_by_client(hours: int = 24) -> list[dict]:
    since = time.time() - (hours * 3600)
    by_client: dict[str, dict] = {}
    with _lock:
        for snap in _traffic_snapshots:
            if snap["timestamp"] < since:
                continue
            n = snap["client_name"]
            if n not in by_client:
                by_client[n] = {"client_name": n, "total_rx": 0, "total_tx": 0}
            by_client[n]["total_rx"] += snap["delta_rx"]
            by_client[n]["total_tx"] += snap["delta_tx"]
    return sorted(by_client.values(), key=lambda x: x["total_rx"] + x["total_tx"], reverse=True)


def get_summary(hours: int = 24) -> dict:
    since = time.time() - (hours * 3600)
    with _lock:
        log = [ev for ev in _connection_log if ev["connected_at"] >= since]
        total_connections = len(log)
        unique_clients = len({ev["client_name"] for ev in log})
        active_sessions = sum(1 for ev in log if ev["active"])
        snaps = [s for s in _traffic_snapshots if s["timestamp"] >= since]
        total_rx = sum(s["delta_rx"] for s in snaps)
        total_tx = sum(s["delta_tx"] for s in snaps)
        durations = [ev["duration_seconds"] for ev in log if ev["duration_seconds"] > 0]
        avg_duration = (sum(durations) / len(durations)) if durations else 0

    return {
        "total_connections": total_connections,
        "unique_clients": unique_clients,
        "total_rx": total_rx,
        "total_tx": total_tx,
        "avg_session_minutes": round(avg_duration / 60, 1),
        "active_sessions": active_sessions,
        "period_hours": hours,
    }
