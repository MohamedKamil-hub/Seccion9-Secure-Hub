#!/bin/bash
# ============================================================
# FIREWALL BASE — Cloud-Hub VPN (simula OPNsense)
# ============================================================

# Limpiar reglas previas
iptables -F
iptables -t nat -F
iptables -F FORWARD

# Política base: permitir todo el forwarding (luego restringimos)
iptables -P FORWARD ACCEPT

# NAT: los spokes pueden salir a internet a través del Hub
iptables -t nat -A POSTROUTING -s 10.10.1.0/24 -o eth0 -j MASQUERADE

# Permitir tráfico entre spokes a través de wg0 (base)
iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT

# Permitir tráfico de spokes hacia internet
iptables -A FORWARD -i wg0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Log para debug (opcional)
# iptables -A FORWARD -j LOG --log-prefix "[HUB-FW] "

echo "[FIREWALL] Reglas base aplicadas — todo el tráfico entre spokes permitido"
