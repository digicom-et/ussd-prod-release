#!/bin/bash
source "$(dirname "$0")/env.sh"
PIDFILE="${PKG_ROOT}/.http-as.pid"
if [ -f "${PIDFILE}" ]; then
    kill "$(cat "${PIDFILE}")" 2>/dev/null || true
    rm -f "${PIDFILE}"
    echo "HTTP AS stopped"
fi
