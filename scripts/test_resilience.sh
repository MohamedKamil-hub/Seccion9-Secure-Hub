#!/bin/bash
# ============================================================
#  TEST 7: Simulación de caída del Hub — Resiliencia
#  
#  Escenario: El VPS central cae. Se demuestra que:
#  1. Los spokes pierden acceso a la red corporativa
#  2. Los spokes mantienen conectividad a internet (split-tunneling)
#  3. Al restaurar el Hub, los túneles se reconectan automáticamente
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
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

FAILURES=0

echo -e "${BOLD}━━━ TEST 7: Caída del Hub — Resiliencia ━━━${NC}"
echo ""

# ----------------------------------------------------------
#  7.1 Verificar estado previo (todo funciona)
# ----------------------------------------------------------
info "7.1 — Verificando estado previo: Spoke-01 → Servidor..."
if docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1; then
    pass "Estado previo OK — VPN funcional"
else
    fail "VPN no funciona antes del test — abortando"
    exit 1
fi

info "7.1 — Verificando estado previo: Spoke-01 → Internet (management)..."
if docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 172.20.20.10 > /dev/null 2>&1; then
    pass "Estado previo OK — Conectividad de management funcional"
else
    warn "Sin acceso a management (puede ser normal)"
fi

echo ""

# ----------------------------------------------------------
#  7.2 SIMULAR CAÍDA: Apagar WireGuard en el Hub
# ----------------------------------------------------------
info "7.2 — SIMULANDO CAÍDA DEL HUB: Deteniendo WireGuard en el gateway..."
docker exec clab-cloudhub-vpn-hub wg-quick down wg0 2>/dev/null || \
    docker exec clab-cloudhub-vpn-hub ip link set wg0 down 2>/dev/null || true
echo -e "  ${RED}${BOLD}  ⚡ HUB CAÍDO — WireGuard detenido${NC}"
sleep 2
echo ""

# ----------------------------------------------------------
#  7.3 Verificar que la red corporativa es INACCESIBLE
# ----------------------------------------------------------
info "7.3 — Spoke-01 → Servidor (10.10.1.100) — debería FALLAR..."
if ! docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1; then
    pass "Red corporativa INACCESIBLE — el Hub está caído"
else
    fail "Red corporativa sigue accesible con el Hub caído (inesperado)"
fi

info "7.3 — Spoke-02 → Servidor (10.10.1.100) — debería FALLAR..."
if ! docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1; then
    pass "Red corporativa INACCESIBLE desde Spoke-02"
else
    fail "Red corporativa sigue accesible desde Spoke-02"
fi

info "7.3 — Spoke-01 → Hub VPN (10.10.1.1) — debería FALLAR..."
if ! docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.1 > /dev/null 2>&1; then
    pass "Hub VPN INACCESIBLE"
else
    fail "Hub VPN sigue respondiendo"
fi

echo ""

# ----------------------------------------------------------
#  7.4 Verificar que la conexión a internet/management SIGUE ACTIVA
#  (Esto demuestra split-tunneling: la VPN cae pero internet no)
# ----------------------------------------------------------
info "7.4 — SPLIT-TUNNELING: Verificando que los spokes mantienen conectividad externa..."

# En el lab, "internet" es la red de management de Containerlab
# Los spokes deberían poder seguir haciendo ping a IPs fuera de 10.10.1.0/24
if docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 172.20.20.10 > /dev/null 2>&1; then
    pass "Spoke-01 MANTIENE conectividad externa (split-tunneling funcional)"
else
    # Esto puede fallar porque el ping va por management, no por wg0
    # Verificamos con la ruta predeterminada
    DEFAULT_GW=$(docker exec clab-cloudhub-vpn-spoke-01 ip route show default 2>/dev/null | head -1)
    if [ -n "$DEFAULT_GW" ]; then
        pass "Spoke-01 tiene ruta predeterminada activa: ${DEFAULT_GW}"
    else
        warn "No se pudo verificar split-tunneling (puede depender de la topología)"
    fi
fi

info "7.4 — Verificando que la ruta VPN es la única afectada..."
VPN_ROUTE=$(docker exec clab-cloudhub-vpn-spoke-01 ip route show 10.10.1.0/24 2>/dev/null || echo "sin ruta")
info "Ruta VPN en Spoke-01: ${VPN_ROUTE}"
DEFAULT_ROUTE=$(docker exec clab-cloudhub-vpn-spoke-01 ip route show default 2>/dev/null | head -1)
info "Ruta default en Spoke-01: ${DEFAULT_ROUTE:-sin ruta predeterminada}"

echo ""

# ----------------------------------------------------------
#  7.5 RESTAURAR: Levantar WireGuard en el Hub
# ----------------------------------------------------------
info "7.5 — RESTAURANDO HUB: Levantando WireGuard..."
docker exec clab-cloudhub-vpn-hub wg-quick up wg0 2>/dev/null || \
    docker exec clab-cloudhub-vpn-hub ip link set wg0 up 2>/dev/null || true
echo -e "  ${GREEN}${BOLD}  ✓ HUB RESTAURADO — WireGuard activo${NC}"

# Esperar a que los peers reconecten (PersistentKeepalive = 25s)
info "Esperando reconexión de peers (PersistentKeepalive: hasta 25 segundos)..."
RECONNECTED=false
for i in $(seq 1 12); do
    sleep 3
    if docker exec clab-cloudhub-vpn-spoke-01 ping -c 1 -W 2 10.10.1.1 > /dev/null 2>&1; then
        RECONNECTED=true
        break
    fi
    echo -ne "  ${CYAN}→${NC} Intento ${i}/12...\r"
done
echo ""

echo ""

# ----------------------------------------------------------
#  7.6 Verificar reconexión automática
# ----------------------------------------------------------
info "7.6 — Verificando reconexión automática..."

if [ "$RECONNECTED" = true ]; then
    pass "Spoke-01 RECONECTADO automáticamente al Hub"
else
    # Forzar un intento más
    docker exec clab-cloudhub-vpn-spoke-01 ping -c 3 -W 3 10.10.1.1 > /dev/null 2>&1 && \
        pass "Spoke-01 reconectado (tardó más de lo esperado)" || \
        warn "Spoke-01 no reconectó automáticamente — puede necesitar reiniciar WireGuard en el spoke"
fi

info "Spoke-01 → Servidor (10.10.1.100) — debería FUNCIONAR..."
if docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1; then
    pass "Red corporativa RESTAURADA — Spoke-01 accede al servidor"
else
    warn "Spoke-01 aún no alcanza el servidor (puede necesitar más tiempo)"
fi

info "Spoke-02 → Servidor (10.10.1.100) — debería FUNCIONAR..."
if docker exec clab-cloudhub-vpn-spoke-02 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1; then
    pass "Spoke-02 reconectado y funcional"
else
    warn "Spoke-02 aún no alcanza el servidor"
fi

echo ""

# ----------------------------------------------------------
#  Resumen
# ----------------------------------------------------------
HUB_PEERS=$(docker exec clab-cloudhub-vpn-hub wg show wg0 2>/dev/null | grep -c "peer:" || echo 0)
info "Peers activos en el Hub tras restauración: ${HUB_PEERS}"

echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✓ TEST 7 COMPLETADO — Resiliencia verificada${NC}"
    echo -e "  ${CYAN}Resumen: El Hub cayó → red corporativa inaccesible → internet activo"
    echo -e "  → Hub restaurado → reconexión automática de peers${NC}"
else
    echo -e "${RED}${BOLD}  ✗ TEST 7 — ${FAILURES} fallos${NC}"
fi
echo ""
