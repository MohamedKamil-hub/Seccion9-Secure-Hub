"""
SECCION9 LITE — WireGuard Management Layer
Pure WireGuard. No OpenVPN.
"""

import subprocess
import os
import re
import time
import logging
from dataclasses import dataclass
from config import settings

logger = logging.getLogger("seccion9")


@dataclass
class ClientInfo:
    name: str
    public_key: str
    ip: str
    endpoint: str | None = None
    latest_handshake: int = 0
    transfer_rx: int = 0
    transfer_tx: int = 0
    status: str = "offline"


def _run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    if result.returncode != 0:
        logger.error(f"Command failed: {' '.join(cmd)} -- {result.stderr}")
    return result.stdout.strip()


def _next_available_ip() -> str | None:
    conf = _read_conf()
    for i in range(2, 254):
        ip = f"{settings.vpn_subnet}.{i}"
        if f"AllowedIPs = {ip}/32" not in conf:
            return ip
    return None


def _read_conf() -> str:
    try:
        with open(settings.wg_conf_path, "r") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def _write_conf(content: str):
    with open(settings.wg_conf_path, "w") as f:
        f.write(content)


def _parse_transfer(value: str) -> int:
    match = re.match(r"([\d.]+)\s*(\w+)", value)
    if not match:
        return 0
    num = float(match.group(1))
    unit = match.group(2).lower()
    multipliers = {"b": 1, "kib": 1024, "mib": 1048576, "gib": 1073741824}
    return int(num * multipliers.get(unit, 1))


def list_clients() -> list[ClientInfo]:
    conf = _read_conf()
    clients = []

    pattern = re.compile(
        r"# Cliente: (\S+)\s*\n\[Peer\]\s*\nPublicKey = (.+)\s*\nAllowedIPs = ([\d.]+)/32"
    )

    # Get live data in batch
    handshake_output = _run(["wg", "show", settings.wg_interface, "latest-handshakes"])
    transfer_output = _run(["wg", "show", settings.wg_interface, "transfer"])
    endpoints_output = _run(["wg", "show", settings.wg_interface, "endpoints"])

    hs_map = {}
    for line in handshake_output.split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2:
            try:
                hs_map[parts[0].strip()] = int(parts[1])
            except ValueError:
                pass

    tx_map = {}
    for line in transfer_output.split("\n"):
        parts = line.split("\t")
        if len(parts) >= 3:
            try:
                tx_map[parts[0].strip()] = (int(parts[1]), int(parts[2]))
            except ValueError:
                pass

    ep_map = {}
    for line in endpoints_output.split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2:
            ep_map[parts[0].strip()] = parts[1].strip()

    now = int(time.time())

    for match in pattern.finditer(conf):
        name = match.group(1)
        pubkey = match.group(2).strip()
        ip = match.group(3)

        latest_ts = hs_map.get(pubkey, 0)
        rx, tx = tx_map.get(pubkey, (0, 0))
        endpoint = ep_map.get(pubkey)
        if endpoint == "(none)":
            endpoint = None

        if latest_ts > 0:
            seconds_ago = now - latest_ts
            status = "online" if seconds_ago < 180 else "inactive"
        else:
            status = "offline"

        clients.append(ClientInfo(
            name=name, public_key=pubkey, ip=ip,
            endpoint=endpoint, latest_handshake=latest_ts,
            transfer_rx=rx, transfer_tx=tx, status=status,
        ))

    return clients


def get_client(name: str) -> ClientInfo | None:
    for client in list_clients():
        if client.name == name:
            return client
    return None


def add_client(name: str) -> dict:
    name = re.sub(r"[^a-zA-Z0-9_-]", "", name.replace(" ", "_"))
    if not name:
        raise ValueError("Invalid client name")

    conf = _read_conf()
    if f"# Cliente: {name}" in conf:
        raise ValueError(f"Client '{name}' already exists")

    ip = _next_available_ip()
    if not ip:
        raise ValueError("No available IPs in subnet")

    private_key = _run(["wg", "genkey"])
    public_key = subprocess.run(
        ["wg", "pubkey"], input=private_key,
        capture_output=True, text=True, timeout=5
    ).stdout.strip()

    if not private_key or not public_key:
        raise RuntimeError("Failed to generate WireGuard keys")

    peer_block = f"\n# Cliente: {name}\n[Peer]\nPublicKey = {public_key}\nAllowedIPs = {ip}/32\n"

    with open(settings.wg_conf_path, "a") as f:
        f.write(peer_block)

    _run(["wg", "set", settings.wg_interface, "peer", public_key, "allowed-ips", f"{ip}/32"])

    os.makedirs(settings.configs_dir, exist_ok=True)
    client_conf = f"""[Interface]
PrivateKey = {private_key}
Address = {ip}/24
DNS = {settings.get_dns()}

[Peer]
PublicKey = {settings.server_public_key}
Endpoint = {settings.server_public_ip}:{settings.server_port}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
"""

    conf_path = os.path.join(settings.configs_dir, f"{name}.conf")
    with open(conf_path, "w") as f:
        f.write(client_conf)
    os.chmod(conf_path, 0o600)

    logger.info(f"ADDED client={name} ip={ip}")
    return {"name": name, "ip": ip, "public_key": public_key, "config": client_conf, "config_path": conf_path}


def remove_client(name: str) -> bool:
    name = re.sub(r"[^a-zA-Z0-9_-]", "", name.replace(" ", "_"))
    conf = _read_conf()

    if f"# Cliente: {name}" not in conf:
        raise ValueError(f"Client '{name}' does not exist")

    match = re.search(
        rf"# Cliente: {re.escape(name)}\s*\n\[Peer\]\s*\nPublicKey = (.+)\s*\n", conf
    )
    pubkey = match.group(1).strip() if match else None

    pattern = rf"\n?# Cliente: {re.escape(name)}\s*\n\[Peer\]\s*\nPublicKey = .+\s*\nAllowedIPs = [\d.]+/32\s*\n?"
    new_conf = re.sub(pattern, "\n", conf)
    new_conf = re.sub(r"\n{3,}", "\n\n", new_conf)
    _write_conf(new_conf)

    if pubkey:
        _run(["wg", "set", settings.wg_interface, "peer", pubkey, "remove"])

    conf_path = os.path.join(settings.configs_dir, f"{name}.conf")
    if os.path.exists(conf_path):
        os.remove(conf_path)

    logger.info(f"REMOVED client={name}")
    return True


def get_client_config(name: str) -> str | None:
    conf_path = os.path.join(settings.configs_dir, f"{name}.conf")
    if not os.path.exists(conf_path):
        return None
    with open(conf_path, "r") as f:
        return f.read()


def get_server_status() -> dict:
    try:
        wg_check = _run(["wg", "show", settings.wg_interface])
        service_status = "active" if wg_check else "inactive"
    except Exception:
        service_status = "inactive"

    try:
        with open("/proc/sys/net/ipv4/ip_forward") as f:
            ip_forward = f.read().strip() == "1"
    except Exception:
        ip_forward = False

    wg_port = str(settings.server_port)
    ufw_wg = False
    try:
        ipt_save = _run(["iptables-save"])
        ufw_wg = any(
            wg_port in line and "ACCEPT" in line
            for line in ipt_save.splitlines()
            if not line.startswith("#")
        )
    except Exception:
        pass

    clients = list_clients()
    online = sum(1 for c in clients if c.status == "online")

    try:
        with open("/proc/uptime") as f:
            secs = float(f.read().split()[0])
        days = int(secs // 86400)
        hours = int((secs % 86400) // 3600)
        uptime = f"up {days}d {hours}h"
    except Exception:
        uptime = "unknown"

    return {
        "service": service_status,
        "ip_forwarding": ip_forward,
        "ufw_wireguard": ufw_wg,
        "total_clients": len(clients),
        "online_clients": online,
        "server_ip": settings.server_public_ip,
        "server_port": settings.server_port,
        "vpn_subnet": f"{settings.vpn_subnet}.0/24",
        "uptime": uptime,
        "wg_interface": settings.wg_interface,
    }
