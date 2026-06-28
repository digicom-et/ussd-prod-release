#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "${DIR}/env.sh"

"${DIR}/09-stop-http-as.sh" 2>/dev/null || true
"${DIR}/05-stop-grpc-as.sh"
"${DIR}/04-stop-gateway.sh"
echo "All services stopped."
