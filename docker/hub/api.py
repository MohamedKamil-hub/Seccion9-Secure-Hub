#!/usr/bin/env python3
"""
Mini API de estado del Hub — Puerto 8080
Devuelve información de peers WireGuard y reglas de firewall en JSON.
Usada por el dashboard de monitorización.
"""

import http.server
import json
import subprocess
import re
from datetime import datetime


def get_wg_status():
    """Parsea la salida de 'wg show' y devuelve datos estructurados."""
    try:
        raw = subprocess.check_output(["wg", "show", "wg0", "dump"], text=True).strip()
    except Exception:
        return {"error": "WireGuard no disponible", "peers": []}

    lines = raw.split("\n")
    if not lines:
        return {"error": "Sin datos", "peers": []}

    # Primera línea: interfaz
    iface_parts = lines[0].split("\t")
    peers = []

    # Nombres asignados por IP
    peer_names = {
        "10.10.1.10/32": {"name": "Empleado Remoto", "id": "spoke-01"},
        "10.10.1.20/32": {"name": "PC Oficina", "id": "spoke-02"},
        "10.10.1.100/32": {"name": "Servidor Interno", "id": "spoke-03"},
    }

    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) >= 8:
            allowed_ips = parts[3]
            info = peer_names.get(allowed_ips, {"name": "Desconocido", "id": "unknown"})
            last_handshake = int(parts[4]) if parts[4] != "0" else 0
            rx_bytes = int(parts[5])
            tx_bytes = int(parts[6])

            if last_handshake > 0:
                elapsed = int(datetime.now().timestamp()) - last_handshake
                status = "conectado" if elapsed < 180 else "inactivo"
            else:
                status = "sin conexión"

            peers.append({
                "public_key": parts[0][:16] + "...",
                "endpoint": parts[2] if parts[2] != "(none)" else "—",
                "allowed_ips": allowed_ips,
                "name": info["name"],
                "node_id": info["id"],
                "status": status,
                "last_handshake_secs_ago": elapsed if last_handshake > 0 else None,
                "rx_bytes": rx_bytes,
                "tx_bytes": tx_bytes,
            })

    return {
        "hub_ip": "10.10.1.1",
        "interface": "wg0",
        "listen_port": 51820,
        "peer_count": len(peers),
        "peers": peers,
        "timestamp": datetime.now().isoformat(),
    }


def get_firewall_rules():
    """Devuelve las reglas de iptables FORWARD activas."""
    try:
        raw = subprocess.check_output(
            ["iptables", "-L", "FORWARD", "-n", "-v", "--line-numbers"],
            text=True
        ).strip()
    except Exception:
        return {"error": "iptables no disponible", "rules": []}

    rules = []
    for line in raw.split("\n")[2:]:  # skip headers
        parts = line.split()
        if len(parts) >= 10:
            rules.append({
                "num": parts[0],
                "pkts": parts[1],
                "bytes": parts[2],
                "target": parts[3],
                "proto": parts[4],
                "source": parts[8],
                "destination": parts[9],
            })

    return {"rules": rules}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Silenciar logs

    def _send_json(self, data, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())

    def do_GET(self):
        if self.path == "/api/status":
            self._send_json(get_wg_status())
        elif self.path == "/api/firewall":
            self._send_json(get_firewall_rules())
        elif self.path == "/api/health":
            self._send_json({"status": "ok", "service": "Cloud-Hub VPN Gateway"})
        else:
            self._send_json({"endpoints": ["/api/status", "/api/firewall", "/api/health"]})


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", 8080), Handler)
    server.serve_forever()
