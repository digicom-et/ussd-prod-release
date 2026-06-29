#!/bin/bash
# =============================================================================
#  USSD Gateway — Full Build Pipeline
#  Clone/pull từ GitHub digicom-et → Maven build → Ant release → Docker image
#
#  Usage:
#    ./build-all.sh
#    SKIP_CLONE=1 ./build-all.sh
#    SKIP_DOCKER=1 ./build-all.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_DIR="${PROJECTS_DIR:-${SCRIPT_DIR}/../build-projects}"
WILDFLY_ZIP="${SCRIPT_DIR}/resources/wildfly-10.0.0.Final-cleaned.zip"
USSD_VERSION="${USSD_VERSION:-$(tr -d '[:space:]' < "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo '7.3.1-SNAPSHOT')}"
DOCKER_TAG="restcomm-ussd-zulu:${USSD_VERSION%-SNAPSHOT}"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
step()  { echo -e "\n${GREEN}━━━${NC} $* ${GREEN}━━━${NC}"; }

# ── Repos (digicom-et) ──────────────────────────────────────────────────────
REPOS=(
  "jain-slee|https://github.com/digicom-et/jain-slee.git"
  "jss7|https://github.com/digicom-et/jss7.git"
  "sip-servlets|https://github.com/digicom-et/sip-servlets.git"
  "jain-slee.ss7|https://github.com/digicom-et/jain-slee.ss7.git"
  "jain-slee.sip|https://github.com/digicom-et/jain-slee.sip.git"
  "jain-slee-http-okhttp|https://github.com/digicom-et/jain-slee-http-okhttp.git"
  "ussdgateway|https://github.com/digicom-et/ussdgw.git"
)

# ── Step 0: Java 8 ──────────────────────────────────────────────────────────
step "Step 0: Java 8 (Zulu)"
if command -v mise &>/dev/null; then
  mise install java@zulu-8 2>/dev/null || true
  export JAVA_HOME="$(mise where java@zulu-8 2>/dev/null || echo '')"
fi
if [ -z "${JAVA_HOME:-}" ] || [ ! -f "${JAVA_HOME}/bin/java" ]; then
  err "Java 8 required. Run: mise install java@zulu-8"
  exit 1
fi
"${JAVA_HOME}/bin/java" -version 2>&1 | head -1

# ── Step 1: Clone/Pull ──────────────────────────────────────────────────────
if [ "${SKIP_CLONE:-0}" != "1" ]; then
  step "Step 1: Clone/Pull from GitHub"
  mkdir -p "${PROJECTS_DIR}"
  for entry in "${REPOS[@]}"; do
    project="${entry%%|*}"
    url="${entry##*|}"
    dir="${PROJECTS_DIR}/${project}"
    if [ -d "${dir}/.git" ]; then
      info "Pull ${project}..."
      (cd "${dir}" && git fetch origin && git reset --hard origin/master 2>/dev/null || git reset --hard origin/main)
    else
      info "Clone ${project}..."
      git clone "${url}" "${dir}"
    fi
    echo "  ✓ ${project}"
  done
else
  step "Step 1: SKIPPED (SKIP_CLONE=1)"
fi

# ── Step 2: Maven install ───────────────────────────────────────────────────
if [ "${SKIP_MAVEN:-0}" != "1" ]; then
  step "Step 2: Maven install (dependency order)"
  _mvn() { info "$1"; cd "$2"; mvn clean install -DskipTests -q 2>&1 | tail -2; echo "  ✓ $1"; }
  _mvn "jain-slee"          "${PROJECTS_DIR}/jain-slee/jain-slee"
  _mvn "jSS7"               "${PROJECTS_DIR}/jss7"
  _mvn "sip-servlets"       "${PROJECTS_DIR}/sip-servlets"
  _mvn "jain-slee.ss7 RA"   "${PROJECTS_DIR}/jain-slee.ss7"
  _mvn "jain-slee.sip RA"   "${PROJECTS_DIR}/jain-slee.sip"
  _mvn "http-okhttp RA"     "${PROJECTS_DIR}/jain-slee-http-okhttp"
  _mvn "ussdgateway"        "${PROJECTS_DIR}/ussdgateway"
  info "All Maven builds completed"
else
  step "Step 2: SKIPPED (SKIP_MAVEN=1)"
fi

# ── Step 3: WildFly clean ───────────────────────────────────────────────────
step "Step 3: WildFly 10 clean"
mkdir -p "${SCRIPT_DIR}/resources"
if [ ! -f "${WILDFLY_ZIP}" ]; then
  SRC="${PROJECTS_DIR}/ussdgateway/release-wildfly/wildfly-10.0.0.Final-cleaned.zip"
  if [ -f "${SRC}" ]; then
    cp "${SRC}" "${WILDFLY_ZIP}"
    info "Copied from ussdgateway repo"
  else
    err "Not found: ${WILDFLY_ZIP} or ${SRC}"
    err "Download wildfly-10.0.0.Final.zip and save as resources/wildfly-10.0.0.Final-cleaned.zip"
    exit 1
  fi
fi
ls -lh "${WILDFLY_ZIP}"

# ── Step 4: Ant release ─────────────────────────────────────────────────────
step "Step 4: Build USSD distribution"
USSDGW_RELEASE="${PROJECTS_DIR}/ussdgateway/release-wildfly"
cp "${WILDFLY_ZIP}" "${USSDGW_RELEASE}/wildfly-10.0.0.Final-cleaned.zip"

# Pre-build SLEE AS7 + HTTP RA
JAINSLEE_AS7="${PROJECTS_DIR}/jain-slee/jain-slee/container/build/as7"
if [ -d "${JAINSLEE_AS7}" ]; then
  cd "${JAINSLEE_AS7}" && mvn -q clean package -Dmaven.test.skip=true 2>&1 | tail -2
fi
HTTP_RA="${PROJECTS_DIR}/jain-slee-http-okhttp/resources/http-servlet"
if [ -d "${HTTP_RA}" ]; then
  cd "${HTTP_RA}" && mvn -q clean install -Dmaven.test.skip=true 2>&1 | tail -2
fi

cd "${USSDGW_RELEASE}"
ant -f build-linux.xml clean release 2>&1 | tail -8
RELEASE_ZIP="${USSDGW_RELEASE}/restcomm-ussd-${USSD_VERSION}-linux.zip"
[ -f "${RELEASE_ZIP}" ] || { err "Release zip failed"; exit 1; }
ls -lh "${RELEASE_ZIP}"

# ── Step 5: Docker image ────────────────────────────────────────────────────
if [ "${SKIP_DOCKER:-0}" != "1" ]; then
  step "Step 5: Build Docker image"
  GATEWAY="${SCRIPT_DIR}/gateway"
  cp "${RELEASE_ZIP}" "${GATEWAY}/restcomm-ussd-${USSD_VERSION}-linux.zip"
  CMD=$(command -v docker 2>/dev/null || command -v podman)
  cd "${GATEWAY}"
  ${CMD} build --build-arg "USSD_VERSION=${USSD_VERSION}" --build-arg "CACHEBUST=$(date +%s)" \
    -t "${DOCKER_TAG}" -t restcomm-ussd-zulu:latest -f Dockerfile.zulu . 2>&1 | tail -8
  ${CMD} images | grep restcomm-ussd-zulu

  # Step 6: Save tar
  step "Step 6: Save Docker tar"
  mkdir -p "${SCRIPT_DIR}/docker"
  TAR="${SCRIPT_DIR}/docker/restcomm-ussd-zulu-${USSD_VERSION%-SNAPSHOT}.tar"
  ${CMD} save "${DOCKER_TAG}" -o "${TAR}"
  ls -lh "${TAR}"
else
  step "Step 5-6: SKIPPED (SKIP_DOCKER=1)"
fi

# ── Done ───────────────────────────────────────────────────────────────────
step "BUILD COMPLETE"
echo "  Version: ${USSD_VERSION}"
echo "  Image:   ${DOCKER_TAG}"
echo ""
echo "  Next: cd ${SCRIPT_DIR}"
echo "        ./scripts/01-load-docker-image.sh"
echo "        docker compose up -d"
