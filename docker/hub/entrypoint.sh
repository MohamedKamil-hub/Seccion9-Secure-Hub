#!/bin/bash
set -e

echo "============================================"
echo "  CLOUD-HUB VPN — Gateway Central (Hub)"
echo "  SECCIÓN 9 — MVP Containerlab"
echo "============================================"

# Habilitar forwarding
sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Levantar WireGuard
if [ -f /etc/wireguard/wg0.conf ]; then
    wg-quick up wg0
    echo "[OK] WireGuard activo en 10.10.1.1/24 (puerto 51820)"
else
    echo "[ERROR] No se encontró /etc/wireguard/wg0.conf"
    exit 1
fi

# Aplicar reglas de firewall base
/firewall.sh
echo "[OK] Firewall base aplicado"

# Levantar mini API de estado (puerto 8080)
python3 /api.py &
echo "[OK] API de estado en http://0.0.0.0:8080"

echo ""
echo "[HUB] Gateway operativo. Esperando conexiones de spokes..."
echo ""

# Mantener vivo
exec tail -f /dev/null
