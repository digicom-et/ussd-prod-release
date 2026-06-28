#!/bin/bash
# Start the USSD Gateway via the master compose at package root.
# Master compose also includes the BPF collector and (optionally) the TUI.
#
# Flags:
#   --with-monitor   Start the collector + TUI services as well
#   --tui-only      Start only the TUI (foreground, attach to your terminal)
#   --collector-only
#                   Start only the collector (no gateway)
set -euo pipefail
source "$(dirname "$0")/env.sh"
# shellcheck source=lib/health-wait.sh
source "$(dirname "$0")/lib/health-wait.sh"

COMPOSE_FILE="${PKG_ROOT}/docker-compose.yml"
WITH_MONITOR=0
TUI_ONLY=0
COLLECTOR_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-monitor) WITH_MONITOR=1 ; shift ;;
        --tui-only)     TUI_ONLY=1 ;     shift ;;
        --collector-only) COLLECTOR_ONLY=1; shift ;;
        -h|--help)
            sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

cd "${PKG_ROOT}"

if [ "${TUI_ONLY}" -eq 1 ]; then
    echo "=== Starting TUI (foreground — auto-attaches to this terminal) ==="
    exec docker compose -f "${COMPOSE_FILE}" up tui
fi

if [ "${COLLECTOR_ONLY}" -eq 1 ]; then
    echo "=== Starting BPF collector only ==="
    docker compose -f "${COMPOSE_FILE}" up -d collector
    exit 0
fi

echo "=== Starting USSD Gateway (master compose) ==="
if [ "${WITH_MONITOR}" -eq 1 ]; then
    docker compose -f "${COMPOSE_FILE}" up -d ussdgw collector
    echo ""
    echo "Tip: attach the live TPS dashboard to THIS terminal:"
    echo "     docker compose -f ${COMPOSE_FILE} up tui"
else
    docker compose -f "${COMPOSE_FILE}" up -d ussdgw
fi

if wait_gateway_health 60; then
    exit 0
fi
echo "WARN: health check timeout — check: docker logs ${USSDGW_CONTAINER}"
exit 1
