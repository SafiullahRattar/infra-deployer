#!/usr/bin/env bash
set -euo pipefail

# Manual deployment script. Use this as a backup when CI/CD is unavailable.
# Usage: ./scripts/deploy.sh [environment]
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - Docker installed and running
#   - Terraform installed
#
# Environment variables:
#   AWS_REGION       - AWS region (default: us-east-1)
#   AWS_ACCOUNT_ID   - AWS account ID (auto-detected if not set)
#   ECR_REPOSITORY   - ECR repository name (default: infra-deployer)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[deploy]${NC} $*"; }
warn()  { echo -e "${YELLOW}[deploy]${NC} $*"; }
error() { echo -e "${RED}[deploy]${NC} $*" >&2; }

ENVIRONMENT="${1:-production}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-infra-deployer}"
GIT_SHA="$(git rev-parse --short HEAD)"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
IMAGE_TAG="${GIT_SHA}-${TIMESTAMP}"

main() {
    log "Starting deployment to ${ENVIRONMENT}..."
    log "Image tag: ${IMAGE_TAG}"
    echo

    # Detect AWS account
    if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
        AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
    fi
    ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
    log "ECR URI: ${ECR_URI}"
    echo

    # Build Docker image
    log "Building Docker image..."
    docker build -t "${ECR_REPOSITORY}:${IMAGE_TAG}" -f docker/Dockerfile .
    docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" "${ECR_URI}:${IMAGE_TAG}"
    docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" "${ECR_URI}:latest"
    log "Image built and tagged."
    echo

    # Push to ECR
    log "Logging into ECR..."
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

    log "Pushing image to ECR..."
    docker push "${ECR_URI}:${IMAGE_TAG}"
    docker push "${ECR_URI}:latest"
    log "Image pushed."
    echo

    # Terraform
    log "Running Terraform..."
    cd terraform

    terraform init
    terraform plan \
        -var "container_image=${ECR_URI}:${IMAGE_TAG}" \
        -var "environment=${ENVIRONMENT}" \
        -out=tfplan

    echo
    warn "Review the plan above. Proceed with apply? (yes/no)"
    read -r CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        log "Deployment cancelled."
        exit 0
    fi

    terraform apply tfplan
    cd ..
    echo

    # Health check
    log "Running post-deploy health check..."
    ALB_DNS="$(terraform -chdir=terraform output -raw alb_dns_name)"
    ./scripts/health-check.sh "http://${ALB_DNS}"

    echo
    log "Deployment complete!"
    log "ALB endpoint: http://${ALB_DNS}"
    log "Image: ${ECR_URI}:${IMAGE_TAG}"
}

main "$@"
