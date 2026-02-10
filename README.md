# infra-deployer

A lightweight deployment orchestrator for containerized applications on AWS. Provides production-grade infrastructure as code, CI/CD pipelines, and observability -- all wired together and ready to deploy.

## Architecture

### Deployment Pipeline

```
                            +------------------+
                            |    Developer     |
                            +--------+---------+
                                     |
                              git push / PR
                                     |
                            +--------v---------+
                            |  GitHub Actions  |
                            |  (CI Pipeline)   |
                            +---+---------+----+
                                |         |
                         docker build   terraform
                                |         plan/apply
                        +-------v---+     |
                        |    ECR    |     |
                        +-------+---+     |
                                |         |
                        +-------v---------v----+
                        |      ECS Fargate     |
                        |   (Private Subnet)   |
                        +----------+-----------+
                                   |
                        +----------v-----------+
                        |         ALB          |
                        |   (Public Subnet)    |
                        +----------+-----------+
                                   |
                            +------v------+
                            |    Users    |
                            +-------------+

               +-------------------------------------------+
               |            Monitoring Stack               |
               |  Prometheus --> Grafana --> Alert Rules    |
               +-------------------------------------------+
```

### Infrastructure Layout

```
+-----------------------------------------------------------------------+
|  VPC (10.0.0.0/16)                                                    |
|                                                                       |
|  +-----------------------------+  +-----------------------------+     |
|  | Public Subnet (AZ-a)       |  | Public Subnet (AZ-b)       |     |
|  |  10.0.0.0/24               |  |  10.0.1.0/24               |     |
|  |  +-------+   +---------+  |  |  +-------+                  |     |
|  |  |  NAT  |   |   ALB   |  |  |  |  ALB  |                  |     |
|  |  +-------+   +---------+  |  |  +-------+                  |     |
|  +-----------------------------+  +-----------------------------+     |
|                                                                       |
|  +-----------------------------+  +-----------------------------+     |
|  | Private Subnet (AZ-a)      |  | Private Subnet (AZ-b)      |     |
|  |  10.0.100.0/24             |  |  10.0.101.0/24             |     |
|  |  +----------+              |  |  +----------+              |     |
|  |  |   ECS    |              |  |  |   ECS    |              |     |
|  |  |  Fargate |              |  |  |  Fargate |              |     |
|  |  +----------+              |  |  +----------+              |     |
|  |  +----------+              |  |                             |     |
|  |  |   RDS    |              |  |                             |     |
|  |  | Postgres |              |  |                             |     |
|  |  +----------+              |  |                             |     |
|  +-----------------------------+  +-----------------------------+     |
+-----------------------------------------------------------------------+

Internet Gateway
       |
  Public Route Table --> IGW
  Private Route Table --> NAT Gateway
```

## Prerequisites

| Tool      | Version  | Purpose                      |
|-----------|----------|------------------------------|
| AWS CLI   | >= 2.x   | AWS resource management      |
| Terraform | >= 1.5   | Infrastructure as code       |
| Docker    | >= 24.x  | Container builds             |
| Go        | >= 1.22  | Build the example app        |
| gh CLI    | >= 2.x   | GitHub operations            |

You also need:
- An AWS account with programmatic access
- An S3 bucket for Terraform state (see `terraform/backend.tf`)
- A DynamoDB table for state locking

## Quick Start (Local Development)

```bash
# Clone the repo
git clone https://github.com/SafiullahRattar/infra-deployer.git
cd infra-deployer

# Run the bootstrap script
./scripts/setup.sh

# Or start manually
docker compose -f docker/docker-compose.yml up -d --build
```

This starts:
- **Application** on http://localhost:8080
- **PostgreSQL** on localhost:5432
- **Redis** on localhost:6379
- **Prometheus** on http://localhost:9090
- **Grafana** on http://localhost:3000 (admin / admin)

Endpoints:
| Path             | Description                  |
|------------------|------------------------------|
| `/health`        | Health check (JSON)          |
| `/metrics`       | Prometheus metrics           |
| `/api/v1/status` | Application status & runtime |

## Deployment Guide

### 1. Configure Remote State

Create the S3 bucket and DynamoDB table for Terraform state:

```bash
aws s3api create-bucket \
    --bucket infra-deployer-tfstate \
    --region us-east-1

aws s3api put-bucket-versioning \
    --bucket infra-deployer-tfstate \
    --versioning-configuration Status=Enabled

aws dynamodb create-table \
    --table-name infra-deployer-tflock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
```

### 2. Set Variables

Create a `terraform.tfvars` file (do **not** commit this):

```hcl
aws_region      = "us-east-1"
environment     = "production"
container_image = "<account-id>.dkr.ecr.us-east-1.amazonaws.com/infra-deployer:latest"
db_username     = "appuser"
db_password     = "use-a-strong-password"
```

### 3. Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Or use the manual deploy script:

```bash
./scripts/deploy.sh production
```

### 4. Verify

```bash
./scripts/health-check.sh http://$(terraform -chdir=terraform output -raw alb_dns_name)
```

## CI/CD Pipeline

### ci.yml (Push / PR to main)

1. **Lint** -- `go vet` and `gofmt` check
2. **Test** -- `go test -race` with coverage
3. **Build & Push** -- Multi-stage Docker build, push to ECR (main branch only)
4. **Terraform Validate** -- `terraform fmt -check` and `terraform validate`

### deploy.yml (Terraform changes)

- **On PR:** runs `terraform plan` and posts the output as a PR comment
- **On merge to main:** runs `terraform apply` followed by a health check

### rollback.yml (Manual trigger)

Manually triggered from the GitHub Actions UI. Rolls back the ECS service to the previous task definition revision (or a specific ARN you provide). Requires typing "rollback" as confirmation.

## Monitoring & Alerting

### Prometheus

Scrapes the `/metrics` endpoint every 10 seconds. Configuration is in `monitoring/prometheus/prometheus.yml`.

### Alert Rules (`monitoring/prometheus/alerts.yml`)

| Alert                | Condition                                      | Severity |
|----------------------|------------------------------------------------|----------|
| HighErrorRate        | > 5% of requests returning 5xx for 5 min       | critical |
| HighLatency          | p95 latency > 1s for 5 min                     | warning  |
| HighLatencyCritical  | p99 latency > 5s for 2 min                     | critical |
| ServiceDown          | Target unreachable for 1 min                   | critical |
| HighMemoryUsage      | RSS > 400MB for 5 min                          | warning  |
| TooManyGoroutines    | > 1000 goroutines for 5 min                    | warning  |
| HighDiskUsage        | Disk > 85% full for 10 min                     | warning  |
| HighCPUUsage         | CPU > 80% for 10 min                           | warning  |

### Grafana

A pre-built dashboard (`monitoring/grafana/dashboards/app-dashboard.json`) provides:
- Service status, request rate, error rate, and p95 latency at a glance
- Request rate by status code over time
- Latency distribution (p50 / p90 / p95 / p99)
- Request rate by endpoint
- Memory usage and goroutine count

## Cost Estimation

Approximate monthly costs for a minimal production deployment in us-east-1:

| Resource                  | Spec              | Est. Cost/mo |
|---------------------------|-------------------|-------------|
| NAT Gateway               | 1x                | ~$32        |
| ALB                       | 1x                | ~$16        |
| ECS Fargate (2 tasks)     | 0.25 vCPU, 512MB  | ~$15        |
| RDS PostgreSQL            | db.t3.micro       | ~$13        |
| S3 (minimal usage)        | < 1GB             | ~$1         |
| CloudWatch Logs           | Moderate volume   | ~$5         |
| **Total**                 |                   | **~$82**    |

Costs scale with traffic, task count, and data volume. Use Fargate Spot (configured as default capacity provider) to reduce compute costs by up to 70%.

## Design Decisions

**ECS Fargate over EKS.** Fargate eliminates cluster management overhead. For a service this size, the operational simplicity outweighs the flexibility of Kubernetes. The project can be extended to EKS if multi-service orchestration becomes necessary.

**Single NAT Gateway.** A single NAT gateway keeps costs low for non-critical environments. For production HA, deploy one NAT gateway per AZ by modifying the VPC module.

**Deployment circuit breaker.** The ECS service has `deployment_circuit_breaker` enabled with automatic rollback. If a deployment fails health checks, ECS reverts to the previous task definition without manual intervention.

**Fargate Spot as default capacity provider.** The cluster uses a weighted strategy: 1 base task on regular Fargate (guarantees availability) with additional tasks on Fargate Spot (up to 70% cheaper). The circuit breaker handles Spot interruptions.

**S3 lifecycle policies.** Objects transition to Standard-IA at 30 days and Glacier at 90 days. Non-current versions expire after 365 days. This balances cost with data retention requirements.

**Scratch-based Docker image.** The final image is built from `scratch` with only the compiled binary, timezone data, and CA certificates. This produces a minimal attack surface and an image under 15MB.

**Prometheus metrics in-app.** The Go application exports metrics natively using the Prometheus client library rather than relying on a sidecar. This eliminates the need for additional infrastructure and gives direct access to application-level metrics like request duration histograms.

## Project Structure

```
infra-deployer/
├── README.md
├── terraform/                    # Infrastructure as code
│   ├── main.tf                   # Root module - wires everything together
│   ├── variables.tf              # Input variables
│   ├── outputs.tf                # Output values
│   ├── providers.tf              # AWS provider config
│   ├── backend.tf                # S3 remote state backend
│   └── modules/
│       ├── vpc/                  # Networking (VPC, subnets, NAT, routes)
│       ├── ecs/                  # Compute (Fargate, ALB, auto-scaling)
│       ├── rds/                  # Database (PostgreSQL, parameter groups)
│       └── s3/                   # Storage (versioning, lifecycle, encryption)
├── docker/
│   ├── Dockerfile                # Multi-stage build (scratch-based)
│   ├── docker-compose.yml        # Local dev stack
│   └── .dockerignore
├── .github/workflows/
│   ├── ci.yml                    # Lint, test, build, push
│   ├── deploy.yml                # Terraform plan (PR) / apply (merge)
│   └── rollback.yml              # Manual rollback trigger
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml        # Scrape configuration
│   │   └── alerts.yml            # Alert rules
│   └── grafana/dashboards/
│       └── app-dashboard.json    # Pre-built Grafana dashboard
├── scripts/
│   ├── setup.sh                  # Bootstrap local dev environment
│   ├── deploy.sh                 # Manual deploy (backup for CI/CD)
│   └── health-check.sh           # Post-deploy verification
└── app/
    ├── main.go                   # HTTP server with graceful shutdown
    ├── handlers.go               # Routes, health, metrics, status
    ├── go.mod
    └── go.sum
```

## License

MIT
