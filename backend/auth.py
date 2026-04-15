import json
import os
import time
import logging
import threading
from datetime import datetime, timedelta, timezone
from collections import defaultdict

from config import settings
from jose import JWTError, jwt
from passlib.context import CryptContext
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

logger = logging.getLogger("seccion9")

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

ALGORITHM = "HS256"
USERS_FILE = "/etc/wireguard/users.json"

ROLES = {
    "admin":   {"description": "Full access + user management",  "can_manage_users": True,  "can_manage_clients": True,  "can_manage_invites": True,  "can_manage_settings": True},
    "tecnico": {"description": "Client and invite management",    "can_manage_users": False, "can_manage_clients": True,  "can_manage_invites": True,  "can_manage_settings": False},
    "viewer":  {"description": "Read only",                       "can_manage_users": False, "can_manage_clients": False, "can_manage_invites": False, "can_manage_settings": False},
}

MAX_ATTEMPTS = 5
LOCKOUT_SECONDS = 900
_login_attempts: dict = defaultdict(lambda: {"count": 0, "locked_until": 0.0})

# ── User cache ────────────────────────────────────────────────
_users_cache: list[dict] | None = None
_users_cache_mtime: float = -1.0
_users_lock = threading.Lock()


def _load_users() -> list[dict]:
    global _users_cache, _users_cache_mtime
    with _users_lock:
        try:
            mtime = os.path.getmtime(USERS_FILE)
        except FileNotFoundError:
            _users_cache = []
            _users_cache_mtime = -1.0
            return []
        # Devuelve cache si el archivo no cambió
        if _users_cache is not None and mtime == _users_cache_mtime:
            return list(_users_cache)
        try:
            with open(USERS_FILE, "r") as f:
                data = json.load(f)
        except (json.JSONDecodeError, IOError):
            data = []
        _users_cache = data
        _users_cache_mtime = mtime
        return list(data)


def _save_users(users: list[dict]):
    global _users_cache, _users_cache_mtime
    with _users_lock:
        os.makedirs(os.path.dirname(USERS_FILE), exist_ok=True)
        with open(USERS_FILE, "w") as f:
            json.dump(users, f, indent=2)
        os.chmod(USERS_FILE, 0o600)
        # Actualiza cache inmediatamente para evitar re-lectura
        _users_cache = list(users)
        try:
            _users_cache_mtime = os.path.getmtime(USERS_FILE)
        except FileNotFoundError:
            _users_cache_mtime = -1.0





# Brute-force tracker (in-memory, resets on restart)
MAX_ATTEMPTS = 5
LOCKOUT_SECONDS = 900
_login_attempts: dict = defaultdict(lambda: {"count": 0, "locked_until": 0.0})


def check_brute_force(client_ip: str):
    entry = _login_attempts[client_ip]
    now = time.time()
    if entry["locked_until"] > now:
        remaining = int(entry["locked_until"] - now)
        raise HTTPException(status_code=429, detail=f"Too many attempts. Try again in {remaining}s.")
    if entry["locked_until"] > 0 and entry["locked_until"] <= now:
        _login_attempts[client_ip] = {"count": 0, "locked_until": 0.0}


def record_failed_attempt(client_ip: str):
    entry = _login_attempts[client_ip]
    entry["count"] += 1
    if entry["count"] >= MAX_ATTEMPTS:
        entry["locked_until"] = time.time() + LOCKOUT_SECONDS


def record_success(client_ip: str):
    _login_attempts.pop(client_ip, None)


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password[:72])


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain[:72], hashed)


# ── User storage (JSON) ──────────────────────────────────────

def _load_users() -> list[dict]:
    if not os.path.exists(USERS_FILE):
        return []
    try:
        with open(USERS_FILE, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return []


def _save_users(users: list[dict]):
    os.makedirs(os.path.dirname(USERS_FILE), exist_ok=True)
    with open(USERS_FILE, "w") as f:
        json.dump(users, f, indent=2)
    os.chmod(USERS_FILE, 0o600)


def _ensure_default_admin():
    users = _load_users()
    if not users:
        admin = {
            "username": settings.admin_user,
            "password_hash": get_password_hash(settings.admin_password),
            "role": "admin",
            "created_at": time.time(),
            "created_by": "system",
        }
        _save_users([admin])
        logger.info(f"Admin user created from .env: {settings.admin_user}")
        return

    changed = False
    for u in users:
        if u["username"] == settings.admin_user:
            if not verify_password(settings.admin_password, u["password_hash"]):
                u["password_hash"] = get_password_hash(settings.admin_password)
                changed = True
                logger.info(f"Admin password re-synced from .env")
            break
    if changed:
        _save_users(users)


_ensure_default_admin()


def _get_user(username: str) -> dict | None:
    for u in _load_users():
        if u["username"] == username:
            return u
    return None


def authenticate_user(username: str, password: str) -> dict | None:
    user = _get_user(username)
    if not user or not verify_password(password, user["password_hash"]):
        return None
    return {"username": user["username"], "role": user["role"]}


def update_password(username: str, new_password: str) -> bool:
    users = _load_users()
    for u in users:
        if u["username"] == username:
            u["password_hash"] = get_password_hash(new_password)
            _save_users(users)
            return True
    return False


def list_users() -> list[dict]:
    return [
        {"username": u["username"], "role": u["role"], "created_at": u.get("created_at", 0), "created_by": u.get("created_by", "")}
        for u in _load_users()
    ]


def create_user(username: str, password: str, role: str, created_by: str) -> dict:
    if role not in ROLES:
        raise ValueError(f"Invalid role: {role}")
    if len(password) < 8:
        raise ValueError("Password must be at least 8 characters")
    if not username or len(username) < 3:
        raise ValueError("Username must be at least 3 characters")
    if _get_user(username):
        raise ValueError(f"User '{username}' already exists")
    users = _load_users()
    user = {"username": username, "password_hash": get_password_hash(password), "role": role, "created_at": time.time(), "created_by": created_by}
    users.append(user)
    _save_users(users)
    return {"username": username, "role": role, "created_at": user["created_at"], "created_by": created_by}


def delete_user(username: str, deleted_by: str) -> bool:
    users = _load_users()
    admins = [u for u in users if u["role"] == "admin"]
    target = next((u for u in users if u["username"] == username), None)
    if not target:
        raise ValueError(f"User '{username}' does not exist")
    if target["role"] == "admin" and len(admins) <= 1:
        raise ValueError("Cannot delete the last administrator")
    if username == deleted_by:
        raise ValueError("Cannot delete yourself")
    _save_users([u for u in users if u["username"] != username])
    return True


def update_user_role(username: str, new_role: str, updated_by: str) -> bool:
    if new_role not in ROLES:
        raise ValueError(f"Invalid role: {new_role}")
    users = _load_users()
    target = next((u for u in users if u["username"] == username), None)
    if not target:
        raise ValueError(f"User '{username}' does not exist")
    if target["role"] == "admin" and new_role != "admin":
        if sum(1 for u in users if u["role"] == "admin") <= 1:
            raise ValueError("Cannot change the last administrator's role")
    target["role"] = new_role
    _save_users(users)
    return True


def reset_user_password(username: str, new_password: str, reset_by: str) -> bool:
    if len(new_password) < 8:
        raise ValueError("Password must be at least 8 characters")
    if not update_password(username, new_password):
        raise ValueError(f"User '{username}' does not exist")
    return True


# ── JWT ───────────────────────────────────────────────────────

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, settings.secret_key, algorithm=ALGORITHM)


async def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    exc = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token", headers={"WWW-Authenticate": "Bearer"})
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        role: str = payload.get("role", "viewer")
        if username is None:
            raise exc
    except JWTError:
        raise exc
    return {"username": username, "role": role}


def require_role(*allowed_roles: str):
    async def checker(user: dict = Depends(get_current_user)) -> dict:
        if user["role"] not in allowed_roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=f"Access denied. Required: {', '.join(allowed_roles)}")
        return user
    return checker
