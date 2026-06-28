#!/bin/bash
# Full E2E lab startup: load image → host init → gateway → gRPC AS
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "${DIR}/env.sh"

"${DIR}/00-preflight.sh"
"${DIR}/01-load-docker-image.sh"    # load only — does not stop gateway
if [ "$(id -u)" -eq 0 ]; then
    "${DIR}/02-setup-host.sh"
else
    sudo "${DIR}/02-setup-host.sh"
fi
"${DIR}/03-start-gateway.sh"
"${DIR}/05-start-grpc-as.sh"

echo ""
echo "=== Lab ready ==="
echo "  Gateway:  curl -fs http://localhost:8080/jolokia/version"
echo "  gRPC AS:  localhost:${GRPC_AS_PORT}"
echo "  MAP test: ${DIR}/06-run-map-smoke.sh"
echo "  gRPC test:${DIR}/07-run-grpc-smoke.sh"
