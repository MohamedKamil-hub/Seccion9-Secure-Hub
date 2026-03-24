#!/bin/bash
# ============================================================
#  SECCIÓN 9 — Destruir laboratorio Cloud-Hub VPN
# ============================================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "Destruyendo laboratorio Cloud-Hub VPN..."
cd "${PROJECT_DIR}"
sudo containerlab destroy --topo topology.yml --cleanup 2>/dev/null || true
echo "✓ Laboratorio destruido."
echo ""
echo "Para volver a desplegarlo: ./setup.sh"
