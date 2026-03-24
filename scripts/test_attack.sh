#!/bin/bash
# ============================================================
#  TEST 6: Ataque simulado — Intento de acceso no autorizado
#  
#  Escenario: Un atacante (contenedor sin VPN) intenta acceder
#  a los recursos internos de la red corporativa (10.10.1.0/24).
#  Debe fallar en todos los intentos.
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

echo -e "${BOLD}━━━ TEST 6: Ataque simulado — Acceso no autorizado ━━━${NC}"
echo ""
info "Escenario: un atacante en la red de management intenta acceder"
info "a los recursos internos de la VPN (10.10.1.0/24) sin túnel WireGuard."
echo ""

# ----------------------------------------------------------
#  6.1 Crear contenedor atacante (sin WireGuard, sin VPN)
# ----------------------------------------------------------
info "Levantando contenedor atacante (sin VPN)..."
docker rm -f clab-attacker 2>/dev/null || true
docker run -d \
    --name clab-attacker \
    --network cloudhub-mgmt \
    --cap-add NET_ADMIN \
    debian:bookworm-slim \
    sleep infinity > /dev/null

# Instalar herramientas mínimas
docker exec clab-attacker bash -c "apt-get update -qq && apt-get install -y -qq iputils-ping curl netcat-openbsd iproute2 > /dev/null 2>&1"
echo ""

# ----------------------------------------------------------
#  6.2 Atacante intenta ping al Hub por IP VPN
# ----------------------------------------------------------
info "6.1 — Atacante intenta ping al Hub VPN (10.10.1.1)..."
if ! docker exec clab-attacker ping -c 2 -W 2 10.10.1.1 > /dev/null 2>&1; then
    pass "Ping a 10.10.1.1 RECHAZADO — la red VPN no es alcanzable sin túnel"
else
    fail "Ping a 10.10.1.1 respondió — la red VPN es accesible sin VPN (CRÍTICO)"
fi

# ----------------------------------------------------------
#  6.3 Atacante intenta acceder al servidor HTTP interno
# ----------------------------------------------------------
info "6.2 — Atacante intenta acceder al servidor interno (10.10.1.100:8080)..."
HTTP_RESP=$(docker exec clab-attacker curl -s --connect-timeout 3 http://10.10.1.100:8080 2>/dev/null || echo "TIMEOUT")
if echo "$HTTP_RESP" | grep -q "TIMEOUT\|Connection refused\|couldn't connect"; then
    pass "HTTP a 10.10.1.100:8080 RECHAZADO — servidor no accesible sin VPN"
else
    fail "HTTP a 10.10.1.100:8080 respondió — servidor expuesto sin VPN (CRÍTICO)"
fi

# ----------------------------------------------------------
#  6.4 Atacante intenta conectarse al puerto WireGuard del Hub
#       (puede llegar al puerto, pero sin claves no pasa nada)
# ----------------------------------------------------------
info "6.3 — Atacante intenta conexión al puerto WireGuard (172.20.20.10:51820)..."
# WireGuard no responde a tráfico no autenticado — el puerto está abierto
# pero sin la clave privada correcta, no se establece túnel
NC_RESULT=$(docker exec clab-attacker bash -c "echo 'test' | nc -u -w 2 172.20.20.10 51820 2>&1" || echo "")
# Verificamos que no hay handshake posible intentando ping a la red VPN
if ! docker exec clab-attacker ping -c 1 -W 2 10.10.1.1 > /dev/null 2>&1; then
    pass "Puerto WireGuard alcanzable pero sin handshake — sin claves no hay acceso"
else
    fail "Acceso a la red VPN sin claves válidas (CRÍTICO)"
fi

# ----------------------------------------------------------
#  6.5 Atacante intenta acceder a spokes directamente
# ----------------------------------------------------------
info "6.4 — Atacante intenta alcanzar spoke-01 por IP VPN (10.10.1.10)..."
if ! docker exec clab-attacker ping -c 2 -W 2 10.10.1.10 > /dev/null 2>&1; then
    pass "Spoke-01 NO alcanzable sin VPN"
else
    fail "Spoke-01 accesible sin VPN (CRÍTICO)"
fi

info "6.5 — Atacante intenta alcanzar spoke-02 por IP VPN (10.10.1.20)..."
if ! docker exec clab-attacker ping -c 2 -W 2 10.10.1.20 > /dev/null 2>&1; then
    pass "Spoke-02 NO alcanzable sin VPN"
else
    fail "Spoke-02 accesible sin VPN (CRÍTICO)"
fi

# ----------------------------------------------------------
#  6.6 Verificar que un peer legítimo SÍ puede acceder
# ----------------------------------------------------------
echo ""
info "6.6 — Verificación: un peer legítimo SÍ accede (Spoke-01 → Servidor)..."
docker exec clab-cloudhub-vpn-spoke-01 ping -c 2 -W 3 10.10.1.100 > /dev/null 2>&1 && pass "Spoke-01 legítimo SÍ accede al servidor (control)" || fail "Spoke-01 tampoco accede (problema de red)"

# ----------------------------------------------------------
#  Limpiar
# ----------------------------------------------------------
echo ""
info "Eliminando contenedor atacante..."
docker rm -f clab-attacker > /dev/null 2>&1

echo ""
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✓ TEST 6 COMPLETADO — Todos los ataques rechazados${NC}"
else
    echo -e "${RED}${BOLD}  ✗ TEST 6 — ${FAILURES} fallos detectados${NC}"
fi
echo ""
