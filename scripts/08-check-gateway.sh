#!/bin/bash
# Diagnose ussd-prod container + WildFly health (port 9990).
set -euo pipefail
source "$(dirname "$0")/env.sh"

C="${USSDGW_CONTAINER}"
MGMT_PORT=9990
HTTP_PORT=8080

echo "=== Gateway health check: ${C} ==="

if ! docker ps -a --format '{{.Names}}' | grep -qx "${C}"; then
    echo "FAIL: container '${C}' not found"
    echo "  → cd gateway && docker compose up -d"
    exit 1
fi

echo "--- docker ps ---"
docker ps -a --filter "name=^${C}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'

echo "--- docker health ---"
health=$(docker inspect "${C}" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' 2>/dev/null || echo unknown)
echo "Health: ${health}"
if [ "${health}" = "unhealthy" ]; then
    echo "Last health errors:"
    docker inspect "${C}" --format '{{range .State.Health.Log}}{{.Output}}{{end}}' 2>/dev/null | tail -5
fi

echo "--- ports on host (network_mode: host) ---"
if command -v ss >/dev/null; then
    ss -tlnp 2>/dev/null | grep -E ":${MGMT_PORT}|:${HTTP_PORT}" || echo "WARN: nothing listening on ${MGMT_PORT}/${HTTP_PORT}"
else
    netstat -tlnp 2>/dev/null | grep -E ":${MGMT_PORT}|:${HTTP_PORT}" || echo "WARN: nothing listening on ${MGMT_PORT}/${HTTP_PORT}"
fi

echo "--- curl health (WildFly 10: no /health on 9990) ---"
if curl -fsS -m 5 "http://127.0.0.1:${HTTP_PORT}/jolokia/version" >/dev/null 2>&1; then
    echo "OK: http://127.0.0.1:${HTTP_PORT}/jolokia/version"
elif curl -fsS -m 5 -u admin:admin \
    -H "Content-Type: application/json" \
    -d '{"operation":"read-attribute","address":[],"name":"server-state"}' \
    "http://127.0.0.1:${MGMT_PORT}/management" 2>/dev/null | grep -q '"running"'; then
    echo "OK: WildFly server-state=running (Jolokia not deployed — rebuild image with jolokia.war)"
else
    echo "FAIL: gateway not ready (no Jolokia, WildFly not running)"
    echo "  WildFly first boot often needs 3–5 minutes (SLEE deploy + patch JARs)."
    echo "  If GUI shows POST /jolokia/ 404 → missing jolokia.war in deployments."
    echo "  If still failing after 5 min, see logs below."
fi

echo "--- recent container log (last 40 lines) ---"
docker logs --tail 40 "${C}" 2>&1 || true

if [ -f /opt/ussdgw/log/server.log ]; then
    echo "--- /opt/ussdgw/log/server.log (last 20 lines) ---"
    tail -20 /opt/ussdgw/log/server.log
    echo "--- known error patterns in server.log ---"
    for pat in \
        'UnknownHostException: ussd-prod' \
        'Unresolved compilation problems' \
        'NoClassDefFoundError.*disruptor' \
        'HttpServletResourceEntryPoint' \
        'failed to connect to MAP service' \
        'compute-jvm.sh.*e+'; do
        if grep -qE "${pat}" /opt/ussdgw/log/server.log 2>/dev/null; then
            echo "  FOUND: ${pat} — see docs/e2e-grpc-ussd-test.md troubleshooting table"
        fi
    done
fi

echo "=== done ==="
