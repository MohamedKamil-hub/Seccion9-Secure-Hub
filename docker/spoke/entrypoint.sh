#!/bin/bash
set -e

NODE_NAME="${NODE_NAME:-spoke}"
NODE_ROLE="${NODE_ROLE:-spoke}"

echo "============================================"
echo "  CLOUD-HUB VPN — Spoke: ${NODE_NAME}"
echo "  SECCIÓN 9 — MVP Containerlab"
echo "============================================"

# Levantar WireGuard
if [ -f /etc/wireguard/wg0.conf ]; then
    wg-quick up wg0
    WG_IP=$(ip -4 addr show wg0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
    echo "[OK] WireGuard activo — IP VPN: ${WG_IP}"
else
    echo "[ERROR] No se encontró /etc/wireguard/wg0.conf"
    exit 1
fi

# Si es el servidor interno, levantar un servicio HTTP de ejemplo
if [ "${NODE_ROLE}" = "servidor" ]; then
    mkdir -p /var/www
    cat > /var/www/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>Servidor Interno PYME</title></head>
<body style="font-family:sans-serif;text-align:center;padding:60px;background:#0a1628;color:#e0e0e0;">
<h1 style="color:#00d4ff;">Servidor Interno — Red Corporativa</h1>
<p>Este recurso solo es accesible a través de la VPN de SECCIÓN 9.</p>
<p style="color:#4ade80;font-size:1.2em;">✓ Conexión verificada a través del túnel WireGuard</p>
<hr style="border-color:#1e3a5f;">
<p style="font-size:0.9em;color:#888;">IP de acceso: 10.10.1.100 | Puerto: 8080</p>
</body>
</html>
HTMLEOF
    cd /var/www && python3 -m http.server 8080 &
    echo "[OK] Servidor HTTP interno activo en :8080"
fi

echo ""
echo "[${NODE_NAME}] Nodo operativo."
echo ""

exec tail -f /dev/null
