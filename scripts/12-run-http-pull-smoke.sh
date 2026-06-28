#!/bin/bash
# HTTP Pull smoke: SS7 *519# → Gateway → HTTP AS (port 8049)
# TPS warmup: ON by default (60s ramp). Disable: add -Dwarmup=false to java command below.
set -euo pipefail
source "$(dirname "$0")/env.sh"

if ! curl -fs "http://127.0.0.1:${HTTP_AS_PORT}/" -o /dev/null -X POST -d '' 2>/dev/null; then
    echo "WARN: HTTP AS may not be running — run ./scripts/09-start-http-as.sh first"
fi

cd "${MAP_LOAD_DIR}"
echo "=== HTTP Pull smoke (10 dialogs, *519#, BALANCE) ==="
java -cp "lib/*" org.restcomm.protocols.ss7.map.load.ussd.Client \
  10 5 sctp 127.0.0.1 8011 -1 127.0.0.1 "${SCTP_GW_PORT}" IPSP 101 102 1 2 3 2 8 6 8 \
  1111112 9960639999 1 4 -100 0 "${HTTP_SHORT_CODE}" BALANCE 50 200

echo "Check map-*.csv in $(pwd)"
