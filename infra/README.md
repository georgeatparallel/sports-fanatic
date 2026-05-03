# Infrastructure Deployment Guide

Complete AWS infrastructure and Kubernetes deployment for Sports Fanatic.

## Architecture Overview

```
Internet → Route 53 → ALB (HTTPS/ACM) → EKS Cluster
                                           ├── web (Phoenix, port 4000)
                                           └── python-bridge (FastAPI, port 8000, internal)

EKS Nodes → RDS PostgreSQL 16 (private subnet)
EKS Nodes → ElastiCache/Valkey (private subnet)
Web Pods  → S3 (news articles, via IRSA)

ArgoCD watches: github.com/joestein/sports-fanatic → infra/k8s/overlays/prod/
External Secrets Operator syncs: AWS Secrets Manager → K8s Secrets
```

## Prerequisites

Install these tools before proceeding:

| Tool | Version | Installation |
|------|---------|-------------|
| AWS CLI | >= 2.x | `brew install awscli` |
| Terraform | >= 1.5 | `brew install terraform` |
| kubectl | >= 1.28 | `brew install kubectl` |
| Helm | >= 3.x | `brew install helm` |
| Docker | >= 24.x | Docker Desktop |
| kustomize | >= 5.x | `brew install kustomize` (optional, kubectl has built-in) |

## AWS Credentials Setup

1. Create an IAM user or assume a role with admin access (for initial setup only)
2. Configure AWS CLI:
   ```bash
   aws configure
   # Or use named profiles:
   export AWS_PROFILE=sports-fanatic
   ```
3. Verify access:
   ```bash
   aws sts get-caller-identity
   ```

## Step-by-Step First-Time Setup

### 1. Create Terraform State Backend

Before running Terraform, manually create the S3 bucket and DynamoDB table for state:

```bash
# Create S3 bucket for terraform state
aws s3api create-bucket \
  --bucket sports-fanatic-terraform-state \
  --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket sports-fanatic-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket sports-fanatic-terraform-state \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block public access
aws s3api put-public-access-block \
  --bucket sports-fanatic-terraform-state \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name sports-fanatic-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2. Deploy Infrastructure with Terraform

```bash
# Initialize terraform
./scripts/deploy-infra.sh --env prod --action init

# Review the plan
./scripts/deploy-infra.sh --env prod --action plan

# Apply (creates all AWS resources)
./scripts/deploy-infra.sh --env prod --action apply
```

This creates: VPC, EKS cluster, RDS, ElastiCache, ECR repos, Route 53 zone, ACM cert, S3 bucket, Secrets Manager, IAM roles.

**Important**: After apply, note the outputs:
- `nameservers` — Update your domain registrar (sports-fan-agent.com) with these NS records
- `ecr_web_repository_url` — Used in K8s manifests
- `eks_kubeconfig_command` — Run this to configure kubectl

### 3. Update Domain Registrar

Take the nameservers from terraform output and update your domain registrar:
```bash
cd infra/terraform
terraform output nameservers
```

Set these as the NS records for `sports-fan-agent.com` at your registrar. DNS propagation may take up to 48 hours.

### 4. Populate Secrets

Update AWS Secrets Manager with real values:

```bash
aws secretsmanager put-secret-value \
  --secret-id sports-fanatic-prod/app-secrets \
  --secret-string '{
    "DATABASE_URL": "ecto://sports_fanatic:PASSWORD@ENDPOINT/sports_fanatic",
    "SECRET_KEY_BASE": "GENERATE_WITH_mix_phx.gen.secret",
    "FANTASY_NERDS_API_KEY": "your-key",
    "ANTHROPIC_API_KEY": "sk-ant-your-key",
    "EXA_API_KEY": "your-key",
    "STRIPE_SECRET_KEY": "sk_live_your-key",
    "STRIPE_WEBHOOK_SECRET": "whsec_your-secret",
    "STRIPE_PRICE_MONTHLY": "price_xxxxx",
    "STRIPE_PRICE_YEARLY": "price_xxxxx"
  }'
```

**Note**: The `DATABASE_URL` is auto-populated by Terraform with the RDS endpoint and generated password. You only need to update the other values.

Generate SECRET_KEY_BASE:
```bash
mix phx.gen.secret
```

### 5. Update K8s Manifests

Replace placeholder values in the K8s manifests with your actual AWS account ID and terraform outputs:

```bash
# Get your account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get terraform outputs
cd infra/terraform
CERT_ARN=$(terraform output -raw certificate_arn 2>/dev/null || echo "pending")
VALKEY_ENDPOINT=$(terraform output -raw elasticache_endpoint 2>/dev/null || echo "pending")
WEB_ROLE_ARN=$(terraform output -raw web_service_account_role_arn 2>/dev/null || echo "pending")
ESO_ROLE_ARN=$(terraform output -raw external_secrets_role_arn 2>/dev/null || echo "pending")

# Update manifests (examples — do these manually or script them)
# infra/k8s/base/ingress.yaml: replace ACCOUNT_ID and CERTIFICATE_ID
# infra/k8s/base/web-serviceaccount.yaml: replace ACCOUNT_ID
# infra/k8s/base/eso-serviceaccount.yaml: replace ACCOUNT_ID
# infra/k8s/base/configmap.yaml: replace VALKEY_URL with actual endpoint
# infra/k8s/overlays/*/kustomization.yaml: replace ACCOUNT_ID in image names
```

### 6. Build and Push Docker Images

```bash
./scripts/make-ecr.sh --env prod
```

### 7. Bootstrap the Cluster

This installs ArgoCD, External Secrets Operator, and AWS Load Balancer Controller:

```bash
./scripts/bootstrap-cluster.sh --env prod
```

Save the ArgoCD admin password output by this script.

### 8. Verify Deployment

```bash
# Check pods are running
kubectl get pods -n sports-fanatic

# Check ingress/ALB is created
kubectl get ingress -n sports-fanatic

# Check external secrets are syncing
kubectl get externalsecret -n sports-fanatic

# Check ArgoCD application status
kubectl get application -n argocd
```

## Triggering a Deploy

After the initial setup, deployments are triggered by:

```bash
./scripts/deploy.sh --env prod
```

This script:
1. Builds Docker images
2. Pushes to ECR (tagged with git SHA)
3. Updates kustomize image tags
4. Commits and pushes to git
5. ArgoCD auto-syncs the change

### Deploy only one service:
```bash
./scripts/deploy.sh --env prod --service web
./scripts/deploy.sh --env prod --service python-bridge
```

### Skip build (just update tags):
```bash
./scripts/deploy.sh --env prod --skip-build
```

## Run Migrations

Migrations run automatically on container startup via `entrypoint.sh`. If you need to run them manually:

```bash
kubectl exec -n sports-fanatic deployment/web -- bin/sports_fanatic eval "SportsFanatic.Release.migrate"
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod -n sports-fanatic <pod-name>
kubectl logs -n sports-fanatic <pod-name>
```

### External Secrets not syncing
```bash
kubectl describe externalsecret -n sports-fanatic sports-fanatic-secrets
kubectl logs -n external-secrets deployment/external-secrets
```

### ALB not created
```bash
kubectl describe ingress -n sports-fanatic web
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

### ArgoCD sync issues
```bash
# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080 (admin / password from bootstrap)

# Or use CLI
argocd app get sports-fanatic
argocd app sync sports-fanatic
```

### Database connectivity
```bash
# Test from a pod
kubectl exec -n sports-fanatic deployment/web -- bin/sports_fanatic eval "SportsFanatic.Repo.query!(\"SELECT 1\")"
```

### Valkey/Redis connectivity
```bash
kubectl exec -n sports-fanatic deployment/web -- bin/sports_fanatic eval "SportsFanatic.Cache.get(\"test\")"
```

## Cost Estimate (~100 users)

| Resource | Type | Monthly Cost (approx) |
|----------|------|----------------------|
| EKS cluster | Control plane | $73 |
| EC2 (2x t3.medium) | Worker nodes | $60 |
| RDS (db.t3.small) | PostgreSQL | $25 |
| ElastiCache (cache.t3.micro) | Valkey | $12 |
| NAT Gateway | Single AZ | $32 |
| ALB | Application LB | $22 |
| Route 53 | Hosted zone | $1 |
| S3 | News storage | $1-5 |
| Secrets Manager | 9 secrets | $4 |
| **Total** | | **~$230-235/mo** |

## Environment Differences

| Setting | Dev | Prod |
|---------|-----|------|
| EKS nodes (min/desired/max) | 1/2/3 | 2/2/3 |
| RDS instance | db.t3.micro | db.t3.small |
| RDS storage | 20 GB | 50 GB |
| RDS backups | 1 day | 7 days |
| RDS deletion protection | No | Yes |
| Web replicas | 1 | 2 |
| HPA max replicas | 2 | 4 |
| Web CPU request/limit | 100m/250m | 250m/500m |
| Web memory request/limit | 256Mi/512Mi | 512Mi/1Gi |
| S3 bucket | sports-fanatic-news-dev | sports-fanatic-news |
