#!/bin/bash
# gRPC smoke: loadtest_client.py, 50 TPS × 30s, BALANCE multi-menu
# TPS warmup: ON by default (60s ramp). Disable: add --no-warmup to loadtest_client.py below.
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "${GRPC_AS_DIR}"
VENV="${GRPC_AS_DIR}/.venv"
[ -x "${VENV}/bin/python" ] || { echo "Run 05-start-grpc-as.sh first"; exit 1; }

echo "=== gRPC multi-menu smoke (30s, BALANCE) ==="
"${VENV}/bin/python" loadtest_client.py \
  --target "localhost:${GRPC_AS_PORT}" \
  --tps 50 --duration 30 \
  --multi-menu --profile BALANCE \
  --think-min 50 --think-max 200 \
  --menu-config menu_config.json
