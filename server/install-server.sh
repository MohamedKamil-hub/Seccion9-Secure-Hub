#!/bin/bash
# ============================================================
#  SECCION9 — WireGuard Server Setup
#  Uso: sudo bash install-server.sh
#  Probado en: Ubuntu 22.04 LTS
# ============================================================

WG_PORT=51820
WG_NETWORK="10.0.0.0/24"
SERVER_IP="10.0.0.1"
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   SECCION9 — WireGuard Server Setup       ${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   Interfaz de red detectada: $INTERFACE   ${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Ejecuta como root: sudo bash install-server.sh${NC}"
    exit 1
fi

# --- 1. Instalar WireGuard ---
echo -e "${YELLOW}[1/5] Instalando WireGuard...${NC}"
apt update && apt install -y wireguard wireguard-tools ufw
echo -e "${GREEN}[+] Instalado.${NC}"

# --- 2. Generar claves ---
echo -e "${YELLOW}[2/5] Generando claves del servidor...${NC}"
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
chmod 600 /etc/wireguard/server_private.key
SERVER_PRIV=$(cat /etc/wireguard/server_private.key)
SERVER_PUB=$(cat /etc/wireguard/server_public.key)
echo -e "${GREEN}[+] Claves generadas.${NC}"

# --- 3. Crear configuracion ---
echo -e "${YELLOW}[3/5] Creando configuracion wg0...${NC}"
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = ${SERVER_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}

PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; \
           iptables -A FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -A POSTROUTING -o ${INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; \
           iptables -D FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE

# === PEERS (añadir con add-client.sh) ===
EOF
chmod 600 /etc/wireguard/wg0.conf
echo -e "${GREEN}[+] Configuracion creada.${NC}"

# --- 4. IP forwarding ---
echo -e "${YELLOW}[4/5] Activando IP forwarding...${NC}"
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p
echo -e "${GREEN}[+] IP forwarding activo.${NC}"

# --- 5. UFW y servicio ---
echo -e "${YELLOW}[5/5] Configurando UFW y servicio...${NC}"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow ${WG_PORT}/udp
ufw --force enable
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
echo -e "${GREEN}[+] UFW configurado y WireGuard activo.${NC}"

# --- Resultado ---
echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}   INSTALACION COMPLETADA${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""
echo -e " Clave publica del servidor:"
echo -e " ${GREEN}${SERVER_PUB}${NC}"
echo ""
echo -e " ${YELLOW}IMPORTANTE:${NC}"
echo -e " 1. Guarda esta clave publica — la necesitan los clientes"
echo -e " 2. Abre el puerto UDP ${WG_PORT} en el firewall del proveedor (Ionos, etc.)"
echo -e " 3. Usa add-client.sh para registrar nuevos clientes"
echo ""
sudo wg show
