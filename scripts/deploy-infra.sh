#!/usr/bin/env bash
set -euo pipefail

# Deploy AWS infrastructure with Terraform
# Usage: ./scripts/deploy-infra.sh [--env prod|dev] [--action plan|apply|destroy]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TF_DIR="${PROJECT_ROOT}/infra/terraform"

# Defaults
ENVIRONMENT="${ENVIRONMENT:-prod}"
ACTION="plan"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy AWS infrastructure with Terraform."
    echo ""
    echo "Options:"
    echo "  --env ENV        Environment (dev|prod). Default: prod"
    echo "  --action ACTION  Terraform action (init|plan|apply|destroy). Default: plan"
    echo "  -h, --help       Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENVIRONMENT="$2"; shift 2 ;;
        --action) ACTION="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Validate
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo "Error: --env must be 'dev' or 'prod'"
    exit 1
fi

if [[ "$ACTION" != "init" && "$ACTION" != "plan" && "$ACTION" != "apply" && "$ACTION" != "destroy" ]]; then
    echo "Error: --action must be init, plan, apply, or destroy"
    exit 1
fi

TFVARS_FILE="${TF_DIR}/${ENVIRONMENT}.tfvars"

if [[ ! -f "$TFVARS_FILE" ]]; then
    echo "Error: tfvars file not found: $TFVARS_FILE"
    exit 1
fi

echo "=== Terraform Deploy ==="
echo "Environment: $ENVIRONMENT"
echo "Action:      $ACTION"
echo "Tfvars:      $TFVARS_FILE"
echo ""

cd "$TF_DIR"

case "$ACTION" in
    init)
        echo "Initializing Terraform..."
        terraform init
        ;;
    plan)
        echo "Running Terraform plan..."
        terraform plan -var-file="$TFVARS_FILE" -out="${ENVIRONMENT}.tfplan"
        echo ""
        echo "Plan saved to ${ENVIRONMENT}.tfplan"
        echo "To apply: $0 --env $ENVIRONMENT --action apply"
        ;;
    apply)
        PLAN_FILE="${TF_DIR}/${ENVIRONMENT}.tfplan"
        if [[ -f "$PLAN_FILE" ]]; then
            echo "Applying saved plan..."
            terraform apply "$PLAN_FILE"
            rm -f "$PLAN_FILE"
        else
            echo "No saved plan found. Running plan + apply..."
            terraform apply -var-file="$TFVARS_FILE"
        fi
        ;;
    destroy)
        echo "WARNING: This will destroy all infrastructure for $ENVIRONMENT!"
        echo ""
        terraform destroy -var-file="$TFVARS_FILE"
        ;;
esac

echo ""
echo "=== Terraform $ACTION complete ==="
