#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
# shellcheck source=lib/health-wait.sh
source "$(dirname "$0")/lib/health-wait.sh"

echo "=== Starting USSD Gateway ==="
cd "${GATEWAY_DIR}"
docker compose up -d

if wait_gateway_health 60; then
    exit 0
fi
echo "WARN: health check timeout — check: docker logs ${USSDGW_CONTAINER}"
exit 1
