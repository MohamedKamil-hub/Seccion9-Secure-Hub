#!/bin/bash
# ============================================================
#  SECCION9 — Despliegue del Panel de Gestión VPN
#  Uso: sudo bash deploy.sh
#  Requisitos: Docker + Docker Compose instalados
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   SECCION9 — Panel VPN — Despliegue     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[!] Ejecuta como root: sudo bash deploy.sh${NC}"
    exit 1
fi

# Verificar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}[*] Instalando Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}[+] Docker instalado.${NC}"
fi

if ! command -v docker compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}[!] Docker Compose no disponible. Instálalo: apt install docker-compose-plugin${NC}"
    exit 1
fi

# Crear directorios necesarios
echo -e "${YELLOW}[*] Preparando directorios...${NC}"
mkdir -p /var/log/seccion9
mkdir -p /etc/wireguard/clientes
mkdir -p nginx/certs

# Verificar que el docker-compose.yml tiene contraseñas cambiadas
if grep -q "CAMBIAME" docker-compose.yml; then
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}  ¡ATENCIÓN! Debes cambiar las contraseñas por defecto    ${NC}"
    echo -e "${RED}  en docker-compose.yml antes de desplegar:               ${NC}"
    echo -e "${RED}                                                          ${NC}"
    echo -e "${RED}  - ADMIN_PASSWORD                                        ${NC}"
    echo -e "${RED}  - SECRET_KEY                                            ${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Edita docker-compose.yml y vuelve a ejecutar deploy.sh${NC}"
    exit 1
fi

# Abrir puerto del panel en UFW si está activo
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}[*] Configurando UFW...${NC}"
    ufw allow 80/tcp
    ufw allow 443/tcp
    echo -e "${GREEN}[+] Puertos 80 y 443 abiertos.${NC}"
fi

# Build y arrancar
echo -e "${YELLOW}[*] Construyendo contenedores...${NC}"
docker compose build --no-cache

echo -e "${YELLOW}[*] Arrancando servicios...${NC}"
docker compose up -d

# Esperar a que arranque
sleep 5

# Verificar
echo ""
if docker compose ps | grep -q "Up"; then
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   PANEL DESPLEGADO CORRECTAMENTE         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Panel web:  ${CYAN}http://TU_IP_PUBLICA${NC}"
    echo -e "  API docs:   ${CYAN}http://TU_IP_PUBLICA/api/docs${NC}"
    echo ""
    echo -e "  ${YELLOW}Siguiente paso: configura HTTPS con certbot${NC}"
    echo ""
else
    echo -e "${RED}[!] Algo falló. Revisa los logs:${NC}"
    echo "    docker compose logs"
fi
