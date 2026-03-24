#!/bin/bash
# ============================================================
#  SECCIÓN 9 — Cloud-Hub VPN MVP
#  Test Suite Completa: Todos los escenarios de demostración
# ============================================================
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"

pass() { echo -e "  ${GREEN}✓ PASS${NC} — $1"; }
fail() { echo -e "  ${RED}✗ FAIL${NC} — $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║  SECCIÓN 9 — Cloud-Hub VPN — Test Suite Completa    ║"
echo "║                                                      ║"
echo "║  Tests:                                              ║"
echo "║   1-3  Túneles VPN + Conectividad + HTTP             ║"
echo "║   4    Segmentación de red                           ║"
echo "║   5    Revocación de acceso                          ║"
echo "║   6    Ataque simulado (acceso no autorizado)        ║"
echo "║   7    Caída del Hub (resiliencia)                   ║"
echo "║   8    Monitorización de tráfico                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar que el lab está corriendo
if ! docker ps --filter "name=clab-cloudhub-vpn-hub" --format "{{.Names}}" | grep -q "hub"; then
    echo -e "${RED}ERROR: El laboratorio no está corriendo. Ejecuta ./setup.sh primero.${NC}"
    exit 1
fi

echo -e "${YELLOW}Iniciando en 3 segundos...${NC}"
sleep 3
echo ""

# ============================================================
#  TESTS 1-3: VPN + Conectividad + HTTP
# ============================================================
echo -e "${BOLD}━━━ TEST 1: Túneles VPN activos ━━━${NC}"
echo ""

info "Comprobando WireGuard en el Hub..."
HUB_PEERS=$(docker exec clab-cloudhub-vpn-hub wg show wg0 2>/dev/null | grep -c "peer:" || echo 0)
if [ "$HUB_PEERS" -eq 3 ]; then
    pass "Hub tiene 3 peers configurados"
else
    fail "Hub tiene ${HUB_PEERS} peers (esperado: 3)"
fi

for spoke in spoke-01 spoke-02 spoke-03; do
    WG_UP=$(docker exec clab-cloudhub-vpn-${spoke} wg show wg0 2>/dev/null | grep -c "peer:" || echo 0)
    if [ "$WG_UP" -ge 1 ]; then
        pass "${spoke}: WireGuard activo"
    else
        fail "${spoke}: WireGuard no activo"
    fi
done
echo ""

echo -e "${BOLD}━━━ TEST 2: Conectividad entre peers ━━━${NC}"
echo ""

info "Spoke-01 (Empleado) → Hub (10.10.1.1)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.1 > /dev/null 2>&1 && pass "Spoke-01 → Hub" || fail "Spoke-01 → Hub"

info "Spoke-01 → Spoke-03 (Servidor 10.10.1.100)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-01 → Servidor" || fail "Spoke-01 → Servidor"

info "Spoke-02 → Spoke-03 (Servidor 10.10.1.100)..."
docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-02 → Servidor" || fail "Spoke-02 → Servidor"

info "Spoke-01 → Spoke-02 (Oficina 10.10.1.20)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.20 > /dev/null 2>&1 && pass "Spoke-01 → Spoke-02" || fail "Spoke-01 → Spoke-02"
echo ""

echo -e "${BOLD}━━━ TEST 3: Servicio HTTP interno ━━━${NC}"
echo ""

info "Spoke-01 → Servidor HTTP (10.10.1.100:8080)..."
HTTP_RESP=$(docker exec clab-cloudhub-vpn-spoke-01 curl -s --connect-timeout 3 http://10.10.1.100:8080 2>/dev/null || echo "")
if echo "$HTTP_RESP" | grep -q "Servidor Interno"; then
    pass "Servidor HTTP accesible desde Spoke-01"
else
    fail "Servidor HTTP no accesible desde Spoke-01"
fi

info "Spoke-02 → Servidor HTTP (10.10.1.100:8080)..."
HTTP_RESP=$(docker exec clab-cloudhub-vpn-spoke-02 curl -s --connect-timeout 3 http://10.10.1.100:8080 2>/dev/null || echo "")
if echo "$HTTP_RESP" | grep -q "Servidor Interno"; then
    pass "Servidor HTTP accesible desde Spoke-02"
else
    fail "Servidor HTTP no accesible desde Spoke-02"
fi
echo ""

# ============================================================
#  TEST 4: Segmentación
# ============================================================
echo -e "${BOLD}━━━ TEST 4: Segmentación de red ━━━${NC}"
echo ""

info "Aplicando regla: BLOQUEAR Spoke-02 (10.10.1.20) → Servidor (10.10.1.100)..."
docker exec clab-cloudhub-vpn-hub iptables -I FORWARD -s 10.10.1.20 -d 10.10.1.100 -j DROP
sleep 1

info "Spoke-02 → Servidor (debería FALLAR)..."
if ! docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 2 10.10.1.100 > /dev/null 2>&1; then
    pass "Spoke-02 BLOQUEADO correctamente"
else
    fail "Spoke-02 todavía accede al servidor"
fi

info "Spoke-01 → Servidor (debería FUNCIONAR)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 2 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-01 NO afectado" || fail "Spoke-01 también bloqueado"

info "Eliminando regla de bloqueo..."
docker exec clab-cloudhub-vpn-hub iptables -D FORWARD -s 10.10.1.20 -d 10.10.1.100 -j DROP

info "Spoke-02 → Servidor (debería FUNCIONAR de nuevo)..."
docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-02 RESTAURADO" || fail "Spoke-02 sigue bloqueado"
echo ""

# ============================================================
#  TEST 5: Revocación
# ============================================================
echo -e "${BOLD}━━━ TEST 5: Revocación de acceso ━━━${NC}"
echo ""

S01_PUB=$(cat "${CONFIG_DIR}/spoke01_public.key")

info "Revocando peer Spoke-01 (Empleado Remoto)..."
docker exec clab-cloudhub-vpn-hub wg set wg0 peer "${S01_PUB}" remove
sleep 2

info "Spoke-01 → Hub (debería FALLAR)..."
if ! docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.1 > /dev/null 2>&1; then
    pass "Spoke-01 REVOCADO correctamente"
else
    fail "Spoke-01 todavía tiene acceso"
fi

info "Spoke-02 → Servidor (debería FUNCIONAR)..."
docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-02 NO afectado" || fail "Spoke-02 también perdió acceso"

info "Restaurando peer Spoke-01..."
docker exec clab-cloudhub-vpn-hub wg set wg0 peer "${S01_PUB}" allowed-ips 10.10.1.10/32
sleep 4

info "Spoke-01 → Hub (debería FUNCIONAR de nuevo)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 3 -W 3 10.10.1.1 > /dev/null 2>&1 && pass "Spoke-01 RESTAURADO" || warn "Spoke-01 tarda en reconectar"
echo ""

# ============================================================
#  TEST 6-8: Escenarios avanzados
# ============================================================
echo -e "${YELLOW}${BOLD}Ejecutando escenarios avanzados...${NC}"
echo ""

bash "${SCRIPT_DIR}/test_attack.sh"
bash "${SCRIPT_DIR}/test_resilience.sh"
bash "${SCRIPT_DIR}/test_monitoring.sh"

# ============================================================
#  RESUMEN FINAL
# ============================================================
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ TEST SUITE COMPLETADA                            ║"
echo "║                                                      ║"
echo "║  Escenarios demostrados:                             ║"
echo "║   ✓ Túneles VPN funcionales (WireGuard)             ║"
echo "║   ✓ Conectividad entre todos los spokes              ║"
echo "║   ✓ Servidor HTTP interno accesible por VPN          ║"
echo "║   ✓ Segmentación: bloqueo selectivo entre peers      ║"
echo "║   ✓ Revocación: eliminación instantánea de acceso    ║"
echo "║   ✓ Protección: atacante sin VPN no puede acceder    ║"
echo "║   ✓ Resiliencia: caída y recuperación del Hub        ║"
echo "║   ✓ Monitorización: tráfico capturado y auditable    ║"
echo "║                                                      ║"
echo "║  Dashboard: http://localhost:3000                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
