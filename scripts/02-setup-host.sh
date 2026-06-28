#!/bin/bash
# Host setup (/opt/ussdgw) + backup restore helpers.
#
# Default: init host dirs and apply package config-seed (test lab).
# --restore <backup-dir>: restore /opt/ussdgw from 01 backup (auto pre-backup).
# --list-backups: list backups under package backups/
# --no-seed: only run host-init (dirs/permissions), do not overwrite XML in data/
set -euo pipefail
source "$(dirname "$0")/env.sh"
# shellcheck source=lib/host-backup.sh
source "$(dirname "$0")/lib/host-backup.sh"

RESTORE_DIR=""
NO_SEED=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --restore|-r) RESTORE_DIR="${2:?--restore requires backup dir}"; shift ;;
        --list-backups|-l) list_host_backups; exit 0 ;;
        --no-seed) NO_SEED=1 ;;
        -h|--help)
            sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

if [ -n "${RESTORE_DIR}" ]; then
    restore_host_ussdgw "${RESTORE_DIR}"
    exit $?
fi

echo "=== Host setup (${HOST_USSDGW}) ==="

if [ -d "${HOST_USSDGW}/data" ] && [ "${NO_SEED}" -eq 0 ]; then
    echo "Existing ${HOST_USSDGW}/data detected — creating safety backup first"
    backup_host_ussdgw "before-setup-host"
fi

docker run --rm --user 0:0 \
  -v "${HOST_USSDGW}:${HOST_USSDGW}" \
  -v "${GATEWAY_DIR}/config-seed:/bundled-seed:ro" \
  -v "${GATEWAY_DIR}/standalone.conf:/bundled/standalone.conf:ro" \
  -v "${GATEWAY_DIR}/scripts/host-init.sh:/host-init.sh:ro" \
  alpine:3.19 \
  /bin/sh /host-init.sh

if [ "${NO_SEED}" -eq 0 ]; then
    echo "Applying package config-seed to ${HOST_USSDGW}/data ..."
    mkdir -p "${HOST_USSDGW}/configuration"
    for f in "${GATEWAY_DIR}/config-seed/"*.xml; do
        cp -f "$f" "${HOST_USSDGW}/data/"
    done
    if [ -d "${GATEWAY_DIR}/config-seed/configuration" ]; then
        for f in "${GATEWAY_DIR}/config-seed/configuration/"*; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            if [ ! -f "${HOST_USSDGW}/configuration/${base}" ]; then
                cp -f "$f" "${HOST_USSDGW}/configuration/"
            fi
        done
        echo "  configuration/ seeded (mgmt-users, mgmt-groups)"
    fi
    cp -f "${GATEWAY_DIR}/standalone.conf" "${HOST_USSDGW}/standalone.conf"
else
    echo "Skipping config-seed overwrite (--no-seed)"
fi

chown -R 2000:2000 "${HOST_USSDGW}/data" "${HOST_USSDGW}/log" 2>/dev/null || \
    sudo chown -R 2000:2000 "${HOST_USSDGW}/data" "${HOST_USSDGW}/log"

check_sctp_module || true

echo ""
echo "Host backups: ${BACKUP_ROOT}/ussdgw-*"
echo "List:         ./scripts/02-setup-host.sh --list-backups"
echo "Restore:      sudo ./scripts/02-setup-host.sh --restore ${BACKUP_ROOT}/ussdgw-<timestamp>"
