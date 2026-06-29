#!/bin/bash
# USSD Gateway PROD Release Package — common paths.
#
# Versioning scheme: Hybrid SemVer + CalVer
#   USSDGW_VERSION  = SemVer core (e.g. 7.3.1, 7.4.0, 8.0.0)  — stable, customer-facing
#   BUILD_DATE      = CalVer  (e.g. 20260628)                — build day
#   BUILD_ID        = <BUILD_DATE>T<HHMMSS>-<gitshort7>       — full audit id
#
# USSD_VERSION is kept as an alias of USSDGW_VERSION for back-compat with older
# scripts and the Wildfly ENTRYPOINT that still uses ${USSD_VERSION}.
#
# Supports TWO Docker image variants:
#   - DOCKER_IMAGE / DOCKER_IMAGE_RELEASE       (heavy: eclipse-temurin Ubuntu)
#   - DOCKER_IMAGE_ZULU / DOCKER_IMAGE_ZULU_RELEASE
#                                              (azul/zulu-openjdk:8 Ubuntu)
#
# USSDGW_IMAGE_VARIANT (default "zulu") controls which one is exported as
# the canonical USSDGW_IMAGE for compose / start scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PKG_ROOT
export GATEWAY_DIR="${PKG_ROOT}/gateway"
export TOOLS_DIR="${PKG_ROOT}/tools"

# ── Version resolution (SemVer core from VERSION file) ──────────────────────
# USSDGW_VERSION = SemVer core, e.g. 7.3.1, 8.0.0
# Override before sourcing: USSDGW_VERSION=8.0.0 . ./scripts/env.sh
USSDGW_VERSION="${USSDGW_VERSION:-}"
if [ -z "${USSDGW_VERSION}" ] && [ -f "${PKG_ROOT}/VERSION" ]; then
    USSDGW_VERSION="$(tr -d '[:space:]' < "${PKG_ROOT}/VERSION")"
fi
# Strip -SNAPSHOT / -rc1 / -alpha suffixes if present (legacy convention)
USSDGW_VERSION="${USSDGW_VERSION%-SNAPSHOT}"
USSDGW_VERSION="${USSDGW_VERSION%%-*}"   # also strips -rc1, -alpha, etc.
# Default if VERSION file missing/empty
USSDGW_VERSION="${USSDGW_VERSION:-7.3.1}"

export USSDGW_VERSION
# Legacy alias — many existing scripts + Dockerfile ENTRYPOINT still use USSD_VERSION
export USSD_VERSION="${USSD_VERSION:-${USSDGW_VERSION}}"

# ── Docker image defaults (heavy + zulu) ──────────────────────────────────
export DOCKER_IMAGE="restcomm-ussd:${USSDGW_VERSION}"
export DOCKER_TAR="${PKG_ROOT}/docker/restcomm-ussd-${USSDGW_VERSION}.tar"

export DOCKER_IMAGE_ZULU="restcomm-ussd-zulu:${USSDGW_VERSION}"
export DOCKER_TAR_ZULU="${PKG_ROOT}/docker/restcomm-ussd-zulu-${USSDGW_VERSION}.tar"

export DOCKER_MANIFEST="${PKG_ROOT}/docker/package.manifest"
export LOADED_IMAGE_STATE="${PKG_ROOT}/.loaded-image-release"

# ── Release-specific metadata from manifest (optional) ──────────────────────
if [ -f "${DOCKER_MANIFEST}" ]; then
    # shellcheck disable=SC1090
    source "${DOCKER_MANIFEST}"
fi

export BUILD_DATE="${BUILD_DATE:-unknown}"
export BUILD_ID="${BUILD_ID:-legacy}"

# Heavy-variant release-specific tag
export DOCKER_IMAGE_RELEASE="${DOCKER_IMAGE_RELEASE:-${DOCKER_IMAGE}}"

# Zulu-variant release-specific tag
export DOCKER_IMAGE_ZULU="${DOCKER_IMAGE_ZULU:-restcomm-ussd-zulu:${USSDGW_VERSION}}"
export DOCKER_IMAGE_ZULU_RELEASE="${DOCKER_IMAGE_ZULU_RELEASE:-${DOCKER_IMAGE_ZULU}}"

# Combined customer-facing version string: 7.3.1+20260628
export USSDGW_VERSION_FULL="${USSDGW_VERSION}+${BUILD_DATE}"

# Active variant for this shell. Override before sourcing:
#     USSDGW_IMAGE_VARIANT=heavy . ./scripts/env.sh
USSDGW_IMAGE_VARIANT="${USSDGW_IMAGE_VARIANT:-zulu}"
case "${USSDGW_IMAGE_VARIANT}" in
    heavy)  USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_RELEASE}" ;;
    zulu)   USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_ZULU_RELEASE}" ;;
    auto)
        # Auto: prefer zulu if its tarball exists, else heavy
        if [ -f "${DOCKER_TAR_ZULU}" ]; then
            USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_ZULU_RELEASE}"
            USSDGW_IMAGE_VARIANT="zulu"
        else
            USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_RELEASE}"
            USSDGW_IMAGE_VARIANT="heavy"
        fi
        ;;
    *) echo "WARN: USSDGW_IMAGE_VARIANT='${USSDGW_IMAGE_VARIANT}' invalid (heavy|zulu|auto); defaulting to zulu"
       USSDGW_IMAGE_DEFAULT="${DOCKER_IMAGE_ZULU_RELEASE}"
       USSDGW_IMAGE_VARIANT="zulu"
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
