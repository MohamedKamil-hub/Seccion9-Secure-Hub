#!/bin/bash
# ============================================================
#  SECCIÓN 9 — Cloud-Hub VPN MVP
#  Script de pruebas: VPN + Segmentación + Revocación
# ============================================================
set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

CONFIG_DIR="$(cd "$(dirname "$0")/../config" && pwd)"

pass() { echo -e "  ${GREEN}✓ PASS${NC} — $1"; }
fail() { echo -e "  ${RED}✗ FAIL${NC} — $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║  SECCIÓN 9 — Test Suite MVP                  ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
#  TEST 1: Estado de WireGuard
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

# ============================================================
#  TEST 2: Conectividad VPN
# ============================================================
echo -e "${BOLD}━━━ TEST 2: Conectividad entre peers ━━━${NC}"
echo ""

info "Spoke-01 (Empleado) → Hub (10.10.1.1)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.1 > /dev/null 2>&1 && pass "Spoke-01 → Hub" || fail "Spoke-01 → Hub"

info "Spoke-01 (Empleado) → Spoke-03 (Servidor 10.10.1.100)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-01 → Servidor" || fail "Spoke-01 → Servidor"

info "Spoke-02 (Oficina) → Spoke-03 (Servidor 10.10.1.100)..."
docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-02 → Servidor" || fail "Spoke-02 → Servidor"

info "Spoke-01 (Empleado) → Spoke-02 (Oficina 10.10.1.20)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.20 > /dev/null 2>&1 && pass "Spoke-01 → Spoke-02" || fail "Spoke-01 → Spoke-02"

echo ""

# ============================================================
#  TEST 3: Servidor interno accesible
# ============================================================
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
#  TEST 4: SEGMENTACIÓN — Bloquear Spoke-02 → Servidor
# ============================================================
echo -e "${BOLD}━━━ TEST 4: Segmentación de red ━━━${NC}"
echo ""

info "Aplicando regla: BLOQUEAR Spoke-02 (10.10.1.20) → Servidor (10.10.1.100)..."
docker exec clab-cloudhub-vpn-hub iptables -I FORWARD -s 10.10.1.20 -d 10.10.1.100 -j DROP
sleep 1

info "Spoke-02 → Servidor (debería FALLAR)..."
if ! docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 2 10.10.1.100 > /dev/null 2>&1; then
    pass "Spoke-02 BLOQUEADO correctamente (no puede alcanzar el servidor)"
else
    fail "Spoke-02 todavía puede alcanzar el servidor (la regla no funcionó)"
fi

info "Spoke-01 → Servidor (debería FUNCIONAR — no está afectado)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 2 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-01 NO afectado (acceso permitido)" || fail "Spoke-01 también bloqueado (error)"

info "Eliminando regla de bloqueo..."
docker exec clab-cloudhub-vpn-hub iptables -D FORWARD -s 10.10.1.20 -d 10.10.1.100 -j DROP

info "Spoke-02 → Servidor (debería FUNCIONAR de nuevo)..."
docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-02 RESTAURADO — acceso recuperado" || fail "Spoke-02 sigue bloqueado"

echo ""

# ============================================================
#  TEST 5: REVOCACIÓN — Eliminar peer Spoke-01
# ============================================================
echo -e "${BOLD}━━━ TEST 5: Revocación de acceso ━━━${NC}"
echo ""

S01_PUB=$(cat "${CONFIG_DIR}/spoke01_public.key")

info "Revocando peer Spoke-01 (Empleado Remoto)..."
docker exec clab-cloudhub-vpn-hub wg set wg0 peer "${S01_PUB}" remove
sleep 2

info "Spoke-01 → Hub (debería FALLAR — peer revocado)..."
if ! docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.1 > /dev/null 2>&1; then
    pass "Spoke-01 REVOCADO correctamente (sin acceso VPN)"
else
    fail "Spoke-01 todavía tiene acceso (la revocación no funcionó)"
fi

info "Spoke-02 → Servidor (debería FUNCIONAR — no está afectado)..."
docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-02 NO afectado" || fail "Spoke-02 también perdió acceso"

info "Restaurando peer Spoke-01..."
docker exec clab-cloudhub-vpn-hub wg set wg0 peer "${S01_PUB}" allowed-ips 10.10.1.10/32
sleep 3

info "Spoke-01 → Hub (debería FUNCIONAR de nuevo)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 3 -W 3 10.10.1.1 > /dev/null 2>&1 && pass "Spoke-01 RESTAURADO — acceso VPN recuperado" || warn "Spoke-01 tarda en reconectar (puede necesitar unos segundos más)"

echo ""
echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════╗"
echo "║  Tests completados                           ║"
echo "║                                              ║"
echo "║  Dashboard: http://localhost:3000             ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"
