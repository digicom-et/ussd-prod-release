#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Loading BPF monitor Docker images ==="

COLLECTOR_TAR="${PKG_ROOT}/docker/sctp-m3ua-collector.tar"
TUI_TAR="${PKG_ROOT}/docker/sctp-m3ua-tui.tar"

for tar_file in "$COLLECTOR_TAR" "$TUI_TAR"; do
    if [ ! -f "$tar_file" ]; then
        echo "ERROR: $tar_file not found" >&2
        exit 1
    fi
    echo "Loading: $(basename "$tar_file")"
    docker load -i "$tar_file" || podman load -i "$tar_file"
    echo "  ✓ done"
done

echo "=== BPF images loaded ==="
docker images | grep -E "sctp-m3ua-(collector|tui)" || podman images | grep -E "sctp-m3ua-(collector|tui)"
