"""
SECCION9 LITE — Invite Links
JWT-signed tokens. State persisted to disk.
"""

import time
import logging
import secrets
import hmac
import hashlib
import json
import base64
import os
from config import settings

logger = logging.getLogger("seccion9")

INVITES_STATE_FILE = "/etc/wireguard/invites_state.json"

_used_tokens: set[str] = set()
_active_invites: dict[str, dict] = {}

CLAIM_GRACE_SECONDS = 600


# ── Persistencia ──────────────────────────────────────────────

def _save_state():
    try:
        os.makedirs(os.path.dirname(INVITES_STATE_FILE), exist_ok=True)
        state = {
            "active_invites": _active_invites,
            "used_tokens": list(_used_tokens),
        }
        tmp = INVITES_STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f, indent=2)
        os.replace(tmp, INVITES_STATE_FILE)  # escritura atómica
        os.chmod(INVITES_STATE_FILE, 0o600)
    except Exception as e:
        logger.error(f"Failed to save invite state: {e}")


def _load_state():
    global _active_invites, _used_tokens
    try:
        with open(INVITES_STATE_FILE) as f:
            state = json.load(f)
        _active_invites = state.get("active_invites", {})
        _used_tokens = set(state.get("used_tokens", []))
        logger.info(f"Invite state loaded: {len(_active_invites)} active, {len(_used_tokens)} used")
    except FileNotFoundError:
        pass  # primera vez, estado vacío
    except Exception as e:
        logger.error(f"Failed to load invite state: {e}")


_load_state()  # ejecuta al importar el módulo


# ── Firma HMAC ────────────────────────────────────────────────

def _sign(payload: dict) -> str:
    data = json.dumps(payload, separators=(",", ":")).encode()
    b64 = base64.urlsafe_b64encode(data).decode().rstrip("=")
    sig = hmac.new(settings.secret_key.encode(), b64.encode(), hashlib.sha256).hexdigest()[:16]
    return f"{b64}.{sig}"


def _verify(token: str) -> dict | None:
    try:
        b64, sig = token.rsplit(".", 1)
        expected = hmac.new(settings.secret_key.encode(), b64.encode(), hashlib.sha256).hexdigest()[:16]
        if not hmac.compare_digest(sig, expected):
            return None
        padded = b64 + "=" * (4 - len(b64) % 4)
        return json.loads(base64.urlsafe_b64decode(padded))
    except Exception:
        return None


# ── CRUD ──────────────────────────────────────────────────────

def create_invite(client_name: str, created_by: str, expire_hours: int = 24) -> dict:
    for tok, meta in list(_active_invites.items()):
        if meta["client_name"] == client_name and meta["expires_at"] > time.time() and tok not in _used_tokens:
            raise ValueError(f"Active invite already exists for '{client_name}'")

    now = time.time()
    nonce = secrets.token_hex(8)
    payload = {
        "client_name": client_name, "created_by": created_by,
        "created_at": now, "expires_at": now + (expire_hours * 3600), "nonce": nonce,
    }
    token = _sign(payload)
    _active_invites[token] = {**payload, "token": token, "claimed": False, "claimed_at": None}
    _save_state()
    logger.info(f"Invite created for '{client_name}' by {created_by}")
    return {"token": token, **payload}


def update_invite(token: str, fields: dict) -> bool:
    if token in _active_invites:
        _active_invites[token].update(fields)
        _save_state()
        return True
    return False


def get_invite(token: str) -> dict | None:
    payload = _verify(token)
    if not payload:
        return None
    if token in _active_invites:
        return _active_invites[token]
    return {
        "token": token, "client_name": payload["client_name"],
        "created_by": payload["created_by"], "created_at": payload["created_at"],
        "expires_at": payload["expires_at"], "claimed": False, "claimed_at": None,
    }


def list_invites() -> list[dict]:
    return list(_active_invites.values())


def claim_invite(token: str) -> bool:
    if token in _used_tokens:
        return False
    _used_tokens.add(token)
    if token in _active_invites:
        _active_invites[token]["claimed"] = True
        _active_invites[token]["claimed_at"] = time.time()
    _save_state()
    logger.info(f"Invite claimed: {token[:8]}...")
    return True


def delete_invite(token: str) -> bool:
    if token in _active_invites:
        del _active_invites[token]
        _used_tokens.discard(token)
        _save_state()
        return True
    return False


def is_valid(invite: dict) -> tuple[bool, str]:
    token = invite.get("token", "")
    now = time.time()
    if now > invite.get("expires_at", 0):
        return False, "expired"
    if token in _used_tokens or invite.get("claimed"):
        claimed_at = invite.get("claimed_at") or 0
        if claimed_at and (now - claimed_at) > CLAIM_GRACE_SECONDS:
            return False, "used"
        return False, "used"
    return True, "valid"


def cleanup_expired():
    cutoff = time.time()
    stale = [t for t, m in _active_invites.items() if m["expires_at"] < cutoff - 86400]
    for t in stale:
        del _active_invites[t]
        _used_tokens.discard(t)
    if stale:
        _save_state()
