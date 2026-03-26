#!/bin/bash
# ============================================================
#  SECCION9 — Añadir nuevo cliente al servidor WireGuard
#  Uso: sudo bash add-client.sh <nombre> <clave_publica> <ip>
#  Ej:  sudo bash add-client.sh moham CMvCw4g...= 10.0.0.2
# ============================================================

CLIENT_NAME=$1
CLIENT_PUBKEY=$2
CLIENT_IP=$3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$CLIENT_NAME" ] || [ -z "$CLIENT_PUBKEY" ] || [ -z "$CLIENT_IP" ]; then
    echo -e "${RED}Uso: sudo bash add-client.sh <nombre> <clave_publica> <ip_asignada>${NC}"
    echo ""
    echo "Ejemplo:"
    echo "  sudo bash add-client.sh moham CMvCw4gSxdv5xwkgx...= 10.0.0.2"
    exit 1
fi

echo ""
echo -e "${YELLOW}[*] Registrando cliente: $CLIENT_NAME ($CLIENT_IP)...${NC}"

# Añadir peer activo sin reiniciar
wg set wg0 peer "$CLIENT_PUBKEY" allowed-ips "${CLIENT_IP}/32"

# Añadir al archivo de configuracion
cat >> /etc/wireguard/wg0.conf << EOF

# Cliente: $CLIENT_NAME
[Peer]
PublicKey = $CLIENT_PUBKEY
AllowedIPs = ${CLIENT_IP}/32
EOF

# Guardar configuracion activa
wg-quick save wg0

echo -e "${GREEN}[+] Cliente $CLIENT_NAME registrado con IP ${CLIENT_IP}.${NC}"
echo ""
echo "Estado actual del servidor:"
sudo wg show
