#!/usr/bin/env bash
set -euo pipefail

# S3 upload/list/download utility for database backups.
# Subcommands: upload <file>, list, download <key> [local_path]

S3_PREFIX="${S3_PREFIX:-backups/sports-fanatic}"
AWS_REGION="${AWS_REGION:-us-east-1}"

log() {
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

die() {
  local code="$1"; shift
  log "ERROR: $*"
  exit "$code"
}

usage() {
  cat >&2 <<'USAGE'
Usage: db_s3_sync.sh <command> [args]

Commands:
  upload <file>                Upload a local file to S3
  list                         List backups in S3
  download <key> [local_path]  Download a backup from S3

Environment variables:
  S3_BUCKET     (required) S3 bucket name
  S3_PREFIX     (optional) Key prefix, default: backups/sports-fanatic
  AWS_REGION    (optional) AWS region, default: us-east-1
  AWS_PROFILE   (optional) AWS CLI profile to use

Exit codes:
  0  Success
  1  General error (missing deps, bad args)
  2  S3 operation failure
USAGE
  exit 0
}

validate_deps() {
  if ! command -v aws &>/dev/null; then
    die 1 "AWS CLI is not installed. Install it from https://aws.amazon.com/cli/"
  fi

  if [[ -z "${S3_BUCKET:-}" ]]; then
    die 1 "S3_BUCKET environment variable is not set"
  fi
}

build_aws_args() {
  local args=("--region" "$AWS_REGION")
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    args+=("--profile" "$AWS_PROFILE")
  fi
  echo "${args[@]}"
}

cmd_upload() {
  local file="${1:-}"
  if [[ -z "$file" ]]; then
    die 1 "Usage: db_s3_sync.sh upload <file>"
  fi

  if [[ ! -f "$file" ]]; then
    die 1 "File not found: $file"
  fi

  local basename
  basename="$(basename "$file")"
  local s3_key="${S3_PREFIX}/${basename}"
  local s3_uri="s3://${S3_BUCKET}/${s3_key}"

  log "Uploading $(du -h "$file" | cut -f1 | tr -d ' ') to ${s3_uri}"

  local aws_args
  read -ra aws_args <<< "$(build_aws_args)"

  if ! aws s3 cp "$file" "$s3_uri" "${aws_args[@]}"; then
    die 2 "Failed to upload to S3: ${s3_uri}"
  fi

  log "Upload complete: ${s3_uri}"
}

cmd_list() {
  local s3_uri="s3://${S3_BUCKET}/${S3_PREFIX}/"

  log "Listing backups in ${s3_uri}"

  local aws_args
  read -ra aws_args <<< "$(build_aws_args)"

  if ! aws s3 ls "$s3_uri" "${aws_args[@]}"; then
    die 2 "Failed to list S3 objects at ${s3_uri}"
  fi
}

cmd_download() {
  local key="${1:-}"
  if [[ -z "$key" ]]; then
    die 1 "Usage: db_s3_sync.sh download <key> [local_path]"
  fi

  local local_path="${2:-$(basename "$key")}"

  # If key doesn't start with s3://, build the full URI
  local s3_uri
  if [[ "$key" == s3://* ]]; then
    s3_uri="$key"
  else
    # Strip prefix if already included
    local clean_key="${key#${S3_PREFIX}/}"
    s3_uri="s3://${S3_BUCKET}/${S3_PREFIX}/${clean_key}"
  fi

  log "Downloading ${s3_uri} to ${local_path}"

  local aws_args
  read -ra aws_args <<< "$(build_aws_args)"

  if ! aws s3 cp "$s3_uri" "$local_path" "${aws_args[@]}"; then
    die 2 "Failed to download from S3: ${s3_uri}"
  fi

  log "Download complete: ${local_path}"
}

# --- Main ---

if [[ $# -lt 1 ]]; then
  usage
fi

case "${1:-}" in
  -h|--help) usage ;;
  upload)    validate_deps; shift; cmd_upload "$@" ;;
  list)      validate_deps; shift; cmd_list "$@" ;;
  download)  validate_deps; shift; cmd_download "$@" ;;
  *)         die 1 "Unknown command: $1. Use -h for help." ;;
esac
