#!/bin/bash
# HTTP Push smoke: http_push_loadtest.py, 50 TPS × 30s, BALANCE multi-menu
# TPS warmup: ON by default (60s ramp). Disable: add --no-warmup to http_push_loadtest.py below.
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "${HTTP_LOADTEST_DIR}"
VENV="${HTTP_LOADTEST_DIR}/.venv"
[ -x "${VENV}/bin/python" ] || { echo "Run 09-start-http-as.sh first (creates venv)"; exit 1; }

echo "=== HTTP Push load (30s, multi-menu BALANCE, 50 TPS smoke) ==="
"${VENV}/bin/python" http_push_loadtest.py \
  --target "${HTTP_PUSH_URL}" \
  --mode multi --profile BALANCE \
  --tps 50 --duration 30 \
  --think-min 50 --think-max 200 \
  --menu-config menu_config.json
