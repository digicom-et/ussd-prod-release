#!/bin/bash
# Full E2E lab shutdown: stop everything in master compose + AS scripts
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "${DIR}/env.sh"

"${DIR}/09-stop-http-as.sh" 2>/dev/null || true
"${DIR}/05-stop-grpc-as.sh"

# Master compose: stop everything (gateway + init + collector + tui)
cd "${PKG_ROOT}"
docker compose -f "${PKG_ROOT}/docker-compose.yml" down --remove-orphans || true

echo "All services stopped."
