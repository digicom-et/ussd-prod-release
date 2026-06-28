#!/bin/bash
# MAP smoke: 10 dialogs, BALANCE profile, multi-menu via gRPC AS
# TPS warmup: ON by default (60s ramp). Disable: add -Dwarmup=false to java command below.
set -euo pipefail
source "$(dirname "$0")/env.sh"

cd "${MAP_LOAD_DIR}"
echo "=== MAP load smoke (10 dialogs, BALANCE) ==="
java -cp "lib/*" org.restcomm.protocols.ss7.map.load.ussd.Client \
  10 5 sctp 127.0.0.1 8011 -1 127.0.0.1 "${SCTP_GW_PORT}" IPSP 101 102 1 2 3 2 8 6 8 \
  1111112 9960639999 1 4 -100 0 "${USSD_SHORT_CODE}" BALANCE 50 200

echo "Check map-*.csv and maplog.txt in $(pwd)"
