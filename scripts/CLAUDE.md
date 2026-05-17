Parent: `../CLAUDE.md`

# CLAUDE.md — Scripts

> See the Documentation Placement Rule in `../CLAUDE.md` before adding
> content here.

---

Shell scripts for database backup/restore and deployment. Local backups land
in `backups/` (gitignored). Run any script with `-h` for full flag reference.

## Inventory

| Script | Purpose |
|--------|---------|
| `db_backup.sh` | Run `pg_dump` + optional S3 upload |
| `db_restore.sh` | Restore from local file or S3 URI |
| `db_s3_sync.sh` | `list` / `upload` / `download` against S3 |
| `bootstrap-cluster.sh` | First-boot ECS/Compose cluster setup |
| `deploy.sh` | Application deploy |
| `deploy-infra.sh` | Infra deploy |
| `make-ecr.sh` | Create ECR repo |

## Database backup quick reference

```bash
# Local backup only
./scripts/db_backup.sh

# Backup and upload to S3
S3_BUCKET=my-bucket ./scripts/db_backup.sh

# Backup specific schemas only
./scripts/db_backup.sh --schemas public,mlb,content

# Backup without S3 upload even when S3_BUCKET is set
./scripts/db_backup.sh --no-s3

# Restore from local file (prompts for confirmation)
./scripts/db_restore.sh backups/sports_fanatic_20260426_090000.dump

# Restore from local file — skip prompt
./scripts/db_restore.sh backups/sports_fanatic_20260426_090000.dump --force

# Restore from S3 URI with clean DB
./scripts/db_restore.sh s3://my-bucket/.../snapshot.dump --force --drop

# Parallel restore (faster for large databases)
./scripts/db_restore.sh backups/snapshot.dump --force --jobs 4

# List backups in S3
S3_BUCKET=my-bucket ./scripts/db_s3_sync.sh list

# Mix task wrappers
mix db.backup
mix db.restore backups/snapshot.dump
```

## Database env vars

| Var | Description | Default | Required |
|-----|-------------|---------|----------|
| `PGHOST` | DB host (auto-detects Docker `db` / `localhost`) | auto | No |
| `PGPORT` | DB port | `5432` | No |
| `PGUSER` | DB user | `postgres` | No |
| `PGPASSWORD` | DB password | `postgres` | No |
| `PGDATABASE` | DB name | `sports_fanatic` | No |
| `BACKUP_DIR` | Local backup directory | `./backups` | No |
| `BACKUP_RETENTION_DAYS` | Days to keep local backups | `30` | No |
| `S3_BUCKET` | S3 bucket | — | for S3 ops |
| `S3_PREFIX` | S3 key prefix | `backups/sports-fanatic` | No |
| `AWS_PROFILE` | AWS CLI named profile | — | No |
| `AWS_REGION` | AWS region | `us-east-1` | No |

Variables can also be set in `.env` at the project root — the scripts source
it automatically if present.

## Docker usage

```bash
# From host (Postgres port must be exposed — default docker-compose exposes 5432)
PGHOST=localhost ./scripts/db_backup.sh

# Inside the web container (connects to 'db' on internal network)
docker compose exec web ./scripts/db_backup.sh

# S3 credentials passed through
docker compose exec -e S3_BUCKET=my-bucket -e AWS_REGION=us-east-1 web \
  ./scripts/db_backup.sh
```

## Stripe CLI

Test Stripe webhooks locally:

```bash
docker compose --profile dev up stripe-cli
# stripe-cli forwards events from Stripe to http://web:4000/webhooks/stripe
```
