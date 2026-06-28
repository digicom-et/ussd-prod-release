#!/bin/bash
# gRPC NI Push smoke: grpc_push_client.py, 50 TPS × 30s, BALANCE multi-menu
# Prerequisite: web mgmt → gRPC Push tab → enabled, port 8453 (GrpcPushServerEnabled=true)
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "${GRPC_AS_DIR}"
VENV="${GRPC_AS_DIR}/.venv"
[ -x "${VENV}/bin/python" ] || { echo "Run 07-run-grpc-smoke.sh first (creates venv)"; exit 1; }

echo "=== gRPC NI Push load (30s, multi-menu BALANCE, 50 TPS smoke) ==="
echo "  target: ${GRPC_PUSH_TARGET}"
"${VENV}/bin/python" grpc_push_client.py \
  --target "${GRPC_PUSH_TARGET}" \
  --mode multi --profile BALANCE \
  --tps 50 --duration 30 \
  --think-min 50 --think-max 200 \
  --menu-config menu_config.json
