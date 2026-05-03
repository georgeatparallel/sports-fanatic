#!/usr/bin/env bash
set -euo pipefail

# Full deployment: build images, push to ECR, update kustomize tags, commit
# ArgoCD auto-syncs the change from the repo
# Usage: ./scripts/deploy.sh [--env prod|dev] [--service web|python-bridge|all]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
ENVIRONMENT="${ENVIRONMENT:-prod}"
SERVICE="all"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="sports-fanatic"
SKIP_BUILD="${SKIP_BUILD:-false}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Full deployment: build images, push to ECR, update kustomize tags."
    echo "ArgoCD auto-syncs the change from the repo."
    echo ""
    echo "Options:"
    echo "  --env ENV          Environment (dev|prod). Default: prod"
    echo "  --service SERVICE  Service to deploy (web|python-bridge|all). Default: all"
    echo "  --skip-build       Skip Docker build, only update tags"
    echo "  --region REGION    AWS region. Default: us-east-1"
    echo "  -h, --help         Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENVIRONMENT="$2"; shift 2 ;;
        --service) SERVICE="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD="true"; shift ;;
        --region) AWS_REGION="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    echo "Error: Could not determine AWS account ID."
    exit 1
fi

GIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"
OVERLAY_DIR="${PROJECT_ROOT}/infra/k8s/overlays/${ENVIRONMENT}"

echo "=== Deploy ==="
echo "Environment: $ENVIRONMENT"
echo "Service:     $SERVICE"
echo "Git SHA:     $GIT_SHA"
echo "Skip Build:  $SKIP_BUILD"
echo ""

# Step 1: Build and push images
if [[ "$SKIP_BUILD" != "true" ]]; then
    echo "--- Step 1: Building and pushing images ---"
    "$SCRIPT_DIR/make-ecr.sh" --env "$ENVIRONMENT" --service "$SERVICE"
    echo ""
fi

# Step 2: Update kustomize image tags
echo "--- Step 2: Updating kustomize image tags ---"
cd "$OVERLAY_DIR"

update_image_tag() {
    local service="$1"
    local image="${ECR_REGISTRY}/${REPO_PREFIX}/${service}"

    echo "Updating ${service} image tag to ${GIT_SHA}..."

    # Use kustomize edit to set the image tag
    if command -v kustomize &>/dev/null; then
        kustomize edit set image "${image}:latest=${image}:${GIT_SHA}"
    else
        kubectl kustomize edit set image "${image}:latest=${image}:${GIT_SHA}" 2>/dev/null || \
            sed -i.bak "s|newTag: .*|newTag: ${GIT_SHA}|" kustomization.yaml
    fi
}

case "$SERVICE" in
    web) update_image_tag "web" ;;
    python-bridge) update_image_tag "python-bridge" ;;
    all)
        update_image_tag "web"
        update_image_tag "python-bridge"
        ;;
esac

# Clean up backup files from sed
find "$OVERLAY_DIR" -name "*.bak" -delete 2>/dev/null || true

echo ""

# Step 3: Commit and push (triggers ArgoCD auto-sync)
echo "--- Step 3: Committing image tag update ---"
cd "$PROJECT_ROOT"
git add "infra/k8s/overlays/${ENVIRONMENT}/kustomization.yaml"

if git diff --cached --quiet; then
    echo "No changes to commit (tags already up to date)."
else
    git commit -m "deploy(${ENVIRONMENT}): update image tags to ${GIT_SHA}"
    git push
    echo "Pushed. ArgoCD will auto-sync shortly."
fi

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Monitor deployment:"
echo "  kubectl get pods -n sports-fanatic -w"
echo "  kubectl rollout status deployment/web -n sports-fanatic"
echo "  argocd app get sports-fanatic"
