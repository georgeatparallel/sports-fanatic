# DevOps Guide

## Infrastructure Overview

Sports Fanatic runs on AWS with the following architecture:

```
Route 53 (DNS) → ACM (TLS) → ALB (HTTPS)
  ↓
EKS Cluster (Kubernetes 1.29+)
  ├── web pods (Phoenix, 2-4 replicas, HPA)
  └── python-bridge pods (FastAPI, 1-2 replicas)
  
Data:
  ├── RDS PostgreSQL 16 (private subnet)
  ├── ElastiCache Valkey (private subnet)
  └── S3 (news article storage)

Secrets:
  └── AWS Secrets Manager → External Secrets Operator → K8s Secrets
```

## Terraform Infrastructure

All infrastructure is defined as code in `infra/terraform/`.

### Modules

| Module | Path | Resources |
|--------|------|-----------|
| VPC | `modules/vpc/` | VPC, 2 public + 2 private subnets, NAT Gateway, IGW, route tables |
| ECR | `modules/ecr/` | Container registries for `web` and `python-bridge` images |
| EKS | `modules/eks/` | EKS cluster, managed node group, OIDC provider for IRSA |
| RDS | `modules/rds/` | PostgreSQL 16, parameter group, security group, automated backups |
| ElastiCache | `modules/elasticache/` | Valkey replication group, security group |
| S3 | `modules/s3/` | News article bucket, versioning, encryption |
| DNS | `modules/dns/` | Route 53 hosted zone, ACM certificate with DNS validation |
| Secrets | `modules/secrets/` | Secrets Manager entries, auto-populated with RDS credentials |
| IAM | `modules/iam/` | IRSA roles for web pods (S3 access) and ESO (secrets access) |

### Environment Configs

| File | Environment | Key Differences |
|------|-------------|-----------------|
| `dev.tfvars` | Development | 1 node, t3.micro, 20 GB storage, single AZ |
| `prod.tfvars` | Production | 2 nodes, t3.small, 50 GB storage, 7-day backups, multi-AZ |

### Commands

```bash
# Initialize Terraform
cd infra/terraform
terraform init

# Plan for production
terraform plan -var-file=prod.tfvars -out=prod.tfplan

# Apply
terraform apply prod.tfplan

# Or use the wrapper script
./scripts/deploy-infra.sh prod plan
./scripts/deploy-infra.sh prod apply
```

### Estimated Monthly Cost (~100 users)

| Resource | Type | Cost |
|----------|------|------|
| EKS control plane | Managed | $73 |
| EC2 worker nodes | 2x t3.medium | $60 |
| RDS PostgreSQL | db.t3.small | $25 |
| ElastiCache Valkey | cache.t3.micro | $12 |
| NAT Gateway | Single AZ | $32 |
| ALB | Application LB | $22 |
| Route 53 | Hosted zone | $1 |
| S3 | News storage | $1-5 |
| Secrets Manager | 9 secrets | $4 |
| **Total** | | **~$230-235/mo** |

## Kubernetes Deployment

### Manifest Structure

```
infra/k8s/
├── base/                        # Common manifests
│   ├── namespace.yaml           # sports-fanatic namespace
│   ├── configmap.yaml           # App configuration
│   ├── secret-store.yaml        # AWS Secrets Manager store
│   ├── external-secret.yaml     # Secret sync from AWS
│   ├── web-deployment.yaml      # Phoenix app (2+ replicas)
│   ├── python-bridge-deployment.yaml  # FastAPI (internal)
│   ├── web-service.yaml         # ClusterIP for web
│   ├── python-bridge-service.yaml     # ClusterIP for python-bridge
│   ├── ingress.yaml             # ALB Ingress (HTTPS)
│   ├── hpa.yaml                 # HPA (min 2, max 4, CPU target 70%)
│   ├── web-serviceaccount.yaml  # IRSA for S3 access
│   ├── eso-serviceaccount.yaml  # IRSA for ESO
│   └── kustomization.yaml
├── overlays/dev/                # Dev overrides (1 replica, smaller resources)
└── overlays/prod/               # Prod overrides (2 replicas, larger resources)
```

### Key Configurations

**Web Deployment** (`web-deployment.yaml`):
- Image: `{account}.dkr.ecr.{region}.amazonaws.com/sports-fanatic-web:latest`
- Replicas: 2 (prod), 1 (dev)
- Resources: 256Mi-512Mi RAM, 250m-500m CPU (prod)
- Health check: `GET /health` every 30s
- Env: ConfigMap + ExternalSecret

**HPA** (`hpa.yaml`):
- Min replicas: 2, Max: 4
- Target CPU utilization: 70%
- Scale-up stabilization: 60s
- Scale-down stabilization: 300s

## Deployment Pipeline

### Build and Deploy

```bash
# 1. Build Docker images and push to ECR
./scripts/make-ecr.sh

# 2. Update image tags in kustomization
# (scripts/deploy.sh does this automatically)
./scripts/deploy.sh prod

# 3. ArgoCD syncs automatically (if configured)
# Or manually:
argocd app sync sports-fanatic
```

### Manual Deployment Steps

```bash
# Build images
docker build -t sports-fanatic-web .
docker build -t sports-fanatic-python-bridge ./python_bridge

# Tag and push to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin {account}.dkr.ecr.us-east-1.amazonaws.com
docker tag sports-fanatic-web:latest {account}.dkr.ecr.us-east-1.amazonaws.com/sports-fanatic-web:$(git rev-parse --short HEAD)
docker push {account}.dkr.ecr.us-east-1.amazonaws.com/sports-fanatic-web:$(git rev-parse --short HEAD)

# Update kustomize image tag
cd infra/k8s/overlays/prod
kustomize edit set image sports-fanatic-web={account}.dkr.ecr.us-east-1.amazonaws.com/sports-fanatic-web:$(git rev-parse --short HEAD)

# Apply
kubectl apply -k infra/k8s/overlays/prod
```

## ArgoCD (GitOps)

ArgoCD watches `infra/k8s/overlays/prod/` and auto-syncs changes.

**Configuration**: `infra/argocd/application.yaml`
- Source: Git repo, path `infra/k8s/overlays/prod/`
- Destination: EKS cluster, `sports-fanatic` namespace
- Sync policy: Automated with prune and self-heal

### Bootstrap

```bash
# Install ArgoCD and supporting operators
./scripts/bootstrap-cluster.sh

# This installs:
# - ArgoCD (Helm)
# - External Secrets Operator (Helm)
# - AWS Load Balancer Controller (Helm)
# - Creates sports-fanatic namespace
```

## Database Operations

### Backup & Restore

```bash
# Local backup
./scripts/db_backup.sh

# Backup to S3
S3_BUCKET=my-bucket ./scripts/db_backup.sh

# Specific schemas
./scripts/db_backup.sh --schemas public,mlb,content

# Restore from local
./scripts/db_restore.sh backups/file.dump --force

# Restore from S3
./scripts/db_restore.sh s3://bucket/path/file.dump --force --drop

# Parallel restore (faster)
./scripts/db_restore.sh backups/file.dump --force --jobs 4
```

### Migrations in Production

```bash
# Via entrypoint (automatic on deploy)
# The entrypoint.sh runs: bin/sports_fanatic eval "SportsFanatic.Release.migrate"

# Manual
kubectl exec -it deploy/web -n sports-fanatic -- bin/sports_fanatic eval "SportsFanatic.Release.migrate()"

# Or via Docker
docker compose exec web bin/sports_fanatic eval "SportsFanatic.Release.migrate()"
```

## Monitoring

### Health Checks

| Service | Endpoint | Interval |
|---------|----------|----------|
| Phoenix | `GET /health` | 30s (Docker + K8s) |
| Python Bridge | `GET /health` | 30s (PythonBridge.HealthCheck GenServer) |
| PostgreSQL | `pg_isready` | 5s (Docker healthcheck) |
| Valkey | `valkey-cli ping` | 5s (Docker healthcheck) |

### Logs

```bash
# Docker
docker compose logs -f web
docker compose logs -f python-bridge

# Kubernetes
kubectl logs -f deploy/web -n sports-fanatic
kubectl logs -f deploy/python-bridge -n sports-fanatic
```

### Phoenix Live Dashboard

Available in development at `http://localhost:4000/dev/dashboard`:
- Process info, ETS tables, ports
- Oban job queue status
- Ecto query performance
- LiveView socket connections

## Environment Variables

See `.env.example` for the complete list. Key production variables:

| Variable | Source in K8s | Description |
|----------|--------------|-------------|
| `SECRET_KEY_BASE` | ExternalSecret (Secrets Manager) | Phoenix session signing |
| `DATABASE_URL` | ExternalSecret (auto from RDS) | PostgreSQL connection |
| `VALKEY_URL` | ConfigMap | ElastiCache endpoint |
| `ANTHROPIC_API_KEY` | ExternalSecret | Claude API |
| `EXA_API_KEY` | ExternalSecret | Exa.ai search |
| `STRIPE_SECRET_KEY` | ExternalSecret | Stripe payments |
| `JOSHUA_USERNAME` | ExternalSecret | Admin gate credentials |
| `JOSHUA_PASSWORD` | ExternalSecret | Admin gate credentials |

## Docker Compose (Local Development)

5 services defined in `docker-compose.yml`:

| Service | Image | Ports | Notes |
|---------|-------|-------|-------|
| `web` | Built from `Dockerfile` | 4000 | Phoenix release |
| `db` | `postgres:16-alpine` | 25432 | Persistent volume |
| `cache` | `valkey/valkey:8-alpine` | 6379 | Persistent volume |
| `python-bridge` | Built from `python_bridge/Dockerfile` | 8000 (internal) | |
| `stripe-cli` | `stripe/stripe-cli` | — | Dev profile only |

```bash
docker compose up -d              # Start all services
docker compose --profile dev up   # Include Stripe CLI
docker compose build web          # Rebuild Phoenix container
docker compose logs -f web        # Follow logs
```
