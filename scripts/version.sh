#!/bin/bash
# USSDGW PROD Release — version inspector.
#
# Usage:
#   ./scripts/version.sh              # one-line summary
#   ./scripts/version.sh --json       # machine-readable
#   ./scripts/version.sh --all        # verbose, all fields
#
# Sources the master env.sh (which derives USSDGW_VERSION from VERSION file
# and BUILD_DATE/BUILD_ID from package.manifest).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh"

MODE="${1:---summary}"

case "${MODE}" in
    --json|-j)
        # Single-line JSON for scripts / monitoring
        cat <<EOF
{"ussdgw_version":"${USSDGW_VERSION}","build_date":"${BUILD_DATE}","build_id":"${BUILD_ID}","version_full":"${USSDGW_VERSION_FULL}","variant":"${USSDGW_IMAGE_VARIANT}","image":"${USSDGW_IMAGE}","image_release":"${DOCKER_IMAGE_ALPINE_RELEASE}"}
EOF
        ;;
    --all|-a)
        cat <<EOF
ussdgw-prod-release version inspector
=====================================

SemVer core         : ${USSDGW_VERSION}
Build date (CalVer) : ${BUILD_DATE}
Full version        : ${USSDGW_VERSION_FULL}
Build ID (audit)    : ${BUILD_ID}

Docker image (active)    : ${USSDGW_IMAGE}
Docker image (release)   : ${DOCKER_IMAGE_ALPINE_RELEASE}

Image variant            : ${USSDGW_IMAGE_VARIANT}
  - heavy  image (Ubuntu): ${DOCKER_IMAGE}
  - alpine image (slim)  : ${DOCKER_IMAGE_ALPINE}

Path /opt/ussdgw         : ${HOST_USSDGW}
Container name           : ${USSDGW_CONTAINER}
SCTP GW port             : ${SCTP_GW_PORT}

Sources:
  VERSION file           : ${PKG_ROOT}/VERSION
  package.manifest       : ${DOCKER_MANIFEST}
  Loaded-state file      : ${LOADED_IMAGE_STATE}
EOF
        ;;
    --summary|"")
        echo "ussdgw-prod-release ${USSDGW_VERSION_FULL}  (${USSDGW_IMAGE_VARIANT}, build ${BUILD_ID})"
        ;;
    -h|--help)
        sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        echo "Unknown mode: ${MODE}" >&2
        echo "Use: --summary | --json | --all | --help" >&2
        exit 1
        ;;
esac