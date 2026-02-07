#!/usr/bin/env bash
set -euo pipefail

# Bootstrap the local development environment.
# Usage: ./scripts/setup.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[setup]${NC} $*"; }
warn()  { echo -e "${YELLOW}[setup]${NC} $*"; }
error() { echo -e "${RED}[setup]${NC} $*" >&2; }

check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is not installed. Please install it first."
        return 1
    fi
    log "$1 found: $(command -v "$1")"
}

main() {
    log "Bootstrapping infra-deployer development environment..."
    echo

    # Check prerequisites
    log "Checking prerequisites..."
    local missing=0
    for cmd in docker go terraform aws gh; do
        if ! check_command "$cmd"; then
            missing=1
        fi
    done

    if [ "$missing" -eq 1 ]; then
        error "Some prerequisites are missing. Install them and re-run this script."
        exit 1
    fi
    echo

    # Verify Docker is running
    log "Verifying Docker daemon is running..."
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
    log "Docker is running."
    echo

    # Build Go application
    log "Building Go application..."
    (cd app && go mod download && go build -o /dev/null .)
    log "Go application builds successfully."
    echo

    # Validate Terraform
    log "Validating Terraform configuration..."
    (cd terraform && terraform init -backend=false -input=false > /dev/null 2>&1 && terraform validate)
    log "Terraform configuration is valid."
    echo

    # Start local stack
    log "Starting local development stack..."
    docker compose -f docker/docker-compose.yml up -d --build

    echo
    log "Local development environment is ready!"
    echo
    log "Services:"
    log "  Application:  http://localhost:8080"
    log "  Health Check: http://localhost:8080/health"
    log "  Metrics:      http://localhost:8080/metrics"
    log "  Prometheus:   http://localhost:9090"
    log "  Grafana:      http://localhost:3000 (admin/admin)"
    echo
    log "To stop: docker compose -f docker/docker-compose.yml down"
}

main "$@"
