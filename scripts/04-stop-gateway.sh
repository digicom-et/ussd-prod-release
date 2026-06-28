#!/bin/bash
# Stop the USSD Gateway (and optionally the monitor stack) via master compose.
#
# Flags:
#   --all    Stop everything in the master compose (gateway + collector + tui)
#   --tui    Stop only the TUI service
set -euo pipefail
source "$(dirname "$0")/env.sh"

COMPOSE_FILE="${PKG_ROOT}/docker-compose.yml"
STOP_ALL=0
STOP_TUI=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all|-a) STOP_ALL=1 ; shift ;;
        --tui|-t) STOP_TUI=1 ; shift ;;
        -h|--help)
            sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

cd "${PKG_ROOT}"

if [ "${STOP_TUI}" -eq 1 ]; then
    docker compose -f "${COMPOSE_FILE}" stop tui || true
    docker compose -f "${COMPOSE_FILE}" rm -f tui   || true
    echo "TUI stopped."
    exit 0
fi

if [ "${STOP_ALL}" -eq 1 ]; then
    docker compose -f "${COMPOSE_FILE}" down
    echo "Full stack (gateway + collector + tui) stopped."
    exit 0
fi

docker compose -f "${COMPOSE_FILE}" stop ussdgw init || true
docker compose -f "${COMPOSE_FILE}" rm -f ussdgw init || true
echo "Gateway stopped."
