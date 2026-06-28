#!/bin/bash
# USSD Gateway PROD Release Package — common paths.
#
# Supports TWO Docker image variants:
#   - DOCKER_IMAGE / DOCKER_IMAGE_RELEASE   (heavy: eclipse-temurin Ubuntu)
#   - DOCKER_IMAGE_ALPINE / DOCKER_IMAGE_ALPINE_RELEASE
#                                          (alpine:3.19 + zulu-openjdk8 slim)
#
# USSDGW_IMAGE_VARIANT (default "alpine") controls which one is exported as
# the canonical USSDGW_IMAGE for compose / start scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PKG_ROOT
export GATEWAY_DIR="${PKG_ROOT}/gateway"
export TOOLS_DIR="${PKG_ROOT}/tools"

# Version from package (written by build-package.sh) or override USSD_VERSION=...
USSD_VERSION="${USSD_VERSION:-7.3.1-SNAPSHOT}"
if [ -f "${PKG_ROOT}/VERSION" ]; then
    USSD_VERSION="$(tr -d '[:space:]' < "${PKG_ROOT}/VERSION")"
fi

export USSD_VERSION

# ---- Docker image defaults (heavy + alpine) ---------------------------------
export DOCKER_IMAGE="restcomm-ussd:${USSD_VERSION}"
export DOCKER_TAR="${PKG_ROOT}/docker/restcomm-ussd-${USSD_VERSION}.tar"

export DOCKER_IMAGE_ALPINE="restcomm-ussd-alpine:${USSD_VERSION}"
export DOCKER_TAR_ALPINE="${PKG_ROOT}/docker/restcomm-ussd-alpine-${USSD_VERSION}.tar"

export DOCKER_MANIFEST="${PKG_ROOT}/docker/package.manifest"
export LOADED_IMAGE_STATE="${PKG_ROOT}/.loaded-image-release"

# Release-specific image tag (unique per package build — avoids SNAPSHOT tag collision)
if [ -f "${DOCKER_MANIFEST}" ]; then
    # shellcheck disable=SC1090
    source "${DOCKER_MANIFEST}"
fi

export BUILD_ID="${BUILD_ID:-legacy}"

# Heavy-variant tag (default = the canonical :<VERSION> tag, not the release-tag)
export DOCKER_IMAGE_RELEASE="${DOCKER_IMAGE_RELEASE:-${DOCKER_IMAGE}}"

# Alpine-variant tag (default = the canonical :<VERSION> tag)
export DOCKER_IMAGE_ALPINE="${DOCKER_IMAGE_ALPINE:-restcomm-ussd-alpine:${USSD_VERSION}}"
export DOCKER_IMAGE_ALPINE_RELEASE="${DOCKER_IMAGE_ALPINE_RELEASE:-${DOCKER_IMAGE_ALPINE}}"

# Active variant for this shell. Override before sourcing:
#     USSDGW_IMAGE_VARIANT=heavy . ./scripts/env.sh
USSDGW_IMAGE_VARIANT="${USSDGW_IMAGE_VARIANT:-alpine}"
case "${USSDGW_IMAGE_VARIANT}" in
    heavy)  USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_RELEASE}" ;;
    alpine) USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_ALPINE_RELEASE}" ;;
    auto)
        # Auto: prefer alpine if its tarball exists, else heavy
        if [ -f "${DOCKER_TAR_ALPINE}" ]; then
            USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_ALPINE_RELEASE}"
            USSDGW_IMAGE_VARIANT="alpine"
        else
            USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_RELEASE}"
            USSDGW_IMAGE_VARIANT="heavy"
        fi
        ;;
    *) echo "WARN: USSDGW_IMAGE_VARIANT='${USSDGW_IMAGE_VARIANT}' invalid (heavy|alpine|auto); defaulting to alpine"
       USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_ALPINE_RELEASE}"
       USSDGW_IMAGE_VARIANT="alpine"
       ;;
esac
export USSDGW_IMAGE_VARIANT
export USSDGW_IMAGE="${USSDGW_IMAGE:-${USSDGW_IMAGE_DEFAULT}}"

export GRPC_AS_DIR="${TOOLS_DIR}/grpc-as-tester"
export MAP_LOAD_DIR="${TOOLS_DIR}/jss7-map-load"
export SIMULATOR_DIR="${TOOLS_DIR}/jss7-simulator"
export USSD_SHORT_CODE='*100#'
export SCTP_GW_PORT=8012
export GRPC_AS_PORT=8443
export GRPC_PUSH_PORT=8453
export GRPC_PUSH_TARGET="localhost:${GRPC_PUSH_PORT}"
export HTTP_AS_PORT=8049
export HTTP_PUSH_URL="http://127.0.0.1:8080/restcomm"
export HTTP_SHORT_CODE='*519#'
export USSDGW_CONTAINER="ussd-prod"
export USSDGW_INIT_CONTAINER="ussd-prod-init"
export HTTP_SIM_DIR="${TOOLS_DIR}/http-simulator"
export HTTP_LOADTEST_DIR="${HTTP_SIM_DIR}/loadtest"

export HOST_USSDGW="/opt/ussdgw"
export BACKUP_ROOT="${PKG_ROOT}/backups"
export IMAGE_HISTORY="${BACKUP_ROOT}/image-history.log"
export GATEWAY_ENV_PREV="${GATEWAY_DIR}/.env.previous"
