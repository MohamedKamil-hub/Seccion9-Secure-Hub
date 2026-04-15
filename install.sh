#!/bin/bash
# ============================================================
#  SECCION9 LITE v5.0 — Lightweight WireGuard Panel
#  No Docker. No React. No npm. No OpenVPN. No SQLite.
#  Pure vanilla frontend. Systemd + Nginx.
#  Supports: Debian 12+, Ubuntu 22.04+
#  Usage: sudo bash install.sh
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}  SECCION9 LITE v5.0 — WireGuard Panel${NC}"
echo -e "${BLUE}  No React · No npm · No OpenVPN · No SQLite${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

[[ $EUID -ne 0 ]] && fail "Run as root: sudo bash install.sh"
[ ! -d "./backend" ] || [ ! -d "./frontend" ] && fail "Run from project directory"

# -- Detect OS -------------------------------------------------
DISTRO="unknown"
grep -qiE "debian|trixie" /etc/os-release 2>/dev/null && DISTRO="debian"
grep -qiE "ubuntu" /etc/os-release 2>/dev/null && DISTRO="ubuntu"
[ "$DISTRO" = "unknown" ] && warn "Untested OS."
ok "OS: $DISTRO"

# -- Gather config ---------------------------------------------
DETECTED_IP=$(curl -s4 --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s4 --connect-timeout 5 icanhazip.com 2>/dev/null || echo "")
if [ -n "$DETECTED_IP" ]; then
    read -p "  VPS public IP [$DETECTED_IP]: " SERVER_IP
    SERVER_IP=${SERVER_IP:-$DETECTED_IP}
else
    read -p "  VPS public IP: " SERVER_IP
fi
[ -z "$SERVER_IP" ] && fail "Public IP required"

DEFAULT_IFACE=$(ip route show default | awk '/default/ {print $5}' | head -1)
read -p "  Network interface [$DEFAULT_IFACE]: " NET_IFACE
NET_IFACE=${NET_IFACE:-$DEFAULT_IFACE}
[ -z "$NET_IFACE" ] && fail "No network interface detected"

while true; do
    read -sp "  Panel admin password (min 8 chars): " ADMIN_PASS; echo
    [ ${#ADMIN_PASS} -ge 8 ] && break
    warn "Minimum 8 characters"
done

read -p "  VPN subnet [10.0.0]: " VPN_SUBNET
VPN_SUBNET=${VPN_SUBNET:-10.0.0}

read -p "  WireGuard port [51820]: " WG_PORT
WG_PORT=${WG_PORT:-51820}

read -p "  Panel HTTPS port [443]: " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-443}

read -p "  DNS servers for clients [8.8.8.8,8.8.4.4]: " DNS_SERVERS
DNS_SERVERS=${DNS_SERVERS:-8.8.8.8,8.8.4.4}

SECRET_KEY=$(openssl rand -hex 32)
PANEL_URL="https://${SERVER_IP}:${PANEL_PORT}"

echo ""
echo -e "${YELLOW}  IP: ${SERVER_IP} | WG: ${WG_PORT}/udp | Panel: ${PANEL_URL}${NC}"
read -p "  Confirm? (y/n): " -n 1 -r; echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

# -- 1. Dependencies -------------------------------------------
info "[1/7] Installing dependencies..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv \
    wireguard wireguard-tools qrencode curl nginx openssl \
    iptables > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent > /dev/null 2>&1 || true
ok "Dependencies installed"

# -- 2. Swap ---------------------------------------------------
info "[2/7] Configuring swap..."
if [ ! -f /swapfile ]; then
    fallocate -l 512M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null
    chmod 600 /swapfile; mkswap /swapfile > /dev/null; swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "512MB swap created"
else
    swapon /swapfile 2>/dev/null || true
    ok "Swap exists"
fi

# -- 3. IP forwarding ------------------------------------------
info "[3/7] IP forwarding..."
cat > /etc/sysctl.d/99-seccion9.conf << 'EOF'
net.ipv4.ip_forward=1
vm.swappiness=10
EOF
sysctl --system > /dev/null 2>&1
ok "IP forwarding active"

# -- 4. WireGuard -----------------------------------------------
info "[4/7] Configuring WireGuard..."
mkdir -p /etc/wireguard/clientes
chmod 700 /etc/wireguard

WG_PRIVKEY=$(wg genkey)
WG_PUBKEY=$(echo "$WG_PRIVKEY" | wg pubkey)

cat > /etc/wireguard/wg0.conf << WGEOF
[Interface]
Address = ${VPN_SUBNET}.1/24
PostUp   = iptables -I FORWARD 1 -i wg0 -o wg0 -j DROP; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ${NET_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -o wg0 -j DROP; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ${NET_IFACE} -j MASQUERADE
ListenPort = ${WG_PORT}
PrivateKey = ${WG_PRIVKEY}
WGEOF

chmod 600 /etc/wireguard/wg0.conf

systemctl enable wg-quick@wg0 > /dev/null 2>&1
systemctl start wg-quick@wg0 2>/dev/null || wg-quick up wg0
ok "WireGuard active — pubkey: ${WG_PUBKEY}"

# -- 5. TLS certs ----------------------------------------------
info "[5/7] TLS certificates..."
mkdir -p /etc/seccion9/certs
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/seccion9/certs/panel.key \
    -out /etc/seccion9/certs/panel.crt \
    -subj "/CN=${SERVER_IP}/O=Seccion9/C=ES" > /dev/null 2>&1
chmod 600 /etc/seccion9/certs/panel.key
ok "Certificates generated"

# -- 6. Backend -------------------------------------------------
info "[6/7] Deploying backend..."
PANEL_DIR="/opt/seccion9"
mkdir -p "$PANEL_DIR"
cp -r ./backend "$PANEL_DIR/"
mkdir -p /var/log/seccion9

# Clean stale state
rm -f /etc/wireguard/users.json

# .env — single source of truth
cat > "$PANEL_DIR/backend/.env" << ENVEOF
ADMIN_USER=admin
ADMIN_PASSWORD=${ADMIN_PASS}
SECRET_KEY=${SECRET_KEY}
SERVER_PUBLIC_IP=${SERVER_IP}
SERVER_PUBLIC_KEY=${WG_PUBKEY}
SERVER_PORT=${WG_PORT}
VPN_SUBNET=${VPN_SUBNET}
WG_INTERFACE=wg0
WG_CONF_PATH=/etc/wireguard/wg0.conf
CONFIGS_DIR=/etc/wireguard/clientes
API_HOST=0.0.0.0
API_PORT=8000
PANEL_PUBLIC_URL=${PANEL_URL}
DNS_SERVERS=${DNS_SERVERS}
ACCESS_TOKEN_EXPIRE_MINUTES=480
ENVEOF
chmod 600 "$PANEL_DIR/backend/.env"

# Python venv
python3 -m venv "$PANEL_DIR/venv"
"$PANEL_DIR/venv/bin/pip" install --quiet --no-cache-dir \
    fastapi==0.115.0 \
    'uvicorn[standard]==0.30.0' \
    'python-jose[cryptography]==3.3.0' \
    'passlib[bcrypt]==1.7.4' \
    bcrypt==4.0.1 \
    python-multipart==0.0.9 \
    pydantic==2.9.0 \
    pydantic-settings==2.5.0 \
    'qrcode[pil]==7.4.2'
ok "Backend ready"

# Systemd service
cat > /etc/systemd/system/seccion9-api.service << SVCEOF
[Unit]
Description=Seccion9 Lite VPN API
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
WorkingDirectory=${PANEL_DIR}/backend
EnvironmentFile=${PANEL_DIR}/backend/.env
ExecStart=${PANEL_DIR}/venv/bin/python main.py
Restart=always
RestartSec=5
MemoryMax=120M
MemoryHigh=100M

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable seccion9-api > /dev/null 2>&1
systemctl start seccion9-api
ok "API service started"

# -- 7. Frontend + Nginx ----------------------------------------
info "[7/7] Deploying frontend (static files, no build)..."

# Copy static files directly — no npm, no build
mkdir -p /var/www/seccion9
cp -r ./frontend/* /var/www/seccion9/
ok "Frontend deployed (static files)"

# Nginx config
rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf

if [ -d "/etc/nginx/sites-available" ]; then
    NGINX_CONF="/etc/nginx/sites-available/seccion9.conf"
    NGINX_LINK="/etc/nginx/sites-enabled/seccion9.conf"
else
    NGINX_CONF="/etc/nginx/conf.d/seccion9.conf"
    NGINX_LINK=""
fi

cat > "$NGINX_CONF" << NGINXEOF
limit_req_zone \$binary_remote_addr zone=panel:10m rate=30r/m;
limit_req_zone \$binary_remote_addr zone=auth:10m rate=10r/m;
limit_req_zone \$binary_remote_addr zone=invite:10m rate=10r/m;

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://\$host\$request_uri;
}

server {
    listen ${PANEL_PORT} ssl default_server;
    listen [::]:${PANEL_PORT} ssl default_server;
    server_name _;

    ssl_certificate     /etc/seccion9/certs/panel.crt;
    ssl_certificate_key /etc/seccion9/certs/panel.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;

    root  /var/www/seccion9;
    index index.html;

    location / {
        limit_req zone=panel burst=20 nodelay;
        try_files \$uri \$uri/ /index.html;
    }

    location /api/auth/login {
        limit_req zone=auth burst=5 nodelay;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 10s;
    }

    location /invite/ {
        limit_req zone=invite burst=5 nodelay;
        rewrite ^/invite/(.*)$ /api/onboard/\$1 break;
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 15s;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 30s;
        proxy_buffering off;
    }

    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    gzip_min_length 256;
}
NGINXEOF

grep -q 'worker_processes' /etc/nginx/nginx.conf && \
    sed -i 's/worker_processes.*/worker_processes 1;/' /etc/nginx/nginx.conf

[ -n "$NGINX_LINK" ] && ln -sf "$NGINX_CONF" "$NGINX_LINK"
nginx -t > /dev/null 2>&1 && systemctl reload nginx
ok "Nginx configured (port ${PANEL_PORT})"

# -- Firewall --------------------------------------------------
iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
iptables -A INPUT -p udp --dport "${WG_PORT}" -j ACCEPT 2>/dev/null || true
iptables -A INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
iptables -A INPUT -p tcp --dport "${PANEL_PORT}" -j ACCEPT 2>/dev/null || true
command -v netfilter-persistent &>/dev/null && netfilter-persistent save > /dev/null 2>&1
ok "Firewall configured"

# -- Verify ----------------------------------------------------
echo ""
info "Verifying..."
sleep 4
ERRORS=0

wg show wg0 &>/dev/null && ok "WireGuard active" || { warn "WireGuard not responding"; ERRORS=$((ERRORS+1)); }
systemctl is-active seccion9-api > /dev/null 2>&1 && ok "API running" || { warn "API not running"; ERRORS=$((ERRORS+1)); }

API_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/api/health 2>/dev/null || echo "000")
[ "$API_CODE" = "200" ] && ok "API responding" || { warn "API health check failed ($API_CODE)"; ERRORS=$((ERRORS+1)); }
[ -f /var/www/seccion9/index.html ] && ok "Frontend deployed" || { warn "Frontend missing"; ERRORS=$((ERRORS+1)); }

USED_MB=$(free -m | awk '/^Mem:/ {print $3}')
TOTAL_MB=$(free -m | awk '/^Mem:/ {print $2}')
ok "RAM: ${USED_MB}MB / ${TOTAL_MB}MB"

# -- Summary ---------------------------------------------------
echo ""
echo -e "${BLUE}=================================================${NC}"
[ $ERRORS -eq 0 ] && \
    echo -e "${GREEN}  SECCION9 LITE v5.0 DEPLOYED${NC}" || \
    echo -e "${YELLOW}  DEPLOYED WITH $ERRORS WARNINGS${NC}"
echo ""
echo -e "  ${GREEN}Panel:${NC}     ${PANEL_URL}"
echo -e "  ${GREEN}User:${NC}      admin"
echo -e "  ${GREEN}Password:${NC}  (as configured)"
echo -e "  ${GREEN}Invites:${NC}   ${PANEL_URL}/invite/{token}"
echo ""
echo -e "  ${YELLOW}.env:${NC}      ${PANEL_DIR}/backend/.env"
echo -e "  ${YELLOW}Logs:${NC}      journalctl -u seccion9-api -f"
echo -e "  ${YELLOW}Restart:${NC}   systemctl restart seccion9-api"
echo -e "${BLUE}=================================================${NC}"
echo ""
