"""
SECCION9 — WireGuard Management Layer
Gestiona peers a través de comandos wg y el archivo wg0.conf
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


def _run(cmd: str) -> str:
    """Ejecutar comando del sistema y devolver stdout."""
    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True, timeout=10
    )
    if result.returncode != 0:
        logger.error(f"Command failed: {cmd} — {result.stderr}")
    return result.stdout.strip()


def _next_available_ip() -> str | None:
    """Buscar la siguiente IP libre en la subred VPN."""
    conf = _read_conf()
    for i in range(2, 255):
        ip = f"{settings.vpn_subnet}.{i}"
        if f"AllowedIPs = {ip}/32" not in conf:
            return ip
    return None


def _read_conf() -> str:
    """Leer el archivo de configuración de WireGuard."""
    try:
        with open(settings.wg_conf_path, "r") as f:
            return f.read()
    except FileNotFoundError:
        return ""


def _write_conf(content: str):
    """Escribir el archivo de configuración de WireGuard."""
    with open(settings.wg_conf_path, "w") as f:
        f.write(content)


def _parse_wg_show() -> dict:
    """Parsear la salida de 'wg show' para obtener info de peers."""
    output = _run(f"wg show {settings.wg_interface}")
    peers = {}
    current_peer = None

    for line in output.split("\n"):
        line = line.strip()
        if line.startswith("peer:"):
            current_peer = line.split("peer:")[1].strip()
            peers[current_peer] = {}
        elif current_peer and ":" in line:
            key, _, value = line.partition(":")
            key = key.strip().lower().replace(" ", "_")
            peers[current_peer][key] = value.strip()

    return peers


def _parse_transfer(value: str) -> int:
    """Convertir cadena de transfer (ej: '1.23 MiB') a bytes."""
    match = re.match(r"([\d.]+)\s*(\w+)", value)
    if not match:
        return 0
    num = float(match.group(1))
    unit = match.group(2).lower()
    multipliers = {"b": 1, "kib": 1024, "mib": 1048576, "gib": 1073741824}
    return int(num * multipliers.get(unit, 1))


def list_clients() -> list[ClientInfo]:
    """Listar todos los clientes configurados con su estado."""
    conf = _read_conf()
    wg_data = _parse_wg_show()
    clients = []

    # Buscar bloques de clientes en el conf
    pattern = re.compile(
        r"# Cliente: (\S+)\s*\n\[Peer\]\s*\nPublicKey = (.+)\s*\nAllowedIPs = ([\d.]+)/32"
    )

    for match in pattern.finditer(conf):
        name = match.group(1)
        pubkey = match.group(2).strip()
        ip = match.group(3)

        peer_data = wg_data.get(pubkey, {})

        # Determinar estado por handshake
        handshake_str = peer_data.get("latest_handshake", "0")
        try:
            if "ago" in handshake_str or "second" in handshake_str or "minute" in handshake_str:
                # Formato relativo — parsear
                handshake_ts = 1  # marcamos como "ha tenido handshake"
            else:
                handshake_ts = 0
        except (ValueError, TypeError):
            handshake_ts = 0

        # Transfer
        transfer = peer_data.get("transfer", "")
        rx, tx = 0, 0
        if "received" in transfer:
            parts = transfer.split(",")
            for part in parts:
                if "received" in part:
                    rx = _parse_transfer(part.replace("received", "").strip())
                elif "sent" in part:
                    tx = _parse_transfer(part.replace("sent", "").strip())

        # Estado basado en el handshake
        endpoint = peer_data.get("endpoint", None)

        # Usar el timestamp real de wg show latest-handshakes
        handshake_output = _run(
            f"wg show {settings.wg_interface} latest-handshakes"
        )
        latest_ts = 0
        for hs_line in handshake_output.split("\n"):
            if pubkey in hs_line:
                parts = hs_line.split()
                if len(parts) >= 2:
                    try:
                        latest_ts = int(parts[1])
                    except ValueError:
                        latest_ts = 0

        if latest_ts > 0:
            seconds_ago = int(time.time()) - latest_ts
            if seconds_ago < 180:
                status = "online"
            else:
                status = "inactive"
        else:
            status = "offline"

        clients.append(
            ClientInfo(
                name=name,
                public_key=pubkey,
                ip=ip,
                endpoint=endpoint,
                latest_handshake=latest_ts,
                transfer_rx=rx,
                transfer_tx=tx,
                status=status,
            )
        )

    return clients


def get_client(name: str) -> ClientInfo | None:
    """Obtener info de un cliente específico."""
    for client in list_clients():
        if client.name == name:
            return client
    return None


def add_client(name: str) -> dict:
    """Añadir un nuevo cliente VPN. Genera claves y config automáticamente."""
    # Validar nombre
    name = re.sub(r"[^a-zA-Z0-9_-]", "", name.replace(" ", "_"))
    if not name:
        raise ValueError("Nombre de cliente inválido")

    # Comprobar duplicado
    conf = _read_conf()
    if f"# Cliente: {name}" in conf:
        raise ValueError(f"Ya existe un cliente con el nombre '{name}'")

    # Buscar IP libre
    ip = _next_available_ip()
    if not ip:
        raise ValueError("No hay IPs disponibles en la subred")

    # Generar claves
    private_key = _run("wg genkey")
    public_key = _run(f"echo '{private_key}' | wg pubkey")

    if not private_key or not public_key:
        raise RuntimeError("Error al generar claves WireGuard")

    # Añadir al archivo de configuración
    peer_block = f"\n# Cliente: {name}\n[Peer]\nPublicKey = {public_key}\nAllowedIPs = {ip}/32\n"

    with open(settings.wg_conf_path, "a") as f:
        f.write(peer_block)

    # Aplicar en caliente
    _run(f"wg set {settings.wg_interface} peer {public_key} allowed-ips {ip}/32")

    # Generar .conf para el cliente
    os.makedirs(settings.configs_dir, exist_ok=True)
    client_conf = f"""[Interface]
PrivateKey = {private_key}
Address = {ip}/24
DNS = 8.8.8.8

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

    # Log
    logger.info(f"AÑADIDO cliente={name} ip={ip} pubkey={public_key}")

    return {
        "name": name,
        "ip": ip,
        "public_key": public_key,
        "config": client_conf,
        "config_path": conf_path,
    }


def remove_client(name: str) -> bool:
    """Eliminar un cliente VPN."""
    name = re.sub(r"[^a-zA-Z0-9_-]", "", name.replace(" ", "_"))
    conf = _read_conf()

    if f"# Cliente: {name}" not in conf:
        raise ValueError(f"No existe el cliente '{name}'")

    # Obtener clave pública antes de borrar
    match = re.search(
        rf"# Cliente: {re.escape(name)}\s*\n\[Peer\]\s*\nPublicKey = (.+)\s*\n",
        conf,
    )
    pubkey = match.group(1).strip() if match else None

    # Eliminar bloque del conf
    pattern = rf"\n?# Cliente: {re.escape(name)}\s*\n\[Peer\]\s*\nPublicKey = .+\s*\nAllowedIPs = [\d.]+/32\s*\n?"
    new_conf = re.sub(pattern, "\n", conf)
    # Limpiar líneas vacías extra
    new_conf = re.sub(r"\n{3,}", "\n\n", new_conf)
    _write_conf(new_conf)

    # Eliminar peer en caliente
    if pubkey:
        _run(f"wg set {settings.wg_interface} peer {pubkey} remove")

    # Eliminar archivo .conf del cliente
    conf_path = os.path.join(settings.configs_dir, f"{name}.conf")
    if os.path.exists(conf_path):
        os.remove(conf_path)

    logger.info(f"ELIMINADO cliente={name} pubkey={pubkey}")
    return True


def get_client_config(name: str) -> str | None:
    """Obtener el contenido del archivo .conf de un cliente."""
    conf_path = os.path.join(settings.configs_dir, f"{name}.conf")
    if not os.path.exists(conf_path):
        return None
    with open(conf_path, "r") as f:
        return f.read()


def get_server_status() -> dict:
    """Obtener estado general del servidor VPN."""
    # Servicio
    service_status = _run("systemctl is-active wg-quick@wg0")

    # IP forwarding
    ip_forward = _run("cat /proc/sys/net/ipv4/ip_forward").strip()

    # UFW
    ufw_output = _run("ufw status 2>/dev/null || echo 'ufw not available'")
    ufw_wg = "51820" in ufw_output and "ALLOW" in ufw_output

    # Peers
    clients = list_clients()
    online = sum(1 for c in clients if c.status == "online")

    # Uptime
    uptime = _run("uptime -p")

    return {
        "service": service_status,
        "ip_forwarding": ip_forward == "1",
        "ufw_wireguard": ufw_wg,
        "total_clients": len(clients),
        "online_clients": online,
        "server_ip": settings.server_public_ip,
        "server_port": settings.server_port,
        "vpn_subnet": f"{settings.vpn_subnet}.0/24",
        "uptime": uptime,
        "wg_interface": settings.wg_interface,
    }
