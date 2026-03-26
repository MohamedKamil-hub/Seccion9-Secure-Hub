#!/bin/bash
# ============================================================
#  SECCION9 — WireGuard Manager
#  Gestión centralizada de usuarios VPN
#  Uso: sudo bash wg-manager.sh
#
#  ANTES DE USAR: ajusta las variables de configuración
#  de abajo con los datos reales de tu servidor.
# ============================================================

# === CONFIGURACIÓN — EDITAR ANTES DE USAR ===
WG_CONF="/etc/wireguard/wg0.conf"
WG_IFACE="wg0"
SERVER_IP="TU_IP_PUBLICA_VPS"
SERVER_PORT="51820"
SERVER_PUBKEY="TU_CLAVE_PUBLICA_SERVIDOR"
VPN_SUBNET="10.0.0"
CONFIGS_DIR="/etc/wireguard/clientes"
LOG_FILE="/var/log/seccion9-vpn.log"

# === COLORES ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# Funciones auxiliares
# ============================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] Ejecuta como root: sudo bash wg-manager.sh${NC}"
        exit 1
    fi
}

check_wireguard() {
    if ! command -v wg &> /dev/null; then
        echo -e "${RED}[!] WireGuard no está instalado.${NC}"
        echo -e "${YELLOW}    Ejecuta primero: sudo bash server/install-server.sh${NC}"
        exit 1
    fi
    if [[ ! -f "$WG_CONF" ]]; then
        echo -e "${RED}[!] No se encontró $WG_CONF${NC}"
        echo -e "${YELLOW}    Ejecuta primero: sudo bash server/install-server.sh${NC}"
        exit 1
    fi
}

check_config() {
    if [[ "$SERVER_IP" == "TU_IP_PUBLICA_VPS" ]] || [[ "$SERVER_PUBKEY" == "TU_CLAVE_PUBLICA_SERVIDOR" ]]; then
        echo -e "${RED}[!] Debes configurar las variables del servidor en wg-manager.sh${NC}"
        echo -e "${YELLOW}    Edita SERVER_IP y SERVER_PUBKEY con los valores reales.${NC}"
        echo ""
        echo -e "    Tu clave pública del servidor es:"
        echo -e "    ${GREEN}$(cat /etc/wireguard/server_public.key 2>/dev/null || echo 'No encontrada — ejecuta: sudo wg show')${NC}"
        echo ""
        exit 1
    fi
}

log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

siguiente_ip() {
    for i in $(seq 2 254); do
        if ! grep -q "AllowedIPs = ${VPN_SUBNET}.${i}/32" "$WG_CONF" 2>/dev/null; then
            echo "${VPN_SUBNET}.${i}"
            return
        fi
    done
    echo ""
}

separador() {
    echo -e "${CYAN}─────────────────────────────────────────${NC}"
}

# ============================================================
# 1. AÑADIR CLIENTE
# ============================================================

anadir_cliente() {
    echo ""
    separador
    echo -e "${BOLD}  AÑADIR NUEVO CLIENTE${NC}"
    separador
    echo ""

    read -p "Nombre del cliente (ej: moham, oficina-bcn): " NOMBRE
    NOMBRE=$(echo "$NOMBRE" | tr ' ' '_' | tr -cd '[:alnum:]_-')

    if [[ -z "$NOMBRE" ]]; then
        echo -e "${RED}[!] El nombre no puede estar vacío.${NC}"
        return
    fi

    if grep -q "# Cliente: $NOMBRE" "$WG_CONF" 2>/dev/null; then
        echo -e "${RED}[!] Ya existe un cliente con el nombre '$NOMBRE'.${NC}"
        return
    fi

    # Generar claves automáticamente
    PRIV=$(wg genkey)
    PUB=$(echo "$PRIV" | wg pubkey)

    # Asignar siguiente IP libre
    IP=$(siguiente_ip)
    if [[ -z "$IP" ]]; then
        echo -e "${RED}[!] No hay IPs disponibles en la subred ${VPN_SUBNET}.0/24${NC}"
        return
    fi

    echo ""
    echo -e "${YELLOW}[*] Registrando cliente: $NOMBRE${NC}"
    echo -e "    IP asignada:    ${GREEN}$IP${NC}"
    echo -e "    Clave pública:  ${GREEN}$PUB${NC}"
    echo ""

    # Añadir peer al archivo de configuración
    cat >> "$WG_CONF" << EOF

# Cliente: $NOMBRE
[Peer]
PublicKey = $PUB
AllowedIPs = ${IP}/32
EOF

    # Aplicar en caliente sin reiniciar el túnel
    wg set "$WG_IFACE" peer "$PUB" allowed-ips "${IP}/32"

    # Crear directorio de configs de clientes
    mkdir -p "$CONFIGS_DIR"

    # Generar archivo .conf completo para el cliente
    CONFIG_FILE="$CONFIGS_DIR/${NOMBRE}.conf"
    cat > "$CONFIG_FILE" << EOF
[Interface]
PrivateKey = $PRIV
Address = ${IP}/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = $SERVER_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    chmod 600 "$CONFIG_FILE"

    log_action "AÑADIDO cliente=$NOMBRE ip=$IP pubkey=$PUB"

    echo -e "${GREEN}[+] Cliente '$NOMBRE' registrado correctamente.${NC}"
    echo ""
    separador
    echo -e "${BOLD}  ARCHIVO .conf PARA ENVIAR AL CLIENTE${NC}"
    separador
    echo ""
    cat "$CONFIG_FILE"
    echo ""
    separador
    echo ""
    echo -e "${YELLOW}Archivo guardado en: $CONFIG_FILE${NC}"
    echo ""
    echo -e "${CYAN}Pasos para el cliente:${NC}"
    echo "  Windows → Importar este .conf en la GUI de WireGuard"
    echo "  Linux   → Copiar a /etc/wireguard/ y ejecutar: sudo wg-quick up seccion9"
    echo ""
}

# ============================================================
# 2. ELIMINAR CLIENTE
# ============================================================

eliminar_cliente() {
    echo ""
    separador
    echo -e "${BOLD}  ELIMINAR CLIENTE${NC}"
    separador

    listar_nombres

    echo ""
    read -p "Nombre del cliente a eliminar: " NOMBRE
    NOMBRE=$(echo "$NOMBRE" | tr ' ' '_' | tr -cd '[:alnum:]_-')

    if [[ -z "$NOMBRE" ]]; then
        echo -e "${RED}[!] El nombre no puede estar vacío.${NC}"
        return
    fi

    if ! grep -q "# Cliente: $NOMBRE" "$WG_CONF" 2>/dev/null; then
        echo -e "${RED}[!] No existe el cliente '$NOMBRE'.${NC}"
        return
    fi

    # Confirmar
    echo ""
    echo -e "${YELLOW}¿Seguro que quieres eliminar a '$NOMBRE'? Esto revoca su acceso VPN.${NC}"
    read -p "Escribe 'si' para confirmar: " CONFIRM
    if [[ "$CONFIRM" != "si" ]]; then
        echo -e "${YELLOW}Cancelado.${NC}"
        return
    fi

    # Obtener clave pública antes de borrar
    PUB=$(grep -A2 "# Cliente: $NOMBRE" "$WG_CONF" | grep "PublicKey" | awk '{print $3}')

    # Eliminar bloque del archivo de configuración
    sed -i "/# Cliente: $NOMBRE/,/AllowedIPs = .*\/32/{d}" "$WG_CONF"
    # Limpiar líneas vacías consecutivas
    sed -i '/^$/N;/^\n$/d' "$WG_CONF"

    # Eliminar peer en caliente
    if [[ -n "$PUB" ]]; then
        wg set "$WG_IFACE" peer "$PUB" remove 2>/dev/null
    fi

    # Eliminar archivo .conf del cliente
    rm -f "$CONFIGS_DIR/${NOMBRE}.conf"

    log_action "ELIMINADO cliente=$NOMBRE pubkey=$PUB"

    echo -e "${GREEN}[+] Cliente '$NOMBRE' eliminado. Acceso revocado.${NC}"
}

# ============================================================
# 3. LISTAR CLIENTES
# ============================================================

listar_nombres() {
    echo ""
    echo -e "${CYAN}Clientes registrados:${NC}"
    LISTA=$(grep "# Cliente:" "$WG_CONF" 2>/dev/null | sed 's/# Cliente: /  - /')
    if [[ -z "$LISTA" ]]; then
        echo "  (ninguno)"
    else
        echo "$LISTA"
    fi
}

listar_clientes() {
    echo ""
    separador
    echo -e "${BOLD}  CLIENTES VPN — ESTADO${NC}"
    separador
    echo ""

    CLIENTES=$(grep "# Cliente:" "$WG_CONF" 2>/dev/null | sed 's/# Cliente: //')

    if [[ -z "$CLIENTES" ]]; then
        echo "  No hay clientes registrados."
        echo ""
        echo -e "  Usa la opción ${GREEN}1)${NC} para añadir uno."
        return
    fi

    printf "  ${BOLD}%-20s %-15s %s${NC}\n" "NOMBRE" "IP" "ESTADO"
    echo "  ────────────────────────────────────────────────────"

    while IFS= read -r NOMBRE; do
        PUB=$(grep -A2 "# Cliente: $NOMBRE" "$WG_CONF" | grep "PublicKey" | awk '{print $3}')
        IP=$(grep -A3 "# Cliente: $NOMBRE" "$WG_CONF" | grep "AllowedIPs" | awk '{print $3}' | cut -d'/' -f1)

        # Comprobar último handshake
        HANDSHAKE=$(wg show "$WG_IFACE" latest-handshakes 2>/dev/null | grep "$PUB" | awk '{print $2}')

        if [[ -n "$HANDSHAKE" && "$HANDSHAKE" -gt 0 ]]; then
            HACE=$(( $(date +%s) - HANDSHAKE ))
            if [[ $HACE -lt 180 ]]; then
                ESTADO="${GREEN}● Conectado${NC} (hace ${HACE}s)"
            else
                MINS=$(( HACE / 60 ))
                ESTADO="${YELLOW}○ Inactivo${NC} (hace ${MINS}min)"
            fi
        else
            ESTADO="${RED}○ Sin conexión${NC}"
        fi

        printf "  %-20s %-15s " "$NOMBRE" "$IP"
        echo -e "$ESTADO"
    done <<< "$CLIENTES"

    echo ""
}

# ============================================================
# 4. VER CONFIG DE UN CLIENTE
# ============================================================

ver_config() {
    echo ""
    separador
    echo -e "${BOLD}  VER CONFIG DE CLIENTE${NC}"
    separador

    listar_nombres

    echo ""
    read -p "Nombre del cliente: " NOMBRE
    NOMBRE=$(echo "$NOMBRE" | tr ' ' '_' | tr -cd '[:alnum:]_-')

    CONFIG_FILE="$CONFIGS_DIR/${NOMBRE}.conf"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}[!] No se encontró config para '$NOMBRE'.${NC}"
        echo -e "${YELLOW}    (Solo disponible para clientes creados con este script)${NC}"
        return
    fi

    echo ""
    separador
    echo -e "${BOLD}  CONFIG — $NOMBRE${NC}"
    separador
    echo ""
    cat "$CONFIG_FILE"
    echo ""
    separador
}

# ============================================================
# 5. ESTADO DEL SERVIDOR
# ============================================================

estado_servidor() {
    echo ""
    separador
    echo -e "${BOLD}  ESTADO DEL SERVIDOR VPN${NC}"
    separador
    echo ""

    # Info del servidor
    echo -e "  ${CYAN}IP pública:${NC}     $SERVER_IP"
    echo -e "  ${CYAN}Puerto:${NC}         $SERVER_PORT/udp"
    echo -e "  ${CYAN}Clave pública:${NC}  $SERVER_PUBKEY"
    echo -e "  ${CYAN}Interfaz:${NC}       $WG_IFACE"
    echo -e "  ${CYAN}Subred VPN:${NC}     ${VPN_SUBNET}.0/24"
    echo ""

    # Estado del servicio
    STATUS=$(systemctl is-active wg-quick@wg0 2>/dev/null)
    if [[ "$STATUS" == "active" ]]; then
        echo -e "  Servicio:       ${GREEN}● Activo${NC}"
    else
        echo -e "  Servicio:       ${RED}● Inactivo${NC} ($STATUS)"
    fi

    # IP forwarding
    FWD=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
    if [[ "$FWD" == "1" ]]; then
        echo -e "  IP Forwarding:  ${GREEN}● Activo${NC}"
    else
        echo -e "  IP Forwarding:  ${RED}● Inactivo${NC}"
    fi

    # UFW
    UFW_WG=$(ufw status 2>/dev/null | grep "51820/udp" | grep "ALLOW")
    if [[ -n "$UFW_WG" ]]; then
        echo -e "  UFW 51820/udp:  ${GREEN}● Permitido${NC}"
    else
        echo -e "  UFW 51820/udp:  ${RED}● No encontrado${NC}"
    fi

    # Número de peers
    NUM_PEERS=$(grep -c "\[Peer\]" "$WG_CONF" 2>/dev/null || echo 0)
    echo -e "  Peers totales:  ${BOLD}$NUM_PEERS${NC}"

    echo ""
    separador
    echo -e "${BOLD}  WG SHOW${NC}"
    separador
    echo ""
    wg show 2>/dev/null || echo "  (No se pudo obtener info de WireGuard)"
    echo ""
}

# ============================================================
# MENÚ PRINCIPAL
# ============================================================

menu() {
    while true; do
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║   ${BOLD}SECCION9 — WireGuard Manager${NC}${CYAN}      ║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}1)${NC} Añadir cliente                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}2)${NC} Eliminar cliente                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}3)${NC} Listar clientes y estado         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}4)${NC} Ver config de un cliente          ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${CYAN}5)${NC} Estado del servidor               ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  6) Salir                            ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
        echo ""
        read -p "  Opción: " OPT

        case $OPT in
            1) anadir_cliente ;;
            2) eliminar_cliente ;;
            3) listar_clientes ;;
            4) ver_config ;;
            5) estado_servidor ;;
            6) echo -e "\n${GREEN}Hasta luego — SECCION9${NC}\n"; exit 0 ;;
            *) echo -e "${RED}Opción inválida.${NC}" ;;
        esac
    done
}

# ============================================================
# INICIO
# ============================================================

check_root
check_wireguard
check_config
menu
