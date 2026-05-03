#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a fresh EKS cluster with required controllers and operators
# Usage: ./scripts/bootstrap-cluster.sh [--env prod|dev]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
ENVIRONMENT="${ENVIRONMENT:-prod}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="sports-fanatic"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Bootstrap a fresh EKS cluster with ArgoCD, External Secrets Operator,"
    echo "and AWS Load Balancer Controller."
    echo ""
    echo "Options:"
    echo "  --env ENV      Environment (dev|prod). Default: prod"
    echo "  --region REG   AWS region. Default: us-east-1"
    echo "  -h, --help     Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENVIRONMENT="$2"; shift 2 ;;
        --region) AWS_REGION="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

CLUSTER_NAME="${PROJECT_NAME}-${ENVIRONMENT}-eks"
NAME_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"

echo "=== Cluster Bootstrap ==="
echo "Cluster:     $CLUSTER_NAME"
echo "Environment: $ENVIRONMENT"
echo "Region:      $AWS_REGION"
echo ""

# Step 1: Update kubeconfig
echo "--- Step 1: Updating kubeconfig ---"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl cluster-info
echo ""

# Step 2: Add Helm repos
echo "--- Step 2: Adding Helm repositories ---"
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update
echo ""

# Step 3: Install AWS Load Balancer Controller
echo "--- Step 3: Installing AWS Load Balancer Controller ---"

# Get the ALB controller role ARN from terraform output
ALB_ROLE_ARN=$(cd "$PROJECT_ROOT/infra/terraform" && terraform output -raw alb_controller_role_arn 2>/dev/null || echo "")

if [[ -z "$ALB_ROLE_ARN" ]]; then
    echo "Warning: Could not get ALB controller role ARN from terraform."
    echo "You may need to set it manually."
    ALB_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/${NAME_PREFIX}-alb-controller-role"
fi

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ALB_ROLE_ARN" \
    --set region="$AWS_REGION" \
    --set vpcId="$(cd "$PROJECT_ROOT/infra/terraform" && terraform output -raw vpc_id 2>/dev/null || echo "CHANGE_ME")" \
    --wait
echo ""

# Step 4: Install External Secrets Operator
echo "--- Step 4: Installing External Secrets Operator ---"

ESO_ROLE_ARN=$(cd "$PROJECT_ROOT/infra/terraform" && terraform output -raw external_secrets_role_arn 2>/dev/null || echo "")

if [[ -z "$ESO_ROLE_ARN" ]]; then
    echo "Warning: Could not get ESO role ARN from terraform."
    ESO_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/${NAME_PREFIX}-eso-role"
fi

helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --create-namespace \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ESO_ROLE_ARN" \
    --wait
echo ""

# Step 5: Install ArgoCD
echo "--- Step 5: Installing ArgoCD ---"
helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --values "$PROJECT_ROOT/infra/argocd/values.yaml" \
    --wait
echo ""

# Step 6: Get ArgoCD admin password
echo "--- Step 6: ArgoCD Admin Credentials ---"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD URL:      https://argocd.sports-fan-agent.com (or port-forward below)"
echo "ArgoCD Username: admin"
echo "ArgoCD Password: $ARGOCD_PASSWORD"
echo ""
echo "To port-forward ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then open: https://localhost:8080"
echo ""

# Step 7: Create the sports-fanatic namespace
echo "--- Step 7: Creating application namespace ---"
kubectl create namespace sports-fanatic 2>/dev/null || echo "Namespace 'sports-fanatic' already exists"
echo ""

# Step 8: Apply the ArgoCD Application
echo "--- Step 8: Deploying ArgoCD Application ---"
kubectl apply -f "$PROJECT_ROOT/infra/argocd/application.yaml"
echo ""

echo "=== Bootstrap complete ==="
echo ""
echo "Next steps:"
echo "  1. Populate secrets in AWS Secrets Manager (see infra/README.md)"
echo "  2. Build and push Docker images: ./scripts/make-ecr.sh --env $ENVIRONMENT"
echo "  3. Update ACCOUNT_ID placeholders in k8s manifests"
echo "  4. ArgoCD will auto-sync from infra/k8s/overlays/prod/"
echo "  5. Verify with: kubectl get pods -n sports-fanatic"
