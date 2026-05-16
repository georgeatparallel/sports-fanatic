# Developer's Guide

## Getting Started

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Elixir | 1.17+ | Application runtime |
| Erlang/OTP | 27+ | VM |
| Docker & Compose | 24+ | Infrastructure services |
| Python | 3.11+ | Only if running python_bridge outside Docker |
| Node.js | 18+ | Asset pipeline (esbuild, Tailwind) |

### Setup

```bash
git clone git@github.com:joestein/sports-fanatic.git
cd sports-fanatic

# Configure environment
cp .env.example .env
# Fill in: SECRET_KEY_BASE, FANTASY_NERDS_API_KEY, ANTHROPIC_API_KEY, EXA_API_KEY,
#          STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, JOSHUA_USERNAME, JOSHUA_PASSWORD

# Start infrastructure
docker compose up -d

# Setup database
docker compose exec web mix ecto.setup

# Open http://localhost:4000
```

### Local Development (without Docker for Phoenix)

```bash
mix deps.get
mix assets.setup

# Start PostgreSQL and Valkey locally
# Adjust DATABASE_URL and VALKEY_URL in .env

# Start Python bridge in Docker
docker compose up -d python-bridge db cache

# Start Phoenix with live reload
mix phx.server
# or interactive: iex -S mix phx.server
```

## Key Commands

```bash
# Tests
mix test.unit           # Pure unit tests (no DB, ~400 tests)
mix test                # All tests (requires PostgreSQL)

# Database
mix ecto.migrate        # Apply pending migrations
mix ecto.reset          # Drop + recreate + migrate + seed
mix ecto.rollback       # Rollback last migration

# Assets
mix assets.build        # Compile Tailwind + esbuild
mix assets.deploy       # Production build (minified)

# Code quality
mix format              # Format all Elixir files
mix format --check-formatted  # CI check

# Compile with strict warnings
mix compile --warnings-as-errors
```

## Project Structure

```
lib/sports_fanatic/          # Business logic (contexts, schemas, workers)
lib/sports_fanatic_web/      # Web layer (controllers, live views, plugs, components)
python_bridge/src/           # Python FastAPI service
priv/repo/migrations/        # Database migrations
test/                        # ExUnit tests
config/                      # App configuration (config.exs, runtime.exs, test.exs)
infra/                       # Terraform, Kubernetes, ArgoCD
scripts/                     # Deployment and database scripts
assets/                      # JS, CSS (Tailwind)
c4/                          # C4 architecture model
docs/                        # Documentation
```

## Common Development Tasks

### Add a New SEO Page

1. Add route in `router.ex` under the `:browser` scope
2. Create controller in `lib/sports_fanatic_web/controllers/`
3. Create HTML module + HEEx template
4. Set SEO assigns: `page_title`, `meta_description`, `canonical_url`, `json_ld`
5. Add Valkey cache read/write in the controller action
6. Update `GenerateSitemapWorker` to include new URLs

### Add a New Oban Worker

1. Create `lib/sports_fanatic/workers/my_worker.ex`:
   ```elixir
   defmodule SportsFanatic.Workers.MyWorker do
     use Oban.Worker, queue: :default, max_attempts: 3

     @impl Oban.Worker
     def perform(%Oban.Job{args: args}) do
       # Work here
       :ok
     end
   end
   ```
2. Add to crontab in `config/config.exs` if scheduled
3. Add to test.unit alias in `mix.exs`
4. Test: `%{} |> SportsFanatic.Workers.MyWorker.new() |> Oban.insert()`

### Add a Chatbot Action (Tool)

1. Create `lib/sports_fanatic/agents/actions/my_action.ex`:
   ```elixir
   defmodule SportsFanatic.Agents.Actions.MyAction do
     use SportsFanatic.Agents.Action,
       name: "my_action",
       description: "Does something useful"

     @impl true
     def run(params, _context) do
       # Tool implementation
       {:ok, %{result: "..."}}
     end
   end
   ```
2. Call it from `NewsAgent.execute/4`
3. Add progress broadcasting for user visibility

### Test Stripe Webhooks Locally

```bash
docker compose --profile dev up stripe-cli
# Stripe CLI forwards events to http://web:4000/webhooks/stripe
```

### Enable/Disable Features

```bash
# Via Joshua admin panel at /admin → Feature Flags tab
# Or via IEx:
docker compose exec web bin/sports_fanatic rpc '
  {:ok, _} = Application.ensure_all_started(:ssl)
  {:ok, _} = Application.ensure_all_started(:postgrex)
  {:ok, _} = Application.ensure_all_started(:ecto_sql)
  {:ok, _} = SportsFanatic.Repo.start_link([])
  SportsFanatic.FeatureFlags.enable("news_chatbot_enabled")
'
```

### Hot-Reload Code in Docker (No Rebuild)

For quick iteration without rebuilding the container:

```bash
# Copy changed files into container
docker cp lib/sports_fanatic/agents/news_agent.ex sports-fanatic-web-1:/tmp/news_agent.ex

# Hot-reload the module in the running BEAM VM
docker compose exec web bin/sports_fanatic rpc '
  [{mod, _}] = Code.compile_file("/tmp/news_agent.ex")
  IO.puts("Reloaded: #{mod}")
'
```

For LiveView templates (HEEx is compiled into the module):
```bash
docker cp lib/sports_fanatic_web/live/news_live.ex sports-fanatic-web-1:/tmp/live/news_live.ex
docker cp lib/sports_fanatic_web/live/news_live.html.heex sports-fanatic-web-1:/tmp/live/news_live.html.heex
docker compose exec web bin/sports_fanatic rpc '
  [{mod, _}] = Code.compile_file("/tmp/live/news_live.ex")
  IO.puts("Reloaded: #{mod}")
'
```

### Database Backup & Restore

```bash
./scripts/db_backup.sh                    # Local backup
S3_BUCKET=my-bucket ./scripts/db_backup.sh  # Backup + S3 upload
./scripts/db_restore.sh backups/file.dump --force  # Restore
```

## Testing Strategy

| Type | Command | Count | DB Required |
|------|---------|-------|-------------|
| Unit tests | `mix test.unit` | ~400 | No |
| Integration | `mix test` | ~500 total | Yes |

Unit tests cover: schema changesets, slug generation, cache key builders, circuit breaker state machine, Oban job structure, Action behaviour compliance, Exa URL validation.

No Mox dependency. Workers are tested by verifying Oban job structure, not external API calls.

## Conventions

- **Contexts**: Business logic lives in context modules (`Accounts`, `News`, `Billing`, `ChatBot`, `Agents`)
- **Schemas**: Ecto schemas in subdirectories (`accounts/user.ex`, `content/news_item.ex`)
- **Slugs**: `Slug.slugify/1` for URL-safe names (lowercase, hyphenated)
- **UUIDs**: All primary keys use `gen_random_uuid()`
- **Caching**: All cache operations via `SportsFanatic.Cache` module
- **HTML safety**: Never use `raw/1` on user or AI content. Use `HtmlSanitizeEx.strip_tags/1` for chat output.
- **Feature flags**: Gate new features behind `FeatureFlags.enabled?/1`
