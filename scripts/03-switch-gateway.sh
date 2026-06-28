#!/bin/bash
# Switch gateway to release in gateway/.env, or rollback to previous / specific image.
set -euo pipefail
source "$(dirname "$0")/env.sh"
# shellcheck source=lib/host-backup.sh
source "$(dirname "$0")/lib/host-backup.sh"
# shellcheck source=lib/health-wait.sh
source "$(dirname "$0")/lib/health-wait.sh"

TARGET_IMAGE=""
ROLLBACK=0
LIST=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rollback|-r) ROLLBACK=1 ;;
        --to) TARGET_IMAGE="${2:?--to requires image tag}"; shift ;;
        --list-images|-l) LIST=1 ;;
        -h|--help)
            echo "Usage: $0 [--rollback | --to IMAGE | --list-images]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

if [ "${LIST}" -eq 1 ]; then
    list_release_images
    exit 0
fi

mkdir -p "${GATEWAY_DIR}"

if [ "${ROLLBACK}" -eq 1 ]; then
    if [ ! -f "${GATEWAY_ENV_PREV}" ]; then
        echo "FAIL: no ${GATEWAY_ENV_PREV}"
        list_release_images
        exit 1
    fi
    [ -f "${GATEWAY_DIR}/.env" ] && cp -f "${GATEWAY_DIR}/.env" "${GATEWAY_DIR}/.env.failed"
    cp -f "${GATEWAY_ENV_PREV}" "${GATEWAY_DIR}/.env"
    echo "Rollback → $(grep '^USSDGW_IMAGE=' "${GATEWAY_DIR}/.env" | cut -d= -f2-)"
elif [ -n "${TARGET_IMAGE}" ]; then
    [ -f "${GATEWAY_DIR}/.env" ] && cp -f "${GATEWAY_DIR}/.env" "${GATEWAY_ENV_PREV}"
    cat > "${GATEWAY_DIR}/.env" <<EOF
USSDGW_IMAGE=${TARGET_IMAGE}
USSD_VERSION=${USSD_VERSION}
BUILD_ID=manual-switch
EOF
elif [ ! -f "${GATEWAY_DIR}/.env" ]; then
    cat > "${GATEWAY_DIR}/.env" <<EOF
USSDGW_IMAGE=${USSDGW_IMAGE}
USSD_VERSION=${USSD_VERSION}
BUILD_ID=${BUILD_ID:-unknown}
EOF
fi

# shellcheck disable=SC1090
source "${GATEWAY_DIR}/.env"

if ! docker image inspect "${USSDGW_IMAGE}" >/dev/null 2>&1; then
    echo "FAIL: image not loaded: ${USSDGW_IMAGE}"
    list_release_images
    exit 1
fi

FROM_IMAGE="none"
if docker ps --format '{{.Names}}' | grep -qx "${USSDGW_CONTAINER}"; then
    FROM_IMAGE="$(docker inspect -f '{{.Config.Image}}' "${USSDGW_CONTAINER}" 2>/dev/null || echo none)"
    target_id="$(docker image inspect -f '{{.Id}}' "${USSDGW_IMAGE}")"
    running_id="$(docker inspect -f '{{.Image}}' "${USSDGW_CONTAINER}" 2>/dev/null || true)"
    if [ "${running_id}" = "${target_id}" ]; then
        echo "Gateway already on ${USSDGW_IMAGE}"
        exit 0
    fi
    echo "Switch: ${FROM_IMAGE} → ${USSDGW_IMAGE}"
    if [ "${ROLLBACK}" -eq 0 ] && [ "${FROM_IMAGE}" != "none" ]; then
        cat > "${GATEWAY_ENV_PREV}" <<EOF
USSDGW_IMAGE=${FROM_IMAGE}
USSD_VERSION=${USSD_VERSION}
BUILD_ID=previous-running
EOF
    fi
else
    echo "Start gateway on ${USSDGW_IMAGE}"
fi

backup_host_ussdgw "before-gateway-switch"

cd "${PKG_ROOT}"
docker compose -f "${PKG_ROOT}/docker-compose.yml" down --remove-orphans
docker compose -f "${PKG_ROOT}/docker-compose.yml" up -d --force-recreate ussdgw

record_image_switch "${FROM_IMAGE}" "${USSDGW_IMAGE}"

if wait_gateway_health 60; then
    echo "Gateway healthy on ${USSDGW_IMAGE}"
    echo "Rollback image: ./scripts/03-switch-gateway.sh --rollback"
    echo "Restore host:   sudo ./scripts/02-setup-host.sh --restore <backup-dir>"
    list_release_images
    exit 0
fi
echo "WARN: health timeout"
echo "  Rollback image: ./scripts/03-switch-gateway.sh --rollback"
echo "  Restore host:   sudo ./scripts/02-setup-host.sh --list-backups"
exit 1
