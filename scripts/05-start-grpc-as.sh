#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "${GRPC_AS_DIR}"
VENV="${GRPC_AS_DIR}/.venv"

if [ ! -d "${VENV}" ]; then
    echo "Creating Python venv..."
    python3 -m venv "${VENV}"
    if [ -d wheels ] && ls wheels/*.whl >/dev/null 2>&1; then
        echo "Installing from offline wheels..."
        "${VENV}/bin/pip" install --no-index --find-links wheels -r requirements.txt || \
        "${VENV}/bin/pip" install -r requirements.txt
    else
        "${VENV}/bin/pip" install -r requirements.txt
    fi
fi

PIDFILE="${PKG_ROOT}/.grpc-as.pid"
if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
    echo "gRPC AS already running (pid $(cat "${PIDFILE}"))"
    exit 0
fi

nohup "${VENV}/bin/python" ussd_as_server.py \
    --port "${GRPC_AS_PORT}" \
    --min-delay 1 --max-delay 100 \
    --menu-config menu_config.json \
    > "${PKG_ROOT}/grpc-as.log" 2>&1 &
echo $! > "${PIDFILE}"
sleep 1
echo "gRPC AS started on :${GRPC_AS_PORT} (pid $(cat "${PIDFILE}"), log grpc-as.log)"
