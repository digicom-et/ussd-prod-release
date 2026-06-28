#!/bin/bash
# Rebuild FULL ussdgw-prod-release package from dev workspace (build machine only).
#
# Two Docker-image variants are supported (controlled by USSDGW_IMAGE_VARIANT):
#   - "heavy"   (default historically) → eclipse-temurin:8-jdk-jammy Ubuntu base
#                                          tag:   restcomm-ussd:<VERSION>
#                                          tar:   docker/restcomm-ussd-<VERSION>.tar
#   - "alpine"                          → alpine:3.19 + openjdk8 (IcedTea build, slim)
#                                          tag:   restcomm-ussd-alpine:<VERSION>
#                                          tar:   docker/restcomm-ussd-alpine-<VERSION>.tar
#
# Detection rule (auto-mode, USSDGW_IMAGE_VARIANT=auto):
#   - If both tarballs exist under docker/, prefer the variant passed in
#     USSDGW_IMAGE_VARIANT; if not set, prefer `alpine` when present, else `heavy`.
#   - Always emit BOTH DOCKER_IMAGE_RELEASE and DOCKER_IMAGE_ALPINE lines in the
#     manifest so downstream scripts can pick whichever exists.
#
# Output always includes:
#   docker/restcomm-ussd-*.tar       (heavy variant)
#   docker/restcomm-ussd-alpine-*.tar (alpine variant, when built)
#   gateway/          (compose + config-seed)
#   scripts/          (start/stop/smoke — not overwritten; see sync below)
#   tools/jss7-map-load/    ← jSS7/map/load (assembled JARs + USSD-LOADTEST.md)
#   tools/jss7-simulator/   ← jSS7/tools/simulator distro
#   tools/grpc-as-tester/   ← ussdgateway/tools/grpc-as-tester + offline wheels
#   docs/
#
# Usage:
#   ./scripts/build-package.sh
#   USSDGW_IMAGE_VARIANT=heavy   ./scripts/build-package.sh
#   USSDGW_IMAGE_VARIANT=alpine  ./scripts/build-package.sh
#   USSDGW_IMAGE_VARIANT=auto    ./scripts/build-package.sh   # pick whichever exists
#   SKIP_DOCKER=1                ./scripts/build-package.sh   # tools + gateway only
#   SKIP_DOCKER_HEAVY=1          ./scripts/build-package.sh   # alpine-only
#   SKIP_DOCKER_ALPINE=1         ./scripts/build-package.sh   # heavy-only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WS="$(cd "${PKG_ROOT}/.." && pwd)"
GW="${WS}/ussdgateway/release-wildfly"
JSS7="${WS}/jSS7"
GRPC="${WS}/ussdgateway/tools/grpc-as-tester"
VERSION="${USSD_VERSION:-7.3.1}"

# Image-variant selection ---------------------------------------------------
# Default = "alpine" (per project plan). "auto" picks whichever tarball already
# exists in docker/ when no build-time Docker image is available.
USSDGW_IMAGE_VARIANT="${USSDGW_IMAGE_VARIANT:-alpine}"

# Tag/tar pairs per variant
declare -A IMG_TAG=(
    [heavy]="restcomm-ussd:${VERSION}"
    [alpine]="restcomm-ussd-alpine:${VERSION}"
)
declare -A IMG_TAR=(
    [heavy]="${PKG_ROOT}/docker/restcomm-ussd-${VERSION}.tar"
    [alpine]="${PKG_ROOT}/docker/restcomm-ussd-alpine-${VERSION}.tar"
)

# If user said "auto", try alpine tar first, fall back to heavy tar.
if [ "${USSDGW_IMAGE_VARIANT}" = "auto" ]; then
    if [ -f "${IMG_TAR[alpine]}" ]; then
        USSDGW_IMAGE_VARIANT="alpine"
    elif [ -f "${IMG_TAR[heavy]}" ]; then
        USSDGW_IMAGE_VARIANT="heavy"
    else
        echo "ERROR: USSDGW_IMAGE_VARIANT=auto but neither alpine nor heavy tar found under docker/"
        echo "  build one of:"
        echo "    cd ussdgw-prod-release/gateway && ./build-docker-alpine.sh"
        echo "    cd ussdgateway/release-wildfly && ./build-docker.sh"
        exit 1
    fi
fi

case "${USSDGW_IMAGE_VARIANT}" in
    heavy|alpine) ;;
    *) echo "ERROR: USSDGW_IMAGE_VARIANT must be one of: heavy | alpine | auto"; exit 1 ;;
esac

IMAGE="${IMG_TAG[${USSDGW_IMAGE_VARIANT}]}"
DOCKER_TAR="${IMG_TAR[${USSDGW_IMAGE_VARIANT}]}"

echo "=== Building ussdgw-prod-release package at ${PKG_ROOT} ==="
echo "    USSDGW_IMAGE_VARIANT = ${USSDGW_IMAGE_VARIANT}"
echo "    IMAGE (active)        = ${IMAGE}"
echo "    DOCKER_TAR (active)   = ${DOCKER_TAR}"

# ── 1. Docker image tar (both variants, controlled by SKIP_DOCKER_*) ────────
if [ "${SKIP_DOCKER:-0}" != "1" ]; then
    mkdir -p "${PKG_ROOT}/docker"
    BUILD_DATE="$(date -u +%Y%m%d)"
    BUILD_ID="${BUILD_DATE}T$(date -u +%H%M%S)-$(git -C "${WS}/ussdgateway" rev-parse --short HEAD 2>/dev/null || echo local)"

    # --- 1a. HEAVY variant (eclipse-temurin:8-jdk-jammy) ---------------------
    if [ "${SKIP_DOCKER_HEAVY:-0}" != "1" ]; then
        HEAVY_TAG="${IMG_TAG[heavy]}"
        HEAVY_TAR="${IMG_TAR[heavy]}"
        if docker image inspect "${HEAVY_TAG}" >/dev/null 2>&1; then
            echo "[docker/heavy] saving ${HEAVY_TAG} -> ${HEAVY_TAR}"
            docker save "${HEAVY_TAG}" -o "${HEAVY_TAR}"
        else
            echo "[docker/heavy] WARN: ${HEAVY_TAG} not built locally — skipping"
            echo "                build with: cd ussdgateway/release-wildfly && ./build-docker.sh"
        fi
    else
        echo "[docker/heavy] SKIP_DOCKER_HEAVY=1 — keeping existing tar"
    fi

    # --- 1b. ALPINE variant (alpine:3.19 + zulu-openjdk8) ---------------------
    if [ "${SKIP_DOCKER_ALPINE:-0}" != "1" ]; then
        ALPINE_TAG="${IMG_TAG[alpine]}"
        ALPINE_TAR="${IMG_TAR[alpine]}"
        if docker image inspect "${ALPINE_TAG}" >/dev/null 2>&1; then
            echo "[docker/alpine] saving ${ALPINE_TAG} -> ${ALPINE_TAR}"
            docker save "${ALPINE_TAG}" -o "${ALPINE_TAR}"
        else
            echo "[docker/alpine] WARN: ${ALPINE_TAG} not built locally — skipping"
            echo "                 build with: cd ussdgw-prod-release/gateway && ./build-docker-alpine.sh"
        fi
    else
        echo "[docker/alpine] SKIP_DOCKER_ALPINE=1 — keeping existing tar"
    fi

    # --- 1c. Manifest (always emits both variant lines) ----------------------
    EXISTING_HEAVY_REL=""
    EXISTING_ALPINE_REL=""
    if [ -f "${PKG_ROOT}/docker/package.manifest" ]; then
        # shellcheck disable=SC1090
        if ( . "${PKG_ROOT}/docker/package.manifest" ) 2>/dev/null; then
            [ -n "${DOCKER_IMAGE_RELEASE:-}" ]         && EXISTING_HEAVY_REL="${DOCKER_IMAGE_RELEASE}"
            [ -n "${DOCKER_IMAGE_ALPINE_RELEASE:-}" ]  && EXISTING_ALPINE_REL="${DOCKER_IMAGE_ALPINE_RELEASE}"
        fi
    fi

    # Which variant is "active" for THIS build?
    if [ "${USSDGW_IMAGE_VARIANT}" = "heavy" ]; then
        ACTIVE_HEAVY_REL="restcomm-ussd:${VERSION}-${BUILD_ID}"
        ACTIVE_ALPINE_REL="${EXISTING_ALPINE_REL:-restcomm-ussd-alpine:${VERSION}}"
    else
        ACTIVE_HEAVY_REL="${EXISTING_HEAVY_REL:-restcomm-ussd:${VERSION}}"
        ACTIVE_ALPINE_REL="restcomm-ussd-alpine:${VERSION}-${BUILD_ID}"
    fi

    cat > "${PKG_ROOT}/docker/package.manifest" <<EOF
# Auto-generated by build-package.sh — unique Docker tag per package build
#
# Versioning scheme: Hybrid SemVer + CalVer
#   USSDGW_VERSION  = SemVer core (e.g. 7.3.1, 7.4.0, 8.0.0) — from VERSION file
#   BUILD_DATE      = CalVer  (e.g. 20260628) — from date -u +%Y%m%d
#   BUILD_ID        = Full audit id (BUILD_DATE-TIME-gitshort7)
#
# Customer-facing Docker tag uses SemVer only (restcomm-ussd-alpine:7.3.1)
# so it is stable across rebuilds. The internal release-specific tag
# (restcomm-ussd-alpine:7.3.1-20260628-3d3881a) is used by the build package
# for rollback and audit.
#
# Build metadata (audit-only, not sourced as env):
#   ACTIVE_VARIANT=${USSDGW_IMAGE_VARIANT}
USSDGW_VERSION=${VERSION}
BUILD_DATE=${BUILD_DATE}
BUILD_ID=${BUILD_ID}
USSD_VERSION=${VERSION}                # legacy alias for backwards-compat
# Heavy variant (eclipse-temurin:8-jdk-jammy Ubuntu)
DOCKER_IMAGE=restcomm-ussd:${VERSION}
DOCKER_IMAGE_RELEASE=${ACTIVE_HEAVY_REL}
DOCKER_TAR=${HEAVY_TAR##*/}
# Alpine variant (alpine:3.19 + openjdk8 IcedTea — slim)
DOCKER_IMAGE_ALPINE=restcomm-ussd-alpine:${VERSION}
DOCKER_IMAGE_ALPINE_RELEASE=${ACTIVE_ALPINE_REL}
DOCKER_TAR_ALPINE=${ALPINE_TAR##*/}
EOF
    echo "  manifest BUILD_ID=${BUILD_ID} BUILD_DATE=${BUILD_DATE} (active=${USSDGW_IMAGE_VARIANT})"
else
    echo "[docker] SKIP_DOCKER=1 — keeping existing tar(s)"
fi

# ── 2. jSS7 MAP load client (jSS7/map/load) ─────────────────────────
echo "[tools] jSS7 map/load ..."
MAP_LOAD_SRC="${JSS7}/map/load"
MAP_LOAD_DST="${PKG_ROOT}/tools/jss7-map-load"

if [ ! -f "${MAP_LOAD_SRC}/target/load/map-load.jar" ]; then
    echo "  building map/load (mvn -Passemble) ..."
    (cd "${MAP_LOAD_SRC}" && mvn clean package -Passemble -DskipTests -q)
fi

rm -rf "${MAP_LOAD_DST}/lib"
mkdir -p "${MAP_LOAD_DST}/lib"
cp -a "${MAP_LOAD_SRC}/target/load/"* "${MAP_LOAD_DST}/lib/"

cp -f "${MAP_LOAD_SRC}/USSD-LOADTEST.md" "${MAP_LOAD_DST}/"
cp -f "${MAP_LOAD_SRC}/src/main/resources/menu_config.json" "${MAP_LOAD_DST}/"
cp -f "${MAP_LOAD_SRC}/ussd_build.xml" "${MAP_LOAD_DST}/" 2>/dev/null || true
for f in Client_sctp.xml Client_m3ua1.xml Test_management.xml; do
    [ -f "${MAP_LOAD_SRC}/${f}" ] && cp -f "${MAP_LOAD_SRC}/${f}" "${MAP_LOAD_DST}/" || true
done
echo "  $(ls "${MAP_LOAD_DST}/lib" | wc -l) JARs in tools/jss7-map-load/lib/"

# Ensure Jackson XML + Woodstox StAX jars in map-load lib (runtime deps for ss7-ext)
ensure_xml_stax_jars() {
    local lib_dir="$1"
    local m2="${M2_REPO:-${HOME}/.m2/repository}"
    local -a specs=(
        "com/fasterxml/woodstox/woodstox-core/6.5.1/woodstox-core-6.5.1.jar:woodstox-core-6.5.1.jar"
        "org/codehaus/woodstox/stax2-api/4.2.1/stax2-api-4.2.1.jar:stax2-api-4.2.1.jar"
    )
    for spec in "${specs[@]}"; do
        local rel="${spec%%:*}"
        local dest_name="${spec##*:}"
        if [ -f "${lib_dir}/${dest_name}" ]; then
            continue
        fi
        if [ -f "${m2}/${rel}" ]; then
            cp -f "${m2}/${rel}" "${lib_dir}/${dest_name}"
            echo "  added ${dest_name} -> ${lib_dir}/"
            continue
        fi
        local base="${dest_name%.jar}"
        for alt in "${lib_dir}/${base}"*.jar "${lib_dir}/${base}.jar"; do
            if [ -f "${alt}" ]; then
                cp -f "${alt}" "${lib_dir}/${dest_name}"
                echo "  linked ${dest_name} from $(basename "${alt}")"
                break
            fi
        done
    done
}
ensure_xml_stax_jars "${MAP_LOAD_DST}/lib"

# ── 3. jSS7 SS7 simulator (jSS7/tools/simulator) ────────────────────
echo "[tools] jSS7 simulator ..."
SIM_SRC="${JSS7}/tools/simulator/bootstrap/target/simulator-ss7"
SIM_DST="${PKG_ROOT}/tools/jss7-simulator"

need_sim_build=0
if [ ! -f "${SIM_SRC}/bin/run.jar" ]; then
    need_sim_build=1
elif ! ls "${SIM_SRC}/lib/"*woodstox* >/dev/null 2>&1; then
    echo "  simulator lib missing woodstox — rebuilding ..."
    need_sim_build=1
fi
if [ "${need_sim_build}" = "1" ]; then
    echo "  building simulator (mvn install -pl tools/simulator/bootstrap -am) ..."
    (cd "${JSS7}" && mvn install -pl tools/simulator/bootstrap -am -Dmaven.test.skip=true -q) || {
        echo "  WARN simulator rebuild failed — will supplement woodstox from map-load lib if needed"
    }
fi

rm -rf "${SIM_DST}"
mkdir -p "${SIM_DST}"
cp -a "${SIM_SRC}/"* "${SIM_DST}/"
# Safety net: ss7-ext XML needs Woodstox StAX on Java 8
for jar in woodstox-core stax2-api; do
    if ! ls "${SIM_DST}/lib/"*${jar}* >/dev/null 2>&1; then
        src="$(ls "${MAP_LOAD_DST}/lib/"*${jar}* 2>/dev/null | head -1)"
        if [ -n "${src}" ]; then
            cp -f "${src}" "${SIM_DST}/lib/"
            echo "  supplemented simulator lib with $(basename "${src}")"
        fi
    fi
done
cp -f "${WS}/ussdgateway/core/bootstrap/src/main/config/ss7-simulator/main_simulator2.xml" \
    "${SIM_DST}/data/main_simulator2.xml"
ensure_xml_stax_jars "${SIM_DST}/lib"
echo "  simulator distro -> tools/jss7-simulator/"

# ── 4. gRPC Python tester (ussdgateway/tools/grpc-as-tester) ────────
echo "[tools] gRPC Python tester ..."
GRPC_DST="${PKG_ROOT}/tools/grpc-as-tester"
mkdir -p "${GRPC_DST}/wheels"
rm -f "${GRPC_DST}/"*.py "${GRPC_DST}/requirements.txt" "${GRPC_DST}/menu_config.json" 2>/dev/null || true
cp -f "${GRPC}"/*.py "${GRPC}/requirements.txt" "${GRPC}/menu_config.json" "${GRPC_DST}/"
# Remove local venv from package if present
rm -rf "${GRPC_DST}/.venv"

for pyver in 39 310 311 312; do
    python3 -m pip download grpcio typing_extensions \
        -d "${GRPC_DST}/wheels" \
        --python-version "${pyver}" --platform manylinux2014_x86_64 \
        --only-binary=:all: -q 2>/dev/null || true
done
echo "  grpc-as-tester + wheels -> tools/grpc-as-tester/"

# ── 5. HTTP simulator + loadtest (ussdgateway/tools/http-simulator) ─
echo "[tools] HTTP simulator ..."
HTTP_SIM="${WS}/ussdgateway/tools/http-simulator"
HTTP_DST="${PKG_ROOT}/tools/http-simulator"
HTTP_SIM_DIST="${HTTP_SIM}/bootstrap/target/simulator-http"

if [ ! -f "${HTTP_SIM_DIST}/bin/run.jar" ]; then
    echo "  building http-simulator (mvn install) ..."
    (cd "${HTTP_SIM}" && mvn install -Dmaven.test.skip=true -q)
fi

rm -rf "${HTTP_DST}"
mkdir -p "${HTTP_DST}"
cp -a "${HTTP_SIM_DIST}/"* "${HTTP_DST}/"
cp -a "${HTTP_SIM}/loadtest" "${HTTP_DST}/"
rm -rf "${HTTP_DST}/loadtest/.venv" 2>/dev/null || true
for pyver in 39 310 311 312; do
    python3 -m pip download aiohttp \
        -d "${HTTP_DST}/loadtest/wheels" \
        --python-version "${pyver}" --platform manylinux2014_x86_64 \
        --only-binary=:all: -q 2>/dev/null || true
done
echo "  http-simulator GUI + loadtest -> tools/http-simulator/"

# ── 6. Gateway config-seed (compose stays package-local: ussd-prod) ───
echo "[gateway] compose + config-seed ..."
mkdir -p "${PKG_ROOT}/gateway/config-seed" "${PKG_ROOT}/gateway/config-seed/configuration" "${PKG_ROOT}/gateway/scripts"
cp -f "${GW}/standalone.conf" "${PKG_ROOT}/gateway/"
# docker-compose.yml: kept in package (ussd-prod naming, lab profile) — do not overwrite from release-wildfly
cp -f "${GW}/scripts/"*.sh "${PKG_ROOT}/gateway/scripts/"
if [ -d "${GW}/config-seed/configuration" ]; then
    cp -f "${GW}/config-seed/configuration/"* "${PKG_ROOT}/gateway/config-seed/configuration/"
fi
for f in "${GW}/config-seed/"*.xml; do
    base=$(basename "$f")
    if [ "$base" = "UssdManagement_scroutingrule.xml" ] || [ "$base" = "UssdManagement_ussdproperties.xml" ]; then
        [ -f "${PKG_ROOT}/gateway/config-seed/${base}" ] || cp -f "$f" "${PKG_ROOT}/gateway/config-seed/"
    else
        cp -f "$f" "${PKG_ROOT}/gateway/config-seed/"
    fi
done

# ── 7. Docs ─────────────────────────────────────────────────────────
mkdir -p "${PKG_ROOT}/docs"
cp -f "${SCRIPT_DIR}/../docs/e2e-grpc-ussd-test.md" "${PKG_ROOT}/docs/" 2>/dev/null || \
  cp -f "${WS}/ussdgateway/docs/e2e-grpc-ussd-test.md" "${PKG_ROOT}/docs/" 2>/dev/null || true
cp -f "${SCRIPT_DIR}/../docs/e2e-grpc-ussd-test_en.md" "${PKG_ROOT}/docs/" 2>/dev/null || \
  cp -f "${WS}/ussdgateway/docs/e2e-grpc-ussd-test_en.md" "${PKG_ROOT}/docs/" 2>/dev/null || true
cp -f "${GW}/DEPLOY-GUIDE.md" "${PKG_ROOT}/docs/" 2>/dev/null || true
cp -f "${SCRIPT_DIR}/../PACKAGE-BUILD.md" "${PKG_ROOT}/" 2>/dev/null || true

echo "${VERSION}" > "${PKG_ROOT}/VERSION"
chmod +x "${PKG_ROOT}/scripts/"*.sh "${PKG_ROOT}/gateway/scripts/"*.sh 2>/dev/null || true

echo ""
echo "=== Package summary ==="
du -sh "${PKG_ROOT}/docker" "${PKG_ROOT}/tools" "${PKG_ROOT}/gateway" 2>/dev/null || true
echo ""
echo "=== Docker image variants ==="
if [ -f "${IMG_TAR[heavy]}" ]; then
    hs=$(du -sh "${IMG_TAR[heavy]}" 2>/dev/null | awk '{print $1}')
    echo "  heavy   : ${IMG_TAG[heavy]}  (${hs:-?})"
else
    echo "  heavy   : ${IMG_TAG[heavy]}  (NOT BUILT — cd ussdgateway/release-wildfly && ./build-docker.sh)"
fi
if [ -f "${IMG_TAR[alpine]}" ]; then
    as=$(du -sh "${IMG_TAR[alpine]}" 2>/dev/null | awk '{print $1}')
    echo "  alpine  : ${IMG_TAG[alpine]}  (${as:-?})"
else
    echo "  alpine  : ${IMG_TAG[alpine]}  (NOT BUILT — cd ussdgw-prod-release/gateway && ./build-docker-alpine.sh)"
fi
echo ""
echo "Active for this run: ${USSDGW_IMAGE_VARIANT} (override: USSDGW_IMAGE_VARIANT=heavy|alpine|auto)"
echo ""
echo "Done. Create archive:"
echo "  tar czf ussdgw-prod-release-${VERSION}.tar.gz -C $(dirname "${PKG_ROOT}") $(basename "${PKG_ROOT}")"
