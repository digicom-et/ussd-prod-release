#!/bin/bash
# Poll WildFly readiness every 5s until OK or timeout.
# WildFly 10 has no MicroProfile /health on 9990 — use Jolokia or management API.

_gateway_health_ok() {
    local host="${1:-127.0.0.1}"

    if curl -fsS -m 5 "http://${host}:8080/jolokia/version" >/dev/null 2>&1; then
        return 0
    fi

    local body='{"operation":"read-attribute","address":[],"name":"server-state"}'
    if curl -fsS -m 5 -u admin:admin \
        -H "Content-Type: application/json" \
        -d "${body}" \
        "http://${host}:9990/management" 2>/dev/null | grep -q '"running"'; then
        return 0
    fi

    return 1
}

wait_gateway_health() {
    local max_attempts="${1:-60}"
    local interval=5
    local container="${USSDGW_CONTAINER:-ussd-prod}"

    echo "Waiting for gateway (Jolokia or WildFly management, up to $((max_attempts * interval / 60)) min)..."
    for i in $(seq 1 "${max_attempts}"); do
        echo "  [${i}/${max_attempts}] probe 8080/jolokia/version or 9990/management"
        if _gateway_health_ok "127.0.0.1"; then
            echo "Gateway healthy."
            return 0
        fi
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${container}"; then
            if docker exec "${container}" curl -fsS -m 5 "http://127.0.0.1:8080/jolokia/version" >/dev/null 2>&1; then
                echo "Gateway healthy (container Jolokia)."
                return 0
            fi
            if docker exec "${container}" sh -c \
                'curl -fsS -m 5 -u admin:admin -H "Content-Type: application/json" -d "{\"operation\":\"read-attribute\",\"address\":[],\"name\":\"server-state\"}" http://127.0.0.1:9990/management' 2>/dev/null \
                | grep -q '"running"'; then
                echo "Gateway healthy (container management API)."
                return 0
            fi
        fi
        if [ "${i}" -lt "${max_attempts}" ]; then
            sleep "${interval}"
        fi
    done
    return 1
}
