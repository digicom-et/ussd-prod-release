#!/bin/bash
# Shared backup / restore helpers for /opt/ussdgw (sourced by 01, 02, 03).
# Requires env.sh (HOST_USSDGW, BACKUP_ROOT, GATEWAY_DIR).

backup_host_ussdgw() {
    local reason="${1:-manual}"
    if [ ! -d "${HOST_USSDGW}" ]; then
        echo "No ${HOST_USSDGW} on host — skip host backup"
        return 0
    fi

    local ts dir tgz
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    dir="${BACKUP_ROOT}/ussdgw-${ts}"
    mkdir -p "${dir}"
    tgz="${dir}/ussdgw-host.tgz"

    echo "=== Backing up ${HOST_USSDGW} → ${dir} (${reason}) ==="
    if tar czf "${tgz}" -C /opt ussdgw 2>/dev/null; then
        :
    elif command -v sudo >/dev/null 2>&1; then
        sudo tar czf "${tgz}" -C /opt ussdgw
    else
        echo "FAIL: cannot read ${HOST_USSDGW} (try sudo)"
        return 1
    fi

    [ -f "${GATEWAY_DIR}/.env" ] && cp -f "${GATEWAY_DIR}/.env" "${dir}/gateway.env"
    [ -f "${GATEWAY_DIR}/.env.previous" ] && cp -f "${GATEWAY_DIR}/.env.previous" "${dir}/gateway.env.previous"
    {
        echo "timestamp=${ts}"
        echo "reason=${reason}"
        echo "BUILD_ID=${BUILD_ID:-unknown}"
        echo "USSDGW_IMAGE=${USSDGW_IMAGE:-unknown}"
        echo "archive=${tgz}"
    } > "${dir}/manifest.txt"

    echo "${dir}" > "${BACKUP_ROOT}/.latest"
    echo "Host backup: ${tgz} ($(du -h "${tgz}" | cut -f1))"
}

list_host_backups() {
    echo "=== Host backups under ${BACKUP_ROOT} ==="
    if [ ! -d "${BACKUP_ROOT}" ]; then
        echo "  (none)"
        return 0
    fi
    local n=0
    while IFS= read -r d; do
        [ -d "${d}" ] || continue
        n=$((n + 1))
        local sz manifest
        sz="?"
        [ -f "${d}/ussdgw-host.tgz" ] && sz="$(du -h "${d}/ussdgw-host.tgz" | cut -f1)"
        manifest=""
        [ -f "${d}/manifest.txt" ] && manifest="$(grep -E '^reason=|^BUILD_ID=' "${d}/manifest.txt" | tr '\n' ' ')"
        echo "  ${d}  (${sz})  ${manifest}"
    done < <(find "${BACKUP_ROOT}" -maxdepth 1 -type d -name 'ussdgw-*' | sort -r)
    [ "${n}" -eq 0 ] && echo "  (none)"
}

restore_host_ussdgw() {
    local src="${1:?usage: restore_host_ussdgw <backup-dir>}"
    local tgz="${src}/ussdgw-host.tgz"
    if [ ! -f "${tgz}" ]; then
        echo "FAIL: missing ${tgz}"
        return 1
    fi

    echo "=== Restoring ${HOST_USSDGW} from ${tgz} ==="
    echo "WARN: this overwrites ${HOST_USSDGW}/data and related host files."

  # Safety backup before restore
    backup_host_ussdgw "pre-restore"

    if [ -d "${HOST_USSDGW}" ]; then
        if rm -rf "${HOST_USSDGW}" 2>/dev/null; then
            :
        else
            sudo rm -rf "${HOST_USSDGW}"
        fi
    fi

    if tar xzf "${tgz}" -C /opt 2>/dev/null; then
        :
    else
        sudo tar xzf "${tgz}" -C /opt
    fi

    if [ -f "${src}/gateway.env" ]; then
        cp -f "${src}/gateway.env" "${GATEWAY_DIR}/.env"
        echo "Restored gateway/.env from backup"
    fi

    chown -R 2000:2000 "${HOST_USSDGW}/data" "${HOST_USSDGW}/log" 2>/dev/null || \
        sudo chown -R 2000:2000 "${HOST_USSDGW}/data" "${HOST_USSDGW}/log" 2>/dev/null || true

    echo "Restore done. Restart gateway: ./scripts/03-switch-gateway.sh or ./scripts/03-start-gateway.sh"
}

record_image_switch() {
    local from_img="${1:-none}"
    local to_img="${2:-unknown}"
  local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "${BACKUP_ROOT}"
    echo "${ts} ${from_img} -> ${to_img}" >> "${IMAGE_HISTORY}"
}

list_release_images() {
    local repo="${DOCKER_IMAGE%%:*}"
    echo "=== Available ${repo} images (old releases kept for rollback) ==="
    docker images "${repo}" --format 'table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}' 2>/dev/null || true
    if [ -f "${IMAGE_HISTORY}" ]; then
        echo ""
        echo "Recent switches (${IMAGE_HISTORY}):"
        tail -10 "${IMAGE_HISTORY}" | sed 's/^/  /'
    fi
    if [ -f "${GATEWAY_DIR}/.env.previous" ]; then
        echo ""
        echo "Previous release (rollback target):"
        grep USSDGW_IMAGE "${GATEWAY_DIR}/.env.previous" | sed 's/^/  /' || true
    fi
}

check_sctp_module() {
    if ! command -v lsmod >/dev/null 2>&1; then
        echo "WARN: lsmod not found — cannot verify SCTP kernel module"
        return 1
    fi
    local line
    line="$(lsmod | awk '/^sctp / {print $1, "size="$2, "refs="$3}')"
    if [ -n "${line}" ]; then
        echo "SCTP kernel module: OK (${line})"
        return 0
    fi
    echo "WARN: SCTP not loaded — MAP/SS7 tests need: sudo modprobe sctp"
    return 1
}
