#!/usr/bin/env bash
set -euo pipefail

# Verify deployment health by checking key endpoints.
# Usage: ./scripts/health-check.sh [base_url]
#
# Exits 0 if all checks pass, 1 otherwise.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[health]${NC} $*"; }
warn()  { echo -e "${YELLOW}[health]${NC} $*"; }
error() { echo -e "${RED}[health]${NC} $*" >&2; }

BASE_URL="${1:-http://localhost:8080}"
MAX_RETRIES="${MAX_RETRIES:-30}"
RETRY_INTERVAL="${RETRY_INTERVAL:-10}"

check_endpoint() {
    local path="$1"
    local expected_status="${2:-200}"
    local url="${BASE_URL}${path}"

    local status
    status="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${url}" 2>/dev/null || echo "000")"

    if [ "${status}" = "${expected_status}" ]; then
        log "OK   ${path} -> ${status}"
        return 0
    else
        error "FAIL ${path} -> ${status} (expected ${expected_status})"
        return 1
    fi
}

wait_for_healthy() {
    log "Waiting for service to become healthy at ${BASE_URL}..."
    for i in $(seq 1 "${MAX_RETRIES}"); do
        if curl -sf --max-time 5 "${BASE_URL}/health" > /dev/null 2>&1; then
            log "Service is reachable after ${i} attempt(s)."
            return 0
        fi
        warn "Attempt ${i}/${MAX_RETRIES}: not healthy yet, retrying in ${RETRY_INTERVAL}s..."
        sleep "${RETRY_INTERVAL}"
    done
    error "Service did not become healthy after ${MAX_RETRIES} attempts."
    return 1
}

main() {
    log "Running health checks against ${BASE_URL}"
    echo

    # Wait for the service to be reachable
    if ! wait_for_healthy; then
        exit 1
    fi
    echo

    # Check individual endpoints
    local failures=0

    log "Checking endpoints..."
    check_endpoint "/health" "200"       || ((failures++))
    check_endpoint "/metrics" "200"      || ((failures++))
    check_endpoint "/api/v1/status" "200" || ((failures++))
    check_endpoint "/" "200"             || ((failures++))
    echo

    # Validate health response body
    log "Validating /health response..."
    local body
    body="$(curl -sf --max-time 10 "${BASE_URL}/health" 2>/dev/null)"
    if echo "${body}" | grep -q '"status"'; then
        log "OK   /health response contains status field"
    else
        error "FAIL /health response missing status field"
        ((failures++))
    fi

    # Validate metrics endpoint has Prometheus format
    log "Validating /metrics response..."
    local metrics
    metrics="$(curl -sf --max-time 10 "${BASE_URL}/metrics" 2>/dev/null)"
    if echo "${metrics}" | grep -q "http_requests_total"; then
        log "OK   /metrics contains http_requests_total"
    else
        error "FAIL /metrics missing expected metric http_requests_total"
        ((failures++))
    fi
    echo

    if [ "${failures}" -gt 0 ]; then
        error "${failures} health check(s) failed."
        exit 1
    fi

    log "All health checks passed!"
}

main "$@"
