#!/bin/bash
# ============================================================
#  SECCION9 — WireGuard Client Setup for Linux
#  Uso: sudo bash setup-linux.sh
# ============================================================
#
#  ANTES DE DISTRIBUIR: reemplaza los valores de abajo
#  con los de tu servidor:
#
#    SERVER_PUBKEY  → clave pública de tu servidor (wg show en el VPS)
#    SERVER_ENDPOINT → IP_publica_del_VPS:51820
#
# ============================================================

SERVER_PUBKEY="TU_CLAVE_PUBLICA_SERVIDOR"
SERVER_ENDPOINT="TU_IP_VPS:51820"
TUNNEL_NAME="seccion9"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   SECCION9 — VPN WireGuard Setup Linux   ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Ejecuta como root: sudo bash setup-linux.sh${NC}"
    exit 1
fi

# --- 1. Instalar WireGuard ---
if ! command -v wg &> /dev/null; then
    echo -e "${YELLOW}[*] Instalando WireGuard...${NC}"
    apt update && apt install -y wireguard wireguard-tools resolvconf
    echo -e "${GREEN}[+] WireGuard instalado.${NC}"
else
    echo -e "${GREEN}[+] WireGuard ya instalado.${NC}"
fi

# --- 2. Pedir IP asignada ---
echo ""
echo "Pregunta a tu administrador de SECCION9 qué IP te han asignado."
read -p "Introduce tu IP VPN asignada (ej: 10.0.0.2): " CLIENT_IP

# --- 3. Generar claves ---
echo ""
echo -e "${YELLOW}[*] Generando par de claves...${NC}"
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

echo -e "${GREEN}[+] Claves generadas.${NC}"
echo ""
echo -e "${YELLOW}======================================================${NC}"
echo -e "${YELLOW} IMPORTANTE: Envía esta clave pública a SECCION9:${NC}"
echo -e " $PUBLIC_KEY"
echo -e "${YELLOW}======================================================${NC}"
echo ""

# --- 4. Crear configuracion ---
cat > /etc/wireguard/${TUNNEL_NAME}.conf << EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = ${CLIENT_IP}/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = $SERVER_ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/${TUNNEL_NAME}.conf
echo -e "${GREEN}[+] Configuracion guardada en /etc/wireguard/${TUNNEL_NAME}.conf${NC}"

echo ""
echo -e "${CYAN}[*] Pasos siguientes:${NC}"
echo "    1. Envía tu clave pública a SECCION9 (mostrada arriba)"
echo "    2. Espera confirmación de que está registrada en el servidor"
echo "    3. Activa el túnel:"
echo ""
echo "       sudo wg-quick up $TUNNEL_NAME"
echo ""
echo "    4. Verifica conexión:"
echo ""
echo "       sudo wg show"
echo "       ping 10.0.0.1"
echo ""
echo -e "${GREEN}Setup completado.${NC}"
