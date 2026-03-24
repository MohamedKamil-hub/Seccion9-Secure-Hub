#!/bin/bash
echo "[DASHBOARD] Panel de monitorización en http://0.0.0.0:3000"
cd /var/www && python3 -m http.server 3000 &
exec tail -f /dev/null
