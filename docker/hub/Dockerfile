FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iptables \
    iproute2 \
    iputils-ping \
    net-tools \
    tcpdump \
    curl \
    procps \
    jq \
    nano \
    python3-minimal \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY firewall.sh /firewall.sh
COPY api.py /api.py
RUN chmod +x /entrypoint.sh /firewall.sh

ENTRYPOINT ["/entrypoint.sh"]
