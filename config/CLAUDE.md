Parent: `../CLAUDE.md`

# CLAUDE.md — Configuration

> See the Documentation Placement Rule in `../CLAUDE.md` before adding
> content here.

---

```
config/
  config.exs    compile-time defaults; imports the env-specific file last
  dev.exs       development overrides
  prod.exs      production overrides
  test.exs      test overrides (incl. Oban testing :disabled)
  runtime.exs   runtime — reads env vars; the only file mutating config in prod
```

## When to put config where

- **Library defaults** (e.g. Oban queues, esbuild version, JSON library) →
  `config.exs`.
- **Env-specific compile-time** (e.g. dev logging) → `dev.exs` / `prod.exs` /
  `test.exs`.
- **Anything read from env vars** → `runtime.exs`. Always provide a sensible
  default (e.g. `System.get_env("VAR", "default")`).

## Oban configuration

`config :sports_fanatic, Oban, ...` in `config.exs`:

```elixir
queues: [data_fetch: 5, content_generation: 3, cache: 2,
         system: 1, default: 10, x_agent: 2]
```

`plugins: [Pruner, Cron]`. Cron entries are UTC — see
`lib/sports_fanatic/workers/CLAUDE.md` for the full schedule table including
the EDT/EST drift caveat (X-AGENT-001).

In `test.exs`, Oban is `testing: :disabled` because Oban 2.22's
`verify_migrated!` requires a live DB even for unit tests.

## Feature flag seeding

New flags are seeded via a migration that inserts into `system.feature_flags`
with `ON CONFLICT (key) DO NOTHING`. Example: `20260518100007_seed_x_agent_feature_flags.exs`.

`SportsFanatic.FeatureFlags.create/1` is the runtime path for ad-hoc creation.

## Env vars — runtime.exs map

| Var | Used by | Required |
|-----|---------|----------|
| `DATABASE_URL` | `Repo` (prod only) | prod |
| `SECRET_KEY_BASE` | `Endpoint` (prod) | prod |
| `PHX_HOST`, `PORT` | `Endpoint` | prod |
| `JOSHUA_USERNAME`, `JOSHUA_PASSWORD` | `JoshuaAuth` | for admin gate |
| `VALKEY_URL` | `Redix` | yes (default redis://localhost:6379) |
| `PYTHON_BRIDGE_URL` | `PythonBridge` | yes (default localhost:8000) |
| `FANTASY_NERDS_API_KEY` | `ExternalApis.FantasyNerds` | yes |
| `EXA_API_KEY` | `ExternalApis.Exa` | when chatbot or X agent enabled |
| `ANTHROPIC_API_KEY` | Python Bridge (and Elixir-side helpers) | yes |
| `NEWS_S3_BUCKET`, `NEWS_S3_ENABLED`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `Storage` | when S3 used |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY` | Billing | yes |
| `X_CLIENT_ID`, `X_CLIENT_SECRET`, `X_REDIRECT_URI`, `X_TOKEN_ENCRYPTION_KEY`, `X_DAILY_CAP_MILLS`, `X_ACCOUNT_HANDLE` | X agent | when `x_agent_enabled=true` |

## X agent configuration block

In `runtime.exs`:

```elixir
config :sports_fanatic, :x_agent,
  client_id: System.get_env("X_CLIENT_ID"),
  client_secret: System.get_env("X_CLIENT_SECRET"),
  redirect_uri:
    System.get_env("X_REDIRECT_URI",
                   "https://sportsfanatic.com/admin/x/oauth/callback"),
  token_encryption_key: System.get_env("X_TOKEN_ENCRYPTION_KEY"),
  daily_cap_mills:
    System.get_env("X_DAILY_CAP_MILLS", "5000") |> String.to_integer(),
  account_handle: System.get_env("X_ACCOUNT_HANDLE", "")
```
