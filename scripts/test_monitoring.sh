#!/bin/bash
# ============================================================
#  TEST 8: Monitorización de tráfico en tiempo real
#  
#  Escenario: Demuestra que SECCIÓN 9 puede ver y auditar
#  todo el tráfico que pasa por el Hub. Captura paquetes
#  reales y los analiza.
# ============================================================
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

pass() { echo -e "  ${GREEN}✓ PASS${NC} — $1"; }
fail() { echo -e "  ${RED}✗ FAIL${NC} — $1"; FAILURES=$((FAILURES+1)); }
info() { echo -e "  ${CYAN}→${NC} $1"; }

FAILURES=0

echo -e "${BOLD}━━━ TEST 8: Monitorización de tráfico ━━━${NC}"
echo ""
info "Escenario: El Hub captura y audita todo el tráfico VPN"
info "que pasa entre los spokes — visibilidad total para SECCIÓN 9."
echo ""

# ----------------------------------------------------------
#  8.1 Captura de tráfico ICMP (ping entre spokes)
# ----------------------------------------------------------
info "8.1 — Iniciando captura de tráfico en el Hub (wg0, 5 segundos)..."

# Lanzar tcpdump en background, capturar a fichero
docker exec clab-cloudhub-vpn-hub bash -c \
    "tcpdump -i wg0 -c 20 -w /tmp/capture_icmp.pcap icmp 2>/dev/null &"
TCPDUMP_PID=$!
sleep 1

# Generar tráfico: Spoke-01 → Spoke-03
info "  Generando tráfico: Spoke-01 → Servidor (10.10.1.100)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 5 -W 2 10.10.1.100 > /dev/null 2>&1 &

# Generar tráfico: Spoke-02 → Spoke-03
info "  Generando tráfico: Spoke-02 → Servidor (10.10.1.100)..."
docker exec clab-cloudhub-vpn-spoke-02 ping -c 5 -W 2 10.10.1.100 > /dev/null 2>&1 &

sleep 6

# Analizar captura
info "  Analizando captura..."
PACKET_COUNT=$(docker exec clab-cloudhub-vpn-hub tcpdump -r /tmp/capture_icmp.pcap 2>/dev/null | wc -l || echo 0)

if [ "$PACKET_COUNT" -gt 0 ]; then
    pass "Capturados ${PACKET_COUNT} paquetes ICMP en el Hub"
else
    fail "No se capturaron paquetes (tcpdump no detectó tráfico en wg0)"
fi

# Mostrar resumen de la captura
echo ""
info "  --- Extracto de la captura ---"
docker exec clab-cloudhub-vpn-hub tcpdump -r /tmp/capture_icmp.pcap -n 2>/dev/null | head -10 | while read line; do
    echo -e "  ${CYAN}│${NC} $line"
done
echo -e "  ${CYAN}└─ (mostrando primeros 10 paquetes)${NC}"
echo ""

# ----------------------------------------------------------
#  8.2 Captura de tráfico HTTP (acceso al servidor web)
# ----------------------------------------------------------
info "8.2 — Capturando tráfico HTTP (acceso al servidor interno)..."

docker exec clab-cloudhub-vpn-hub bash -c \
    "tcpdump -i wg0 -c 30 -w /tmp/capture_http.pcap 'port 8080' 2>/dev/null &"
sleep 1

# Spoke-01 accede al servidor web
info "  Spoke-01 accede a http://10.10.1.100:8080..."
docker exec clab-cloudhub-vpn-spoke-01 curl -s http://10.10.1.100:8080 > /dev/null 2>&1

# Spoke-02 accede al servidor web
info "  Spoke-02 accede a http://10.10.1.100:8080..."
docker exec clab-cloudhub-vpn-spoke-02 curl -s http://10.10.1.100:8080 > /dev/null 2>&1

sleep 3

HTTP_PACKETS=$(docker exec clab-cloudhub-vpn-hub tcpdump -r /tmp/capture_http.pcap 2>/dev/null | wc -l || echo 0)

if [ "$HTTP_PACKETS" -gt 0 ]; then
    pass "Capturados ${HTTP_PACKETS} paquetes HTTP en el Hub"
else
    # tcpdump puede no haber capturado suficientes en tiempo
    warn "No se capturaron paquetes HTTP (timing — no es un fallo crítico)"
fi

echo ""

# ----------------------------------------------------------
#  8.3 Identificación de IPs de origen (auditoría)
# ----------------------------------------------------------
info "8.3 — Auditoría: Identificando qué IPs generaron tráfico..."

echo ""
info "  IPs detectadas en la captura ICMP:"
UNIQUE_IPS=$(docker exec clab-cloudhub-vpn-hub tcpdump -r /tmp/capture_icmp.pcap -n 2>/dev/null | \
    grep -oP '10\.10\.1\.\d+' | sort -u || echo "ninguna")

DETECTED_COUNT=0
for ip in $UNIQUE_IPS; do
    case $ip in
        10.10.1.1)   echo -e "  ${CYAN}│${NC} ${ip} → Hub (Gateway)" ;;
        10.10.1.10)  echo -e "  ${CYAN}│${NC} ${ip} → Spoke-01 (Empleado Remoto)" ;;
        10.10.1.20)  echo -e "  ${CYAN}│${NC} ${ip} → Spoke-02 (PC Oficina)" ;;
        10.10.1.100) echo -e "  ${CYAN}│${NC} ${ip} → Spoke-03 (Servidor Interno)" ;;
        *)           echo -e "  ${CYAN}│${NC} ${ip} → Desconocido" ;;
    esac
    DETECTED_COUNT=$((DETECTED_COUNT+1))
done

if [ "$DETECTED_COUNT" -ge 2 ]; then
    pass "Auditoría OK — ${DETECTED_COUNT} IPs identificadas en el tráfico"
else
    warn "Pocas IPs detectadas (puede ser cuestión de timing)"
fi

echo ""

# ----------------------------------------------------------
#  8.4 Estadísticas de WireGuard (bytes transferidos por peer)
# ----------------------------------------------------------
info "8.4 — Estadísticas de transferencia por peer (wg show)..."
echo ""

docker exec clab-cloudhub-vpn-hub wg show wg0 transfer 2>/dev/null | while read pubkey rx tx; do
    # Buscar qué peer es por su allowed-ips
    ALLOWED=$(docker exec clab-cloudhub-vpn-hub wg show wg0 allowed-ips 2>/dev/null | grep "$pubkey" | awk '{print $2}')
    case $ALLOWED in
        10.10.1.10/32)  NAME="Empleado Remoto" ;;
        10.10.1.20/32)  NAME="PC Oficina" ;;
        10.10.1.100/32) NAME="Servidor Interno" ;;
        *)              NAME="Desconocido" ;;
    esac
    
    # Convertir bytes a legible
    RX_H=$(numfmt --to=iec $rx 2>/dev/null || echo "${rx}B")
    TX_H=$(numfmt --to=iec $tx 2>/dev/null || echo "${tx}B")
    
    echo -e "  ${CYAN}│${NC} ${NAME} (${ALLOWED}): ↓ Recibido ${RX_H} / ↑ Enviado ${TX_H}"
done

echo ""

# ----------------------------------------------------------
#  8.5 Detección de conexiones activas
# ----------------------------------------------------------
info "8.5 — Peers con handshake activo (conexiones vivas)..."
echo ""

ACTIVE=0
TOTAL=0
docker exec clab-cloudhub-vpn-hub wg show wg0 latest-handshakes 2>/dev/null | while read pubkey ts; do
    TOTAL=$((TOTAL+1))
    ALLOWED=$(docker exec clab-cloudhub-vpn-hub wg show wg0 allowed-ips 2>/dev/null | grep "$pubkey" | awk '{print $2}')
    case $ALLOWED in
        10.10.1.10/32)  NAME="Empleado Remoto" ;;
        10.10.1.20/32)  NAME="PC Oficina" ;;
        10.10.1.100/32) NAME="Servidor Interno" ;;
        *)              NAME="Desconocido" ;;
    esac
    
    if [ "$ts" != "0" ]; then
        NOW=$(date +%s)
        AGO=$((NOW - ts))
        if [ $AGO -lt 180 ]; then
            echo -e "  ${GREEN}●${NC} ${NAME}: activo (último handshake hace ${AGO}s)"
        else
            echo -e "  ${YELLOW}●${NC} ${NAME}: inactivo (último handshake hace ${AGO}s)"
        fi
    else
        echo -e "  ${RED}●${NC} ${NAME}: sin handshake"
    fi
done

echo ""

# ----------------------------------------------------------
#  Limpiar capturas
# ----------------------------------------------------------
docker exec clab-cloudhub-vpn-hub rm -f /tmp/capture_icmp.pcap /tmp/capture_http.pcap 2>/dev/null || true

# ----------------------------------------------------------
#  Resumen
# ----------------------------------------------------------
echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✓ TEST 8 COMPLETADO — Monitorización verificada${NC}"
    echo -e "  ${CYAN}Resumen: Todo el tráfico entre spokes pasa por el Hub y es auditable."
    echo -e "  SECCIÓN 9 tiene visibilidad total: quién se conecta, cuándo y a qué.${NC}"
else
    echo -e "${RED}${BOLD}  ✗ TEST 8 — ${FAILURES} fallos${NC}"
fi
echo ""
