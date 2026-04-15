"""
SECCION9 LITE -- PYME Gateway Management
Manages SMB gateways that bridge remote clients to private LANs.
State persisted in JSON. WireGuard configs generated dynamically.
"""

import json
import os
import re
import time
import subprocess
import logging
import threading
from dataclasses import dataclass, asdict
from config import settings

logger = logging.getLogger("seccion9")

PYMES_FILE = "/etc/wireguard/pymes.json"
_lock = threading.Lock()
_cache: dict | None = None
_cache_mtime: float = -1.0


# -- Data model ------------------------------------------------

@dataclass
class PymeGateway:
    name: str                    # unique slug: "acme-corp"
    display_name: str            # "ACME Corp"
    lan_subnet: str              # "192.168.1.0/24"
    gateway_ip: str              # tunnel IP, e.g. "10.0.0.200"
    public_key: str              # WireGuard pubkey of the gateway device
    private_key: str             # stored to regenerate config
    lan_interface: str           # e.g. "eth0" on the gateway device
    lan_dns: str                 # e.g. "192.168.1.1"
    assigned_clients: list[str]  # client names with access
    created_at: float
    created_by: str
    notes: str = ""


# -- Persistence -----------------------------------------------

def _load() -> dict[str, dict]:
    global _cache, _cache_mtime
    with _lock:
        try:
            mtime = os.path.getmtime(PYMES_FILE)
        except FileNotFoundError:
            _cache = {}
            _cache_mtime = -1.0
            return {}
        if _cache is not None and mtime == _cache_mtime:
            return dict(_cache)
        try:
            with open(PYMES_FILE) as f:
                data = json.load(f)
        except (json.JSONDecodeError, IOError):
            data = {}
        _cache = data
        _cache_mtime = mtime
        return dict(data)


def _save(data: dict):
    global _cache, _cache_mtime
    with _lock:
        os.makedirs(os.path.dirname(PYMES_FILE), exist_ok=True)
        tmp = PYMES_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp, PYMES_FILE)
        os.chmod(PYMES_FILE, 0o600)
        _cache = dict(data)
        try:
            _cache_mtime = os.path.getmtime(PYMES_FILE)
        except FileNotFoundError:
            _cache_mtime = -1.0


# -- Helpers ---------------------------------------------------

def _sanitize_name(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_-]", "", name.replace(" ", "-")).lower()


def _next_gateway_ip() -> str | None:
    """Assign gateway IPs from the high end: 10.0.0.200-254"""
    pymes = _load()
    used = {p["gateway_ip"] for p in pymes.values()}
    # Also check wg0.conf for any existing AllowedIPs
    try:
        with open(settings.wg_conf_path) as f:
            conf = f.read()
    except FileNotFoundError:
        conf = ""
    for i in range(200, 255):
        ip = f"{settings.vpn_subnet}.{i}"
        if ip not in used and f"AllowedIPs = {ip}" not in conf:
            return ip
    return None


def _run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    if result.returncode != 0:
        logger.error(f"Command failed: {' '.join(cmd)} -- {result.stderr}")
    return result.stdout.strip()


# -- CRUD ------------------------------------------------------

def list_pymes() -> list[dict]:
    return list(_load().values())


def get_pyme(name: str) -> dict | None:
    return _load().get(name)


def create_pyme(
    name: str,
    display_name: str,
    lan_subnet: str,
    lan_interface: str,
    lan_dns: str,
    created_by: str,
    notes: str = "",
) -> dict:
    slug = _sanitize_name(name)
    if not slug:
        raise ValueError("Invalid PYME name")

    pymes = _load()
    if slug in pymes:
        raise ValueError(f"PYME '{slug}' already exists")

    # Validate subnet format
    if not re.match(r"^\d+\.\d+\.\d+\.\d+/\d+$", lan_subnet):
        raise ValueError(f"Invalid subnet format: {lan_subnet}")

    gateway_ip = _next_gateway_ip()
    if not gateway_ip:
        raise ValueError("No available gateway IPs")

    # Generate WireGuard keys for gateway
    private_key = _run(["wg", "genkey"])
    public_key = subprocess.run(
        ["wg", "pubkey"], input=private_key,
        capture_output=True, text=True, timeout=5
    ).stdout.strip()

    if not private_key or not public_key:
        raise RuntimeError("Failed to generate WireGuard keys")

    pyme = {
        "name": slug,
        "display_name": display_name,
        "lan_subnet": lan_subnet,
        "gateway_ip": gateway_ip,
        "public_key": public_key,
        "private_key": private_key,
        "lan_interface": lan_interface,
        "lan_dns": lan_dns,
        "assigned_clients": [],
        "created_at": time.time(),
        "created_by": created_by,
        "notes": notes,
    }

    # Add peer to wg0.conf
    peer_block = (
        f"\n# PYME: {slug}\n"
        f"[Peer]\n"
        f"PublicKey = {public_key}\n"
        f"AllowedIPs = {gateway_ip}/32, {lan_subnet}\n"
        f"PersistentKeepalive = 25\n"
    )
    with open(settings.wg_conf_path, "a") as f:
        f.write(peer_block)

    # Add peer to live WireGuard
    _run([
        "wg", "set", settings.wg_interface,
        "peer", public_key,
        "allowed-ips", f"{gateway_ip}/32,{lan_subnet}",
    ])

    pymes[slug] = pyme
    _save(pymes)

    logger.info(f"PYME created: {slug} subnet={lan_subnet} gw={gateway_ip}")
    return pyme


def delete_pyme(name: str) -> bool:
    pymes = _load()
    pyme = pymes.get(name)
    if not pyme:
        raise ValueError(f"PYME '{name}' does not exist")

    # Remove peer from wg0.conf
    try:
        with open(settings.wg_conf_path) as f:
            conf = f.read()
        pattern = rf"\n?# PYME: {re.escape(name)}\s*\n\[Peer\]\s*\nPublicKey = .+\s*\nAllowedIPs = .+\s*\n(PersistentKeepalive = \d+\s*\n)?"
        new_conf = re.sub(pattern, "\n", conf)
        new_conf = re.sub(r"\n{3,}", "\n\n", new_conf)
        with open(settings.wg_conf_path, "w") as f:
            f.write(new_conf)
    except Exception as e:
        logger.error(f"Failed to remove PYME peer from conf: {e}")

    # Remove from live WireGuard
    if pyme.get("public_key"):
        _run(["wg", "set", settings.wg_interface, "peer", pyme["public_key"], "remove"])

    # Update client configs to remove PYME subnet
    _remove_subnet_from_clients(pyme["assigned_clients"], pyme["lan_subnet"])

    del pymes[name]
    _save(pymes)

    logger.info(f"PYME deleted: {name}")
    return True


def update_pyme(name: str, fields: dict) -> dict:
    pymes = _load()
    pyme = pymes.get(name)
    if not pyme:
        raise ValueError(f"PYME '{name}' does not exist")

    allowed_fields = {"display_name", "lan_dns", "notes", "lan_interface"}
    for k, v in fields.items():
        if k in allowed_fields:
            pyme[k] = v

    pymes[name] = pyme
    _save(pymes)
    return pyme


# -- Client assignment -----------------------------------------

def assign_client(pyme_name: str, client_name: str) -> dict:
    pymes = _load()
    pyme = pymes.get(pyme_name)
    if not pyme:
        raise ValueError(f"PYME '{pyme_name}' does not exist")

    if client_name in pyme["assigned_clients"]:
        raise ValueError(f"Client '{client_name}' already assigned to '{pyme_name}'")

    pyme["assigned_clients"].append(client_name)
    pymes[pyme_name] = pyme
    _save(pymes)

    # Update client config to include PYME subnet
    _add_subnet_to_client(client_name, pyme["lan_subnet"])

    logger.info(f"Client '{client_name}' assigned to PYME '{pyme_name}'")
    return pyme


def unassign_client(pyme_name: str, client_name: str) -> dict:
    pymes = _load()
    pyme = pymes.get(pyme_name)
    if not pyme:
        raise ValueError(f"PYME '{pyme_name}' does not exist")

    if client_name not in pyme["assigned_clients"]:
        raise ValueError(f"Client '{client_name}' not assigned to '{pyme_name}'")

    pyme["assigned_clients"].remove(client_name)
    pymes[pyme_name] = pyme
    _save(pymes)

    # Remove PYME subnet from client config
    _remove_subnet_from_clients([client_name], pyme["lan_subnet"])

    logger.info(f"Client '{client_name}' unassigned from PYME '{pyme_name}'")
    return pyme


def get_client_pymes(client_name: str) -> list[dict]:
    """Get all PYMEs a client has access to."""
    result = []
    for pyme in _load().values():
        if client_name in pyme.get("assigned_clients", []):
            result.append({
                "name": pyme["name"],
                "display_name": pyme["display_name"],
                "lan_subnet": pyme["lan_subnet"],
            })
    return result


# -- Client config manipulation --------------------------------

def _get_all_subnets_for_client(client_name: str) -> list[str]:
    """Collect all PYME subnets assigned to a client."""
    subnets = []
    for pyme in _load().values():
        if client_name in pyme.get("assigned_clients", []):
            subnets.append(pyme["lan_subnet"])
    return subnets


def _rebuild_client_allowed_ips(client_name: str):
    """Rebuild AllowedIPs in client .conf based on assigned PYMEs."""
    conf_path = os.path.join(settings.configs_dir, f"{client_name}.conf")
    if not os.path.exists(conf_path):
        return

    with open(conf_path) as f:
        conf = f.read()

    subnets = _get_all_subnets_for_client(client_name)

    # Base: VPN subnet only (10.0.0.0/24)
    # With PYMEs: add each LAN subnet
    base = f"{settings.vpn_subnet}.0/24"
    all_ips = [base] + subnets
    new_allowed = ", ".join(all_ips)

    # Replace AllowedIPs line
    conf = re.sub(
        r"AllowedIPs\s*=\s*.+",
        f"AllowedIPs = {new_allowed}",
        conf,
    )

    with open(conf_path, "w") as f:
        f.write(conf)

    logger.info(f"Client '{client_name}' AllowedIPs updated: {new_allowed}")


def _add_subnet_to_client(client_name: str, subnet: str):
    _rebuild_client_allowed_ips(client_name)


def _remove_subnet_from_clients(client_names: list[str], subnet: str):
    for name in client_names:
        _rebuild_client_allowed_ips(name)


# -- Gateway config generation --------------------------------

def generate_gateway_config(pyme_name: str) -> str | None:
    """Generate the WireGuard config file for the PYME gateway device."""
    pyme = get_pyme(pyme_name)
    if not pyme:
        return None

    return (
        f"[Interface]\n"
        f"PrivateKey = {pyme['private_key']}\n"
        f"Address = {pyme['gateway_ip']}/24\n"
        f"DNS = {pyme['lan_dns']}\n"
        f"PostUp = iptables -A FORWARD -i %i -o {pyme['lan_interface']} -j ACCEPT; "
        f"iptables -A FORWARD -i {pyme['lan_interface']} -o %i -j ACCEPT; "
        f"iptables -t nat -A POSTROUTING -s {settings.vpn_subnet}.0/24 -o {pyme['lan_interface']} -j MASQUERADE\n"
        f"PostDown = iptables -D FORWARD -i %i -o {pyme['lan_interface']} -j ACCEPT; "
        f"iptables -D FORWARD -i {pyme['lan_interface']} -o %i -j ACCEPT; "
        f"iptables -t nat -D POSTROUTING -s {settings.vpn_subnet}.0/24 -o {pyme['lan_interface']} -j MASQUERADE\n"
        f"\n"
        f"[Peer]\n"
        f"PublicKey = {settings.server_public_key}\n"
        f"Endpoint = {settings.server_public_ip}:{settings.server_port}\n"
        f"AllowedIPs = {settings.vpn_subnet}.0/24\n"
        f"PersistentKeepalive = 25\n"
    )


def get_gateway_status(pyme_name: str) -> dict:
    """Check if gateway peer is online via WireGuard handshake."""
    pyme = get_pyme(pyme_name)
    if not pyme:
        return {"status": "unknown"}

    hs_output = _run(["wg", "show", settings.wg_interface, "latest-handshakes"])
    now = time.time()

    for line in hs_output.split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2 and parts[0].strip() == pyme["public_key"]:
            try:
                ts = int(parts[1])
                ago = now - ts
                if ts > 0 and ago < 180:
                    return {"status": "online", "last_handshake": ts, "seconds_ago": int(ago)}
                elif ts > 0:
                    return {"status": "inactive", "last_handshake": ts, "seconds_ago": int(ago)}
            except ValueError:
                pass

    return {"status": "offline", "last_handshake": 0}
