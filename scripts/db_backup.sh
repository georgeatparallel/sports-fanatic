#!/usr/bin/env bash
set -euo pipefail

# Full database backup for Sports Fanatic.
# Creates a pg_dump custom-format backup with optional S3 upload.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."

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
Usage: db_backup.sh [OPTIONS]

Options:
  --no-s3           Skip S3 upload even if S3_BUCKET is set
  --schemas LIST    Comma-separated list of schemas to dump (e.g. public,mlb,content)
  -h, --help        Show this help message

Environment variables:
  PGHOST                 Database host (auto-detected: Docker 'db' or localhost)
  PGPORT                 Database port (default: 5432)
  PGUSER                 Database user (default: postgres)
  PGPASSWORD             Database password (default: postgres)
  PGDATABASE             Database name (default: sports_fanatic)
  BACKUP_DIR             Directory for backup files (default: PROJECT_ROOT/backups)
  BACKUP_RETENTION_DAYS  Days to keep local backups (default: 30)
  S3_BUCKET              S3 bucket for remote backups (optional)
  S3_PREFIX              S3 key prefix (default: backups/sports-fanatic)
  AWS_PROFILE            AWS CLI profile (optional)
  AWS_REGION             AWS region (default: us-east-1)

Exit codes:
  0  Success
  1  General error
  2  pg_dump failure
  3  S3 upload failure (local backup preserved)
USAGE
  exit 0
}

# --- Source .env if present ---
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  log "Loading environment from .env"
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

# --- Defaults ---
auto_detect_host() {
  if [[ -n "${PGHOST:-}" ]]; then
    return
  fi

  # Try to resolve 'db' hostname (Docker service name)
  if command -v getent &>/dev/null && getent hosts db &>/dev/null; then
    PGHOST="db"
  elif command -v host &>/dev/null && host db &>/dev/null 2>&1; then
    PGHOST="db"
  else
    PGHOST="localhost"
  fi
}

auto_detect_host

export PGHOST="${PGHOST}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export PGDATABASE="${PGDATABASE:-sports_fanatic}"

BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

NO_S3=false
SCHEMAS=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)   usage ;;
    --no-s3)     NO_S3=true; shift ;;
    --schemas)
      if [[ -z "${2:-}" ]]; then
        die 1 "--schemas requires a comma-separated list of schema names"
      fi
      SCHEMAS="$2"; shift 2 ;;
    *)           die 1 "Unknown option: $1. Use -h for help." ;;
  esac
done

# --- Validate pg_dump ---
if ! command -v pg_dump &>/dev/null; then
  die 1 "pg_dump is not installed"
fi

PG_DUMP_VERSION="$(pg_dump --version | grep -oE '[0-9]+' | head -1)"
if [[ "$PG_DUMP_VERSION" -lt 16 ]]; then
  die 1 "pg_dump version >= 16 required (found: $PG_DUMP_VERSION)"
fi

# --- Prepare backup directory ---
mkdir -p "$BACKUP_DIR"

# --- Build filename ---
FILENAME="sports_fanatic_$(date -u +%Y%m%d_%H%M%S).dump"
FILEPATH="$BACKUP_DIR/$FILENAME"

# --- Set restrictive permissions ---
umask 077

# --- Build pg_dump command ---
DUMP_ARGS=(-Fc --no-owner --no-acl -f "$FILEPATH")

if [[ -n "$SCHEMAS" ]]; then
  IFS=',' read -ra SCHEMA_LIST <<< "$SCHEMAS"
  for schema in "${SCHEMA_LIST[@]}"; do
    DUMP_ARGS+=(-n "$schema")
  done
  log "Dumping schemas: $SCHEMAS"
fi

# --- Run pg_dump ---
log "Starting backup of '$PGDATABASE' on ${PGHOST}:${PGPORT}"
log "Output: $FILEPATH"

if ! pg_dump "${DUMP_ARGS[@]}" "$PGDATABASE"; then
  rm -f "$FILEPATH"
  die 2 "pg_dump failed"
fi

# --- Verify output ---
if [[ ! -s "$FILEPATH" ]]; then
  rm -f "$FILEPATH"
  die 2 "pg_dump produced an empty file"
fi

FILESIZE="$(du -h "$FILEPATH" | cut -f1 | tr -d ' ')"
log "Backup created: $FILENAME ($FILESIZE)"

# --- Optional S3 upload ---
EXIT_CODE=0

if [[ -n "${S3_BUCKET:-}" ]] && [[ "$NO_S3" == false ]]; then
  log "Uploading to S3 (bucket: $S3_BUCKET)"
  if ! "$SCRIPT_DIR/db_s3_sync.sh" upload "$FILEPATH"; then
    log "WARNING: S3 upload failed. Local backup preserved at $FILEPATH"
    EXIT_CODE=3
  fi
elif [[ "$NO_S3" == true ]]; then
  log "S3 upload skipped (--no-s3 flag)"
elif [[ -z "${S3_BUCKET:-}" ]]; then
  log "S3 upload skipped (S3_BUCKET not set)"
fi

# --- Retention cleanup ---
DELETED_COUNT=0
while IFS= read -r -d '' old_file; do
  rm -f "$old_file"
  DELETED_COUNT=$((DELETED_COUNT + 1))
done < <(find "$BACKUP_DIR" -name "sports_fanatic_*.dump" -mtime +"$BACKUP_RETENTION_DAYS" -print0 2>/dev/null || true)

if [[ "$DELETED_COUNT" -gt 0 ]]; then
  log "Retention cleanup: removed $DELETED_COUNT backup(s) older than $BACKUP_RETENTION_DAYS days"
fi

# --- Summary ---
log "Backup complete: $FILEPATH ($FILESIZE)"
exit "$EXIT_CODE"
