#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"

PIDFILE="${PKG_ROOT}/.grpc-as.pid"
if [ -f "${PIDFILE}" ]; then
    kill "$(cat "${PIDFILE}")" 2>/dev/null || true
    rm -f "${PIDFILE}"
    echo "gRPC AS stopped."
else
    echo "gRPC AS not running."
fi
