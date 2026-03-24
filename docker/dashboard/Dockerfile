FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-minimal \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY dashboard.html /var/www/index.html
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
