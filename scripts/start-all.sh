#!/bin/bash
# Full E2E lab startup: load image → host init → gateway (+ collector + TUI) → gRPC AS
#
# Pass --no-tui to skip the BPF TUI dashboard (just gateway + collector headless).
# Pass --no-monitor to skip both collector and TUI.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "${DIR}/env.sh"

WITH_TUI=1
WITH_COLLECTOR=1
for arg in "$@"; do
    case "$arg" in
        --no-tui)      WITH_TUI=0 ;;
        --no-monitor)  WITH_TUI=0; WITH_COLLECTOR=0 ;;
    esac
done

"${DIR}/00-preflight.sh"
"${DIR}/01-load-docker-image.sh"    # load only — does not stop gateway
if [ "$(id -u)" -eq 0 ]; then
    "${DIR}/02-setup-host.sh"
else
    sudo "${DIR}/02-setup-host.sh"
fi

START_FLAGS=""
[ "${WITH_COLLECTOR}" -eq 1 ] && START_FLAGS="--with-monitor"
"${DIR}/03-start-gateway.sh" ${START_FLAGS}
"${DIR}/05-start-grpc-as.sh"

echo ""
echo "=== Lab ready ==="
echo "  Gateway:   curl -fs http://localhost:8080/jolokia/version"
echo "  gRPC AS:   localhost:${GRPC_AS_PORT}"
echo "  Collector: curl -s http://localhost:9090/metrics"
if [ "${WITH_TUI}" -eq 1 ]; then
    echo ""
    echo "  TUI dashboard (auto-attach to THIS terminal):"
    echo "     docker attach sctp-m3ua-tui          # Ctrl-p Ctrl-q to detach"
    echo "  ...or restart it foreground:"
    echo "     ./scripts/03-start-gateway.sh --tui-only"
fi
echo ""
echo "  MAP test:  ${DIR}/06-run-map-smoke.sh"
echo "  gRPC test: ${DIR}/07-run-grpc-smoke.sh"
