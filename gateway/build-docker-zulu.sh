#!/usr/bin/env bash
# =============================================================================
#  Build the USSD Gateway Zulu 8 JDK Docker image.
#
#  Produces:  restcomm-ussd-zulu:<USSD_VERSION>
#             restcomm-ussd-zulu:latest
#
#  Requirements:
#    - Source zip at  ./restcomm-ussd-<USSD_VERSION>-linux.zip
#      (produced by  ussdgateway/release-wildfly/build-docker.sh
#       OR           ussdgateway/release-wildfly/build-linux.xml  via ant)
#
#  Env vars:
#    USSD_VERSION   (default: 7.3.1)
#    IMAGE_TAG      (default: $USSD_VERSION)  — explicit tag override
#    SAVE_TAR       (default: 0)              — set to 1 to save
#                                              docker/restcomm-ussd-zulu-<VER>.tar
#
#  Examples:
#    ./build-docker-zulu.sh
#    USSD_VERSION=7.3.0-SNAPSHOT ./build-docker-zulu.sh
#    SAVE_TAR=1 ./build-docker-zulu.sh
# =============================================================================
set -euo pipefail

VERSION="${USSD_VERSION:-7.3.1}"
IMAGE_TAG="${IMAGE_TAG:-${VERSION}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# ---- Color helpers -----------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_BOLD="\033[1m"; C_DIM="\033[2m"; C_OK="\033[1;32m"
    C_WARN="\033[1;33m"; C_ERR="\033[1;31m"; C_RST="\033[0m"
else
    C_BOLD=""; C_DIM=""; C_OK=""; C_WARN=""; C_ERR=""; C_RST=""
fi
say()  { printf "%s==>%s %s\n" "${C_BOLD}" "${C_RST}" "$*"; }
ok()   { printf "%s  ✓%s %s\n" "${C_OK}"   "${C_RST}" "$*"; }
warn() { printf "%s  !%s %s\n" "${C_WARN}" "${C_RST}" "$*"; }
die()  { printf "%s  ✗%s %s\n" "${C_ERR}" "${C_RST}" "$*" >&2; exit 1; }

# ---- Pre-flight checks -------------------------------------------------------
say "USSD Gateway — Zulu 8 JDK image build"
printf "    %sUSSD_VERSION%s : %s\n" "${C_DIM}" "${C_RST}" "${VERSION}"
printf "    %sIMAGE_TAG%s     : %s\n" "${C_DIM}" "${C_RST}" "${IMAGE_TAG}"
printf "    %sSCRIPT_DIR%s    : %s\n" "${C_DIM}" "${C_RST}" "${SCRIPT_DIR}"

command -v docker >/dev/null 2>&1 || die "docker CLI not found in PATH"

SRC_ZIP="${SCRIPT_DIR}/restcomm-ussd-${VERSION}-linux.zip"
if [ ! -f "${SRC_ZIP}" ]; then
    die "missing source zip: ${SRC_ZIP}

To produce it, run ONE of:

  # Option A — full release build (rebuilds SLEE AS7 modules too, ~5-10 min)
  cd ../../ussdgateway/release-wildfly
  ./build-docker.sh           # step 1 builds the zip via ant
  cp restcomm-ussd-${VERSION}-linux.zip \
     \"${SCRIPT_DIR}/\"

  # Option B — release-only build (no docker build, ~1-2 min)
  cd ../../ussdgateway/release-wildfly
  ant -f build-linux.xml clean release
  cp dist/restcomm-ussd-${VERSION}-linux.zip \"${SRC_ZIP}\"
"
fi
ok "found source zip (${SRC_ZIP##*/})"

# Sanity-check required context files
for f in Dockerfile.zulu standalone.conf docker-entrypoint.sh \
         scripts/init-host-dirs.sh scripts/compute-jvm.sh \
         config-seed/configuration/mgmt-users.properties; do
    [ -f "${SCRIPT_DIR}/${f}" ] || die "missing build context file: ${f}"
done
ok "build context files present"

# ---- Docker build ------------------------------------------------------------
say "Building image restcomm-ussd-zulu:${IMAGE_TAG} (this takes a few minutes)..."
docker build \
    --progress=plain \
    --build-arg "USSD_VERSION=${VERSION}" \
    -f Dockerfile.zulu \
    -t "restcomm-ussd-zulu:${IMAGE_TAG}" \
    -t "restcomm-ussd-zulu:latest" \
    .

# ---- Image size + savings report --------------------------------------------
say "Image sizes"
ZULU_SIZE="$(docker images "restcomm-ussd-zulu:${IMAGE_TAG}" --format '{{.Size}}')"
printf "    %szulu%s : %s\n" "${C_DIM}" "${C_RST}" "${ZULU_SIZE}"

HEAVY_TAG="restcomm-ussd:${VERSION}"
if docker image inspect "${HEAVY_TAG}" >/dev/null 2>&1; then
    HEAVY_SIZE="$(docker images "${HEAVY_TAG}" --format '{{.Size}}')"
    printf "    %sheavy %s : %s\n" "${C_DIM}" "${C_RST}" "${HEAVY_SIZE}"

    # Convert human sizes (e.g. "347MB", "1.2GB") to bytes for subtraction.
    # Uses awk — works without bc.
    to_bytes() {
        awk -v s="$1" 'BEGIN{
            n = s; gsub(/[^0-9.]/,"",n); u = s; gsub(/[0-9. ]/,"",u); gsub(/^ +/,"",u)
            mul = (u=="GB"||u=="G") ? 1024*1024*1024 \
                : (u=="MB"||u=="M") ? 1024*1024 \
                : (u=="KB"||u=="K") ? 1024 \
                : (u=="B"||u=="")   ? 1 : 0
            printf "%d", n * mul
        }'
    }
    A="$(to_bytes "${ZULU_SIZE}")"
    H="$(to_bytes "${HEAVY_SIZE}")"
    if [ "${H}" -gt 0 ]; then
        SAVED=$(( H - A ))
        PCT=$(awk -v a="${A}" -v h="${H}" 'BEGIN{ if(h>0) printf "%.1f", (h-a)/h*100; else print "0.0" }')
        if [ "${SAVED}" -ge 0 ]; then
            SAVED_HUMAN="$(awk -v b="${SAVED}" 'BEGIN{
                if (b>=1024*1024*1024) printf "%.2f GB", b/1024/1024/1024
                else if (b>=1024*1024) printf "%.1f MB", b/1024/1024
                else printf "%d KB", b/1024
            }')"
            ok "estimated savings vs ${HEAVY_TAG}: ${SAVED_HUMAN} (${PCT}% smaller)"
        else
            warn "zulu image is LARGER than ${HEAVY_TAG} — investigate"
        fi
    fi
else
    printf "    %sheavy %s : (not present locally)\n" "${C_DIM}" "${C_RST}"
fi

# ---- Optional tar save -------------------------------------------------------
if [ "${SAVE_TAR:-0}" = "1" ]; then
    OUT_DIR="${SCRIPT_DIR}/../docker"
    mkdir -p "${OUT_DIR}"
    OUT_TAR="${OUT_DIR}/restcomm-ussd-zulu-${IMAGE_TAG}.tar"
    say "Saving image to ${OUT_TAR}"
    docker save -o "${OUT_TAR}" "restcomm-ussd-zulu:${IMAGE_TAG}"
    SIZE_BYTES="$(stat -c %s "${OUT_TAR}" 2>/dev/null || stat -f %z "${OUT_TAR}")"
    SIZE_HUMAN="$(awk -v b="${SIZE_BYTES}" 'BEGIN{
        if (b>=1024*1024*1024) printf "%.2f GB", b/1024/1024/1024
        else if (b>=1024*1024) printf "%.1f MB", b/1024/1024
        else printf "%d KB", b/1024
    }')"
    ok "saved ${OUT_TAR} (${SIZE_HUMAN})"
fi

ok "build complete"
echo
echo "Next steps:"
echo "  docker run --rm -it restcomm-ussd-zulu:${IMAGE_TAG} /usr/lib/jvm/zulu8/bin/java -version"
echo "  cd ../scripts && USSDGW_IMAGE_VARIANT=zulu ./build-package.sh"