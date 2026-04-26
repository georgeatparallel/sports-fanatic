#!/usr/bin/env bash
set -euo pipefail

# Database restore for Sports Fanatic.
# Restores from a pg_dump custom-format file or an S3 key.

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
Usage: db_restore.sh <dump_file_or_s3_key> [OPTIONS]

Arguments:
  dump_file_or_s3_key   Path to local .dump file or S3 key (starts with s3://)

Options:
  --force               Skip confirmation prompt
  --drop                Drop and recreate database before restoring
  --jobs N              Number of parallel restore jobs (default: 1)
  -h, --help            Show this help message

Environment variables:
  PGHOST                Database host (auto-detected: Docker 'db' or localhost)
  PGPORT                Database port (default: 5432)
  PGUSER                Database user (default: postgres)
  PGPASSWORD            Database password (default: postgres)
  PGDATABASE            Database name (default: sports_fanatic)
  S3_BUCKET             S3 bucket (required if using S3 source)
  S3_PREFIX             S3 key prefix (default: backups/sports-fanatic)
  AWS_PROFILE           AWS CLI profile (optional)
  AWS_REGION            AWS region (default: us-east-1)

Exit codes:
  0  Success
  1  General error
  2  pg_restore failure
  3  S3 download failure
  4  User cancelled
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

FORCE=false
DROP=false
JOBS=1
SOURCE=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)   usage ;;
    --force)     FORCE=true; shift ;;
    --drop)      DROP=true; shift ;;
    --jobs)
      if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        die 1 "--jobs requires a positive integer"
      fi
      JOBS="$2"; shift 2 ;;
    -*)          die 1 "Unknown option: $1. Use -h for help." ;;
    *)
      if [[ -n "$SOURCE" ]]; then
        die 1 "Unexpected argument: $1. Only one source file is allowed."
      fi
      SOURCE="$1"; shift ;;
  esac
done

if [[ -z "$SOURCE" ]]; then
  die 1 "No dump file or S3 key specified. Use -h for help."
fi

# --- Download from S3 if needed ---
DUMPFILE="$SOURCE"

if [[ "$SOURCE" == s3://* ]]; then
  log "Source is an S3 URI, downloading..."
  DOWNLOAD_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backups}"
  mkdir -p "$DOWNLOAD_DIR"
  DUMPFILE="$DOWNLOAD_DIR/$(basename "$SOURCE")"

  if ! "$SCRIPT_DIR/db_s3_sync.sh" download "$SOURCE" "$DUMPFILE"; then
    die 3 "Failed to download from S3: $SOURCE"
  fi
fi

# --- Validate dump file ---
if [[ ! -f "$DUMPFILE" ]]; then
  die 1 "Dump file not found: $DUMPFILE"
fi

if [[ ! -s "$DUMPFILE" ]]; then
  die 1 "Dump file is empty: $DUMPFILE"
fi

MAGIC="$(head -c 5 "$DUMPFILE")"
if [[ "$MAGIC" != "PGDMP" ]]; then
  die 1 "Invalid dump file: $DUMPFILE (expected PGDMP header, got '${MAGIC:0:5}')"
fi

FILESIZE="$(du -h "$DUMPFILE" | cut -f1 | tr -d ' ')"

# --- Confirmation prompt ---
if [[ "$FORCE" == false ]]; then
  log "Dump file: $DUMPFILE ($FILESIZE)"
  log "Target: ${PGDATABASE} on ${PGHOST}:${PGPORT}"
  if [[ "$DROP" == true ]]; then
    log "WARNING: --drop flag set. Database will be dropped and recreated."
  fi

  echo -n "This will restore into database '$PGDATABASE' on ${PGHOST}:${PGPORT}. Continue? (y/N) " >&2
  read -r REPLY
  if [[ "${REPLY,,}" != "y" ]]; then
    log "Restore cancelled by user"
    exit 4
  fi
fi

# --- Drop and recreate if requested ---
if [[ "$DROP" == true ]]; then
  log "Dropping database '$PGDATABASE'..."
  if ! dropdb --if-exists "$PGDATABASE"; then
    die 1 "Failed to drop database '$PGDATABASE'"
  fi

  log "Creating database '$PGDATABASE'..."
  if ! createdb "$PGDATABASE"; then
    die 1 "Failed to create database '$PGDATABASE'"
  fi

  INIT_SQL="$PROJECT_ROOT/priv/repo/init.sql"
  if [[ -f "$INIT_SQL" ]]; then
    log "Running init.sql to recreate extensions and schemas..."
    if ! psql -f "$INIT_SQL" "$PGDATABASE"; then
      die 1 "Failed to run init.sql"
    fi
  else
    log "WARNING: init.sql not found at $INIT_SQL, skipping schema initialization"
  fi
fi

# --- Run pg_restore ---
log "Restoring from $DUMPFILE ($FILESIZE) into '$PGDATABASE' (jobs: $JOBS)"

set +e
pg_restore --no-owner --no-acl --jobs "$JOBS" -d "$PGDATABASE" "$DUMPFILE"
RESTORE_EXIT=$?
set -e

if [[ "$RESTORE_EXIT" -eq 0 ]]; then
  log "Restore completed successfully"
elif [[ "$RESTORE_EXIT" -eq 1 ]]; then
  log "WARNING: pg_restore completed with warnings (exit code 1). Some non-critical errors may have occurred."
else
  die 2 "pg_restore failed with exit code $RESTORE_EXIT"
fi

# --- Summary ---
log "Restore complete: $DUMPFILE -> ${PGDATABASE}@${PGHOST}:${PGPORT}"
exit 0
