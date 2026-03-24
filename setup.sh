#!/bin/bash
# ============================================================
#  SECCIÓN 9 — Cloud-Hub VPN MVP
#  Script maestro: genera claves, configs, construye y despliega
# ============================================================
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${PROJECT_DIR}/config"

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║  SECCIÓN 9 — Cloud-Hub VPN MVP              ║"
echo "║  Laboratorio Containerlab                    ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
#  PASO 1: Verificar dependencias
# ============================================================
echo -e "${BOLD}[1/5] Verificando dependencias...${NC}"

check_cmd() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}  ✗ $1 no encontrado. Instálalo antes de continuar.${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ $1${NC}"
}

check_cmd docker
check_cmd containerlab
check_cmd wg

echo ""

# ============================================================
#  PASO 2: Generar claves WireGuard
# ============================================================
echo -e "${BOLD}[2/5] Generando claves WireGuard...${NC}"

mkdir -p "${CONFIG_DIR}"
cd "${CONFIG_DIR}"

for node in hub spoke01 spoke02 spoke03; do
    if [ ! -f "${node}_private.key" ]; then
        wg genkey | tee "${node}_private.key" | wg pubkey > "${node}_public.key"
        chmod 600 "${node}_private.key"
        echo -e "${GREEN}  ✓ Claves generadas para ${node}${NC}"
    else
        echo -e "${YELLOW}  → Claves de ${node} ya existen (reutilizando)${NC}"
    fi
done

# Leer claves
HUB_PRIV=$(cat hub_private.key)
HUB_PUB=$(cat hub_public.key)
S01_PRIV=$(cat spoke01_private.key)
S01_PUB=$(cat spoke01_public.key)
S02_PRIV=$(cat spoke02_private.key)
S02_PUB=$(cat spoke02_public.key)
S03_PRIV=$(cat spoke03_private.key)
S03_PUB=$(cat spoke03_public.key)

echo ""

# ============================================================
#  PASO 3: Generar configuraciones WireGuard
# ============================================================
echo -e "${BOLD}[3/5] Generando configuraciones WireGuard...${NC}"

# Hub config
cat > hub_wg0.conf <<EOF
[Interface]
Address = 10.10.1.1/24
ListenPort = 51820
PrivateKey = ${HUB_PRIV}

# Spoke-01: Empleado Remoto
[Peer]
PublicKey = ${S01_PUB}
AllowedIPs = 10.10.1.10/32

# Spoke-02: PC Oficina
[Peer]
PublicKey = ${S02_PUB}
AllowedIPs = 10.10.1.20/32

# Spoke-03: Servidor Interno
[Peer]
PublicKey = ${S03_PUB}
AllowedIPs = 10.10.1.100/32
EOF
echo -e "${GREEN}  ✓ hub_wg0.conf${NC}"

# Spoke-01: Empleado Remoto (split-tunneling)
cat > spoke01_wg0.conf <<EOF
[Interface]
Address = 10.10.1.10/32
PrivateKey = ${S01_PRIV}

[Peer]
PublicKey = ${HUB_PUB}
Endpoint = 172.20.20.10:51820
AllowedIPs = 10.10.1.0/24
PersistentKeepalive = 25
EOF
echo -e "${GREEN}  ✓ spoke01_wg0.conf (Empleado Remoto — split-tunneling)${NC}"

# Spoke-02: PC Oficina
cat > spoke02_wg0.conf <<EOF
[Interface]
Address = 10.10.1.20/32
PrivateKey = ${S02_PRIV}

[Peer]
PublicKey = ${HUB_PUB}
Endpoint = 172.20.20.10:51820
AllowedIPs = 10.10.1.0/24
PersistentKeepalive = 25
EOF
echo -e "${GREEN}  ✓ spoke02_wg0.conf (PC Oficina)${NC}"

# Spoke-03: Servidor Interno
cat > spoke03_wg0.conf <<EOF
[Interface]
Address = 10.10.1.100/32
PrivateKey = ${S03_PRIV}

[Peer]
PublicKey = ${HUB_PUB}
Endpoint = 172.20.20.10:51820
AllowedIPs = 10.10.1.0/24
PersistentKeepalive = 25
EOF
echo -e "${GREEN}  ✓ spoke03_wg0.conf (Servidor Interno)${NC}"

echo ""

# ============================================================
#  PASO 4: Construir imágenes Docker
# ============================================================
echo -e "${BOLD}[4/5] Construyendo imágenes Docker...${NC}"

docker build -t clab-hub:latest "${PROJECT_DIR}/docker/hub" -q
echo -e "${GREEN}  ✓ clab-hub:latest${NC}"

docker build -t clab-spoke:latest "${PROJECT_DIR}/docker/spoke" -q
echo -e "${GREEN}  ✓ clab-spoke:latest${NC}"

docker build -t clab-dashboard:latest "${PROJECT_DIR}/docker/dashboard" -q
echo -e "${GREEN}  ✓ clab-dashboard:latest${NC}"

echo ""

# ============================================================
#  PASO 5: Desplegar Containerlab
# ============================================================
echo -e "${BOLD}[5/5] Desplegando laboratorio...${NC}"

cd "${PROJECT_DIR}"

# Destruir lab previo si existe
sudo containerlab destroy --topo topology.yml --cleanup 2>/dev/null || true

# Desplegar
sudo containerlab deploy --topo topology.yml

echo ""
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║  ✓ LABORATORIO DESPLEGADO                   ║"
echo "╠══════════════════════════════════════════════╣"
echo "║                                              ║"
echo "║  Dashboard:  http://localhost:3000            ║"
echo "║  Hub API:    http://172.20.20.10:8080         ║"
echo "║                                              ║"
echo "║  Para verificar:                             ║"
echo "║    ./scripts/test.sh                         ║"
echo "║                                              ║"
echo "║  Para destruir:                              ║"
echo "║    ./scripts/destroy.sh                      ║"
echo "║                                              ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"
