#!/usr/bin/env bash
set -euo pipefail

# Build and push Docker images to AWS ECR
# Usage: ./scripts/make-ecr.sh [--env prod|dev] [--service web|python-bridge|all] [--tag TAG]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
ENVIRONMENT="${ENVIRONMENT:-prod}"
SERVICE="all"
CUSTOM_TAG=""
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="sports-fanatic"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build and push Docker images to AWS ECR."
    echo ""
    echo "Options:"
    echo "  --env ENV          Environment (dev|prod). Default: prod"
    echo "  --service SERVICE  Service to build (web|python-bridge|all). Default: all"
    echo "  --tag TAG          Custom tag (in addition to git SHA and latest)"
    echo "  --region REGION    AWS region. Default: us-east-1"
    echo "  -h, --help         Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENVIRONMENT="$2"; shift 2 ;;
        --service) SERVICE="$2"; shift 2 ;;
        --tag) CUSTOM_TAG="$2"; shift 2 ;;
        --region) AWS_REGION="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Validate environment
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo "Error: --env must be 'dev' or 'prod'"
    exit 1
fi

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    echo "Error: Could not determine AWS account ID. Check your AWS credentials."
    exit 1
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO_PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"
GIT_SHA=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD)

echo "=== ECR Build & Push ==="
echo "Environment: $ENVIRONMENT"
echo "Registry:    $ECR_REGISTRY"
echo "Git SHA:     $GIT_SHA"
echo ""

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY"

build_and_push() {
    local service="$1"
    local dockerfile="$2"
    local context="$3"
    local repo="${REPO_PREFIX}/${service}"
    local full_repo="${ECR_REGISTRY}/${repo}"

    echo ""
    echo "--- Building ${service} ---"
    echo "Dockerfile: ${dockerfile}"
    echo "Context:    ${context}"
    echo "Repository: ${full_repo}"

    # Build
    docker build \
        --no-cache \
        --platform linux/amd64 \
        -f "${PROJECT_ROOT}/${dockerfile}" \
        -t "${full_repo}:${GIT_SHA}" \
        -t "${full_repo}:latest" \
        "${PROJECT_ROOT}/${context}"

    # Apply custom tag if provided
    if [[ -n "$CUSTOM_TAG" ]]; then
        docker tag "${full_repo}:${GIT_SHA}" "${full_repo}:${CUSTOM_TAG}"
    fi

    # Push all tags
    echo "Pushing ${service}..."
    docker push "${full_repo}:${GIT_SHA}"
    docker push "${full_repo}:latest"
    if [[ -n "$CUSTOM_TAG" ]]; then
        docker push "${full_repo}:${CUSTOM_TAG}"
    fi

    echo "Done: ${full_repo}:${GIT_SHA}"
}

# Build services
case "$SERVICE" in
    web)
        build_and_push "web" "Dockerfile" "."
        ;;
    python-bridge)
        build_and_push "python-bridge" "python_bridge/Dockerfile" "python_bridge"
        ;;
    all)
        build_and_push "web" "Dockerfile" "."
        build_and_push "python-bridge" "python_bridge/Dockerfile" "python_bridge"
        ;;
    *)
        echo "Error: Unknown service '$SERVICE'. Use web, python-bridge, or all."
        exit 1
        ;;
esac

echo ""
echo "=== Build complete ==="
echo "Images tagged with: ${GIT_SHA}, latest${CUSTOM_TAG:+, $CUSTOM_TAG}"
