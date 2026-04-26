#!/usr/bin/env bash
# Unit tests for db_backup.sh, db_restore.sh, and db_s3_sync.sh
# These tests do NOT require a live PostgreSQL database, pg_dump, pg_restore, or AWS CLI.
# They validate: syntax, argument parsing, help text, file validation, and env defaults.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS_DIR="$WORKTREE_ROOT/scripts"

BACKUP_SCRIPT="$SCRIPTS_DIR/db_backup.sh"
RESTORE_SCRIPT="$SCRIPTS_DIR/db_restore.sh"
S3_SYNC_SCRIPT="$SCRIPTS_DIR/db_s3_sync.sh"

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_case() {
  local name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  echo -n "  TEST: $name ... "
}

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo "PASS"; }

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "FAIL: $1"
}

section() { echo; echo "=== $1 ==="; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run a command in a clean subshell that sources minimal env only.
# Unsets all PG* and AWS* variables to avoid host env bleed.
clean_env() {
  env -i HOME="$HOME" PATH="$PATH" TMPDIR="${TMPDIR:-/tmp}" bash -c "$*"
}

# ---------------------------------------------------------------------------
# Section: Script files exist and are executable
# ---------------------------------------------------------------------------
section "Script existence and permissions"

test_case "db_backup.sh exists"
if [[ -f "$BACKUP_SCRIPT" ]]; then pass; else fail "not found at $BACKUP_SCRIPT"; fi

test_case "db_restore.sh exists"
if [[ -f "$RESTORE_SCRIPT" ]]; then pass; else fail "not found at $RESTORE_SCRIPT"; fi

test_case "db_s3_sync.sh exists"
if [[ -f "$S3_SYNC_SCRIPT" ]]; then pass; else fail "not found at $S3_SYNC_SCRIPT"; fi

test_case "db_backup.sh is readable"
if [[ -r "$BACKUP_SCRIPT" ]]; then pass; else fail "not readable"; fi

test_case "db_restore.sh is readable"
if [[ -r "$RESTORE_SCRIPT" ]]; then pass; else fail "not readable"; fi

test_case "db_s3_sync.sh is readable"
if [[ -r "$S3_SYNC_SCRIPT" ]]; then pass; else fail "not readable"; fi

# ---------------------------------------------------------------------------
# Section: Bash syntax validation
# ---------------------------------------------------------------------------
section "Bash syntax validation (bash -n)"

test_case "db_backup.sh syntax"
if bash -n "$BACKUP_SCRIPT" 2>/dev/null; then pass; else fail "syntax error"; fi

test_case "db_restore.sh syntax"
if bash -n "$RESTORE_SCRIPT" 2>/dev/null; then pass; else fail "syntax error"; fi

test_case "db_s3_sync.sh syntax"
if bash -n "$S3_SYNC_SCRIPT" 2>/dev/null; then pass; else fail "syntax error"; fi

# ---------------------------------------------------------------------------
# Section: Help flags (-h / --help)
# ---------------------------------------------------------------------------
section "Help flags exit 0 and print usage"

test_case "db_backup.sh -h exits 0"
if bash "$BACKUP_SCRIPT" -h >/dev/null 2>&1; then pass; else fail "non-zero exit"; fi

test_case "db_backup.sh --help exits 0"
if bash "$BACKUP_SCRIPT" --help >/dev/null 2>&1; then pass; else fail "non-zero exit"; fi

test_case "db_backup.sh --help prints Usage"
output="$(bash "$BACKUP_SCRIPT" --help 2>&1 || true)"
if echo "$output" | grep -qi "usage"; then pass; else fail "no 'usage' in output"; fi

test_case "db_restore.sh -h exits 0"
if bash "$RESTORE_SCRIPT" -h >/dev/null 2>&1; then pass; else fail "non-zero exit"; fi

test_case "db_restore.sh --help exits 0"
if bash "$RESTORE_SCRIPT" --help >/dev/null 2>&1; then pass; else fail "non-zero exit"; fi

test_case "db_restore.sh --help prints Usage"
output="$(bash "$RESTORE_SCRIPT" --help 2>&1 || true)"
if echo "$output" | grep -qi "usage"; then pass; else fail "no 'usage' in output"; fi

# db_s3_sync.sh --help exits 1 by design (usage exits 1 for the general no-command case);
# but -h / --help are routed through usage which also exits 1.
test_case "db_s3_sync.sh -h prints Usage (exit allowed non-zero)"
output="$(bash "$S3_SYNC_SCRIPT" -h 2>&1 || true)"
if echo "$output" | grep -qi "usage"; then pass; else fail "no 'usage' in output"; fi

test_case "db_s3_sync.sh --help prints Usage (exit allowed non-zero)"
output="$(bash "$S3_SYNC_SCRIPT" --help 2>&1 || true)"
if echo "$output" | grep -qi "usage"; then pass; else fail "no 'usage' in output"; fi

# ---------------------------------------------------------------------------
# Section: Missing required arguments
# ---------------------------------------------------------------------------
section "Missing required arguments"

test_case "db_restore.sh with no args exits non-zero"
bash "$RESTORE_SCRIPT" >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit, got 0"; fi

test_case "db_restore.sh with no args emits error message"
output="$(bash "$RESTORE_SCRIPT" 2>&1 || true)"
if echo "$output" | grep -qi "error\|no dump\|usage\|specify"; then pass; else fail "no error message in output"; fi

test_case "db_s3_sync.sh with no args exits non-zero"
bash "$S3_SYNC_SCRIPT" >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit, got 0"; fi

test_case "db_s3_sync.sh with no args emits usage/error"
output="$(bash "$S3_SYNC_SCRIPT" 2>&1 || true)"
if echo "$output" | grep -qi "usage\|command\|error"; then pass; else fail "no usage/error message"; fi

# ---------------------------------------------------------------------------
# Section: Unknown flags / commands
# ---------------------------------------------------------------------------
section "Unknown flags and commands"

test_case "db_backup.sh with unknown flag exits non-zero"
bash "$BACKUP_SCRIPT" --nonexistent-flag >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

test_case "db_backup.sh with unknown flag emits error"
output="$(bash "$BACKUP_SCRIPT" --nonexistent-flag 2>&1 || true)"
if echo "$output" | grep -qi "unknown\|error"; then pass; else fail "no error message"; fi

test_case "db_restore.sh with unknown flag exits non-zero"
# Provide a dummy source so argument parsing reaches the unknown flag check.
bash "$RESTORE_SCRIPT" /tmp/dummy.dump --nonexistent-flag >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

test_case "db_s3_sync.sh with unknown command exits non-zero"
bash "$S3_SYNC_SCRIPT" badcmd >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit, got 0"; fi

test_case "db_s3_sync.sh with unknown command emits error"
output="$(bash "$S3_SYNC_SCRIPT" badcmd 2>&1 || true)"
if echo "$output" | grep -qi "unknown\|error"; then pass; else fail "no error message"; fi

# ---------------------------------------------------------------------------
# Section: Restore with non-existent file
# ---------------------------------------------------------------------------
section "Restore with non-existent file"

test_case "db_restore.sh non-existent file exits 1"
bash "$RESTORE_SCRIPT" --force /tmp/does_not_exist_sf_test_12345.dump >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -eq 1 ]]; then pass; else fail "expected exit 1, got $exit_code"; fi

test_case "db_restore.sh non-existent file emits 'not found' error"
output="$(bash "$RESTORE_SCRIPT" --force /tmp/does_not_exist_sf_test_12345.dump 2>&1 || true)"
if echo "$output" | grep -qi "not found\|no such\|error"; then pass; else fail "no 'not found' in output"; fi

# ---------------------------------------------------------------------------
# Section: Restore with invalid dump file (bad PGDMP header)
# ---------------------------------------------------------------------------
section "Restore with invalid dump file"

TMPFILE="$(mktemp /tmp/sf_test_invalid_XXXXXX.dump)"
echo "THIS IS NOT A VALID PG DUMP FILE" > "$TMPFILE"

test_case "db_restore.sh invalid dump exits 1"
bash "$RESTORE_SCRIPT" --force "$TMPFILE" >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -eq 1 ]]; then pass; else fail "expected exit 1, got $exit_code"; fi

test_case "db_restore.sh invalid dump emits PGDMP header error"
output="$(bash "$RESTORE_SCRIPT" --force "$TMPFILE" 2>&1 || true)"
if echo "$output" | grep -qi "PGDMP\|header\|invalid"; then pass; else fail "no PGDMP/header/invalid in output; got: $output"; fi

rm -f "$TMPFILE"

# ---------------------------------------------------------------------------
# Section: Restore with empty file
# ---------------------------------------------------------------------------
section "Restore with empty file"

TMPEMPTY="$(mktemp /tmp/sf_test_empty_XXXXXX.dump)"
# File is created but empty (0 bytes).

test_case "db_restore.sh empty dump exits 1"
bash "$RESTORE_SCRIPT" --force "$TMPEMPTY" >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -eq 1 ]]; then pass; else fail "expected exit 1, got $exit_code"; fi

test_case "db_restore.sh empty dump emits error"
output="$(bash "$RESTORE_SCRIPT" --force "$TMPEMPTY" 2>&1 || true)"
if echo "$output" | grep -qi "empty\|error"; then pass; else fail "no 'empty' or 'error' in output; got: $output"; fi

rm -f "$TMPEMPTY"

# ---------------------------------------------------------------------------
# Section: Environment variable defaults
# ---------------------------------------------------------------------------
section "Environment variable defaults"

# We source each script in a subshell after the argument-parsing section.
# Because the scripts call pg_dump / pg_restore we cannot let them run to
# completion — instead we extract the defaults by printing variables before
# the binary execution sections.

# Technique: stub pg_dump as a no-op so the scripts can reach post-init state,
# then inspect env vars printed via a trap or environment introspection.
# Simpler approach: use a wrapper that overrides pg_dump and reads exported vars.

TMPBINDIR="$(mktemp -d /tmp/sf_test_bindir_XXXXXX)"

# Stub pg_dump: prints the PGPORT and PGDATABASE env vars then exits 1 (so the
# script aborts cleanly before doing real work).  We capture stderr where the
# script's log messages go; we capture stdout for our env dump.
cat > "$TMPBINDIR/pg_dump" <<'STUB'
#!/usr/bin/env bash
echo "STUB_PGPORT=${PGPORT:-UNSET}"
echo "STUB_PGDATABASE=${PGDATABASE:-UNSET}"
exit 99
STUB
chmod +x "$TMPBINDIR/pg_dump"

# Also stub pg_dump version check (--version)
cat > "$TMPBINDIR/pg_dump_version_check" <<'STUB'
#!/usr/bin/env bash
echo "pg_dump (PostgreSQL) 16.0"
STUB

# Override pg_dump to handle --version differently from the real dump call:
cat > "$TMPBINDIR/pg_dump" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "pg_dump (PostgreSQL) 16.0"
  exit 0
fi
echo "STUB_PGPORT=${PGPORT:-UNSET}"
echo "STUB_PGDATABASE=${PGDATABASE:-UNSET}"
exit 99
STUB
chmod +x "$TMPBINDIR/pg_dump"

test_case "db_backup.sh defaults PGPORT to 5432"
output="$(PATH="$TMPBINDIR:$PATH" \
  PGPORT="" PGDATABASE="" PGHOST="localhost" \
  bash "$BACKUP_SCRIPT" --no-s3 2>/dev/null || true)"
if echo "$output" | grep -q "STUB_PGPORT=5432"; then
  pass
else
  fail "PGPORT default not 5432; output: $output"
fi

test_case "db_backup.sh defaults PGDATABASE to sports_fanatic"
output="$(PATH="$TMPBINDIR:$PATH" \
  PGPORT="" PGDATABASE="" PGHOST="localhost" \
  bash "$BACKUP_SCRIPT" --no-s3 2>/dev/null || true)"
if echo "$output" | grep -q "STUB_PGDATABASE=sports_fanatic"; then
  pass
else
  fail "PGDATABASE default not sports_fanatic; output: $output"
fi

# Now test db_restore.sh defaults using the same pg_restore stub approach.
# db_restore.sh reads defaults but calls pg_restore, not pg_dump.
# We inject a stub pg_restore that prints env vars and exits non-zero so the
# script stops.  We also need the file to pass validation (PGDMP header).
VALID_DUMP="$(mktemp /tmp/sf_test_valid_XXXXXX.dump)"
printf 'PGDMP\x00\x00\x00' > "$VALID_DUMP"

cat > "$TMPBINDIR/pg_restore" <<'STUB'
#!/usr/bin/env bash
echo "STUB_PGPORT=${PGPORT:-UNSET}"
echo "STUB_PGDATABASE=${PGDATABASE:-UNSET}"
exit 99
STUB
chmod +x "$TMPBINDIR/pg_restore"

test_case "db_restore.sh defaults PGPORT to 5432"
output="$(PATH="$TMPBINDIR:$PATH" \
  PGPORT="" PGDATABASE="" PGHOST="localhost" \
  bash "$RESTORE_SCRIPT" --force "$VALID_DUMP" 2>/dev/null || true)"
if echo "$output" | grep -q "STUB_PGPORT=5432"; then
  pass
else
  fail "PGPORT default not 5432; output: $output"
fi

test_case "db_restore.sh defaults PGDATABASE to sports_fanatic"
output="$(PATH="$TMPBINDIR:$PATH" \
  PGPORT="" PGDATABASE="" PGHOST="localhost" \
  bash "$RESTORE_SCRIPT" --force "$VALID_DUMP" 2>/dev/null || true)"
if echo "$output" | grep -q "STUB_PGDATABASE=sports_fanatic"; then
  pass
else
  fail "PGDATABASE default not sports_fanatic; output: $output"
fi

rm -f "$VALID_DUMP"
rm -rf "$TMPBINDIR"

# ---------------------------------------------------------------------------
# Section: db_restore.sh --jobs validation
# ---------------------------------------------------------------------------
section "db_restore.sh --jobs argument validation"

test_case "db_restore.sh --jobs without value exits non-zero"
bash "$RESTORE_SCRIPT" /tmp/dummy.dump --jobs >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

test_case "db_restore.sh --jobs with non-integer exits non-zero"
bash "$RESTORE_SCRIPT" /tmp/dummy.dump --jobs notanumber >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

# ---------------------------------------------------------------------------
# Section: db_backup.sh --schemas validation
# ---------------------------------------------------------------------------
section "db_backup.sh --schemas argument validation"

test_case "db_backup.sh --schemas without value exits non-zero"
bash "$BACKUP_SCRIPT" --schemas >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

# ---------------------------------------------------------------------------
# Section: db_s3_sync.sh upload missing file argument
# ---------------------------------------------------------------------------
section "db_s3_sync.sh subcommand argument validation"

test_case "db_s3_sync.sh upload with no file arg exits non-zero (missing S3_BUCKET first)"
# Without S3_BUCKET the script fails earlier at validate_deps; that's still non-zero.
S3_BUCKET="" bash "$S3_SYNC_SCRIPT" upload >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

test_case "db_s3_sync.sh download with no key arg exits non-zero"
S3_BUCKET="test-bucket" \
  PATH="/usr/bin:/bin" \
  bash "$S3_SYNC_SCRIPT" download >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

# ---------------------------------------------------------------------------
# Section: S3_BUCKET required for S3 commands
# ---------------------------------------------------------------------------
section "db_s3_sync.sh requires S3_BUCKET"

# Provide a stub aws so validate_deps reaches the S3_BUCKET check.
TMPAWS="$(mktemp -d /tmp/sf_test_awsbindir_XXXXXX)"
cat > "$TMPAWS/aws" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$TMPAWS/aws"

test_case "db_s3_sync.sh upload fails when S3_BUCKET unset"
PATH="$TMPAWS:$PATH" S3_BUCKET="" bash "$S3_SYNC_SCRIPT" upload /tmp/anyfile >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

test_case "db_s3_sync.sh upload emits S3_BUCKET error when unset"
output="$(PATH="$TMPAWS:$PATH" S3_BUCKET="" bash "$S3_SYNC_SCRIPT" upload /tmp/anyfile 2>&1 || true)"
if echo "$output" | grep -qi "S3_BUCKET\|not set\|error"; then pass; else fail "no S3_BUCKET error in output"; fi

test_case "db_s3_sync.sh list fails when S3_BUCKET unset"
PATH="$TMPAWS:$PATH" S3_BUCKET="" bash "$S3_SYNC_SCRIPT" list >/dev/null 2>&1
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then pass; else fail "expected non-zero exit"; fi

rm -rf "$TMPAWS"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "=================================================="
echo "Results: $TESTS_PASSED passed / $TESTS_FAILED failed / $TESTS_RUN total"
echo "=================================================="

if [[ "$TESTS_FAILED" -gt 0 ]]; then
  exit 1
fi

exit 0
