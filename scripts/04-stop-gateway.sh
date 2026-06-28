#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "${GATEWAY_DIR}"
docker compose down
echo "Gateway stopped."
