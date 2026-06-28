#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.sh"
# shellcheck source=lib/host-backup.sh
source "$(dirname "$0")/lib/host-backup.sh"

echo "=== USSD GW PROD Release Package — Preflight ==="

fail=0
check() { if "$@"; then echo "  OK  $*"; else echo "  FAIL $*"; fail=1; fi }

check command -v docker
check docker info >/dev/null 2>&1
if docker context show >/dev/null 2>&1; then
    ctx=$(docker context show 2>/dev/null || echo unknown)
    echo "  INFO docker context: ${ctx} (use same context for build, load, and compose)"
fi
check command -v java
check command -v python3

if check_sctp_module; then
    echo "  OK  SCTP ready for MAP/SS7 (lsmod | grep sctp)"
else
    echo "  WARN SCTP not loaded — run: sudo modprobe sctp"
    echo "        verify: lsmod | grep sctp"
fi

if [ -f "${DOCKER_TAR}" ]; then
    echo "  OK  docker image tar present ($(du -h "${DOCKER_TAR}" | cut -f1))"
else
    echo "  FAIL missing ${DOCKER_TAR}"
    fail=1
fi

[ -f "${DOCKER_MANIFEST}" ] && echo "  OK  package.manifest BUILD_ID=$(grep ^BUILD_ID= "${DOCKER_MANIFEST}" | cut -d= -f2-)" || \
    echo "  WARN package.manifest missing (legacy package)"

if [ -f "${MAP_LOAD_DIR}/lib/map-load.jar" ]; then
    echo "  OK  MAP load map-load.jar"
    if jar tf "${MAP_LOAD_DIR}/lib/map-load.jar" 2>/dev/null | grep -q 'org/restcomm/protocols/ss7/map/load/ussd/Client.class'; then
        echo "  OK  MAP load Client class"
    else
        echo "  FAIL MAP load Client class missing in map-load.jar"
        fail=1
    fi
    echo "  OK  MAP load lib ($(ls "${MAP_LOAD_DIR}/lib" | wc -l) JARs)"
else
    echo "  FAIL MAP load lib (map-load.jar missing)"
    fail=1
fi
[ -f "${MAP_LOAD_DIR}/USSD-LOADTEST.md" ] && echo "  OK  MAP load docs" || echo "  WARN USSD-LOADTEST.md missing"

if [ -f "${SIMULATOR_DIR}/bin/run.jar" ]; then
    echo "  OK  SS7 simulator run.jar"
else
    echo "  FAIL SS7 simulator run.jar missing"
    fail=1
fi
if ls "${SIMULATOR_DIR}/lib/"*woodstox* >/dev/null 2>&1 && ls "${SIMULATOR_DIR}/lib/"*stax2* >/dev/null 2>&1; then
    echo "  OK  SS7 simulator Woodstox StAX ($(ls "${SIMULATOR_DIR}/lib/"*woodstox* "${SIMULATOR_DIR}/lib/"*stax2* | xargs -n1 basename | tr '\n' ' '))"
else
    echo "  FAIL SS7 simulator lib missing woodstox-core / stax2-api (re-run build-package.sh)"
    fail=1
fi

[ -f "${GRPC_AS_DIR}/ussd_as_server.py" ] && echo "  OK  gRPC AS scripts" || fail=1
[ -f "${HTTP_LOADTEST_DIR}/http_as_server.py" ] && echo "  OK  HTTP loadtest scripts" || { echo "  FAIL HTTP loadtest"; fail=1; }
[ -f "${HTTP_SIM_DIR}/bin/run.jar" ] && echo "  OK  HTTP simulator GUI" || echo "  WARN HTTP simulator run.jar missing"

if [ -f "${GATEWAY_DIR}/config-seed/configuration/mgmt-users.properties" ] \
   && [ -f "${GATEWAY_DIR}/config-seed/configuration/mgmt-groups.properties" ]; then
    echo "  OK  GUI auth seed (mgmt-users/groups in config-seed/configuration/)"
else
    echo "  FAIL missing config-seed/configuration/mgmt-*.properties"
    fail=1
fi

[ -d "${BACKUP_ROOT}" ] && echo "  OK  backups dir exists" || echo "  INFO backups created on first 01-load / 02-setup"

# Master compose + monitor stack (BPF collector + TUI dashboard)
if [ -f "${PKG_ROOT}/docker-compose.yml" ]; then
    echo "  OK  master docker-compose.yml (gateway + collector + tui)"
    if docker compose -f "${PKG_ROOT}/docker-compose.yml" config --quiet 2>/dev/null; then
        echo "  OK  master compose parses cleanly"
    else
        echo "  FAIL master compose does not parse:"
        docker compose -f "${PKG_ROOT}/docker-compose.yml" config 2>&1 | head -3
        fail=1
    fi
else
    echo "  FAIL missing master docker-compose.yml at ${PKG_ROOT}/"
    fail=1
fi

# BPF TPS monitor — collector + TUI
for app in collector tui; do
    app_dir="${PKG_ROOT}/bpf-tps-monitor/${app}"
    if [ -f "${app_dir}/Cargo.toml" ] && [ -f "${app_dir}/Dockerfile" ]; then
        echo "  OK  bpf-tps-monitor/${app} (Rust crate + Dockerfile)"
    else
        echo "  FAIL missing bpf-tps-monitor/${app}/Cargo.toml or Dockerfile"
        fail=1
    fi
done

exit $fail
