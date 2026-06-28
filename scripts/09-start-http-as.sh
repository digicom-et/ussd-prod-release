#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "${HTTP_LOADTEST_DIR}"
VENV="${HTTP_LOADTEST_DIR}/.venv"
[ -d "${VENV}" ] || {
    python3 -m venv "${VENV}"
    if [ -d wheels ] && ls wheels/*.whl >/dev/null 2>&1; then
        "${VENV}/bin/pip" install --no-index --find-links wheels -r requirements.txt 2>/dev/null || \
        "${VENV}/bin/pip" install -r requirements.txt
    else
        "${VENV}/bin/pip" install -r requirements.txt
    fi
}

PIDFILE="${PKG_ROOT}/.http-as.pid"
if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
    echo "HTTP AS already running (pid $(cat "${PIDFILE}"))"
    exit 0
fi

nohup "${VENV}/bin/python" http_as_server.py \
    --port "${HTTP_AS_PORT}" \
    --min-delay 1 --max-delay 100 \
    --menu-config menu_config.json \
    > "${PKG_ROOT}/http-as.log" 2>&1 &
echo $! > "${PIDFILE}"
sleep 1
echo "HTTP Pull AS on :${HTTP_AS_PORT} (pid $(cat "${PIDFILE}"), log http-as.log)"
