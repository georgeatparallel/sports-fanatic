# Sports Fanatic

MLB SEO and subscription platform with an AI-powered agentic chatbot. Server-rendered public pages for every player, team, lineup, and news item. Premium AI-generated scouting reports and Game Day Magazines. A conversational research agent that searches local news and discovers new articles via Exa.ai in real-time.

## Quick Start

```bash
cp .env.example .env    # Fill in API keys
docker compose up -d
docker compose exec web mix ecto.setup
# Open http://localhost:4000
```

## What It Does

**Public SEO Pages** — Crawlable HTML pages for 750+ MLB players, 30 teams, daily lineups, and a real-time news feed. JSON-LD structured data, Open Graph tags, Valkey-cached. Lighthouse SEO target: 95+.

**Agentic Chatbot** — An LLM-powered research assistant on the news feed. Users ask about any player, team, or topic. The agent searches the local database, discovers external articles via Exa.ai, classifies and stores them, and streams progress in a chat thread. Understands follow-up questions ("when is he expected back") with context from prior messages.

**Premium Content** — AI-generated scouting reports and Game Day Magazines gated behind Stripe subscriptions ($9.99/mo or $79.99/yr with 7-day trial). Phoenix LiveView for real-time in-game updates.

**News Pipeline** — Automated ingestion from FantasyNerds every minute. Each article is classified by Claude Haiku (category, sentiment, injury details, domain tags), entity-matched to players/teams, and stored with full-text search indexing.

## Architecture

```
Browser → Phoenix Router
  ├── /mlb/* → SEO Controllers → Valkey → PostgreSQL → Cached HTML
  ├── /mlb/news → NewsLive (LiveView + Agentic Chatbot)
  │     ├── ChatBot → AgentSupervisor → NewsAgent (ReAct tool loop)
  │     │     ├── SearchLocalNews (PostgreSQL tsvector full-text)
  │     │     ├── SearchExa (Exa.ai → classify → store → broadcast)
  │     │     └── Context Resolution (Claude Haiku, topic detection)
  │     └── PubSub live updates (news:feed, chat:user_id)
  ├── /premium/* → LiveView (subscription-gated)
  └── /webhooks/stripe → Stripe webhook handler

Background (Oban, 16 workers):
  FetchNews (1 min) → Python Bridge /news/analyze → PostgreSQL → Valkey → PubSub
  FetchSchedule, FetchLineups, GenerateScouting, GenerateGameDay, WarmCache, ...

Python Bridge (FastAPI, internal):
  /predict/* (GradientBoosting), /news/analyze (Claude classification),
  /scouting/* (Exa + Claude), /chat/resolve-context (conversation context)
```

See [docs/architecture.md](docs/architecture.md) for the full architecture guide and [c4/](c4/) for C4 model diagrams.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Backend | Elixir 1.17, Phoenix 1.7, OTP 27 |
| Real-time | Phoenix LiveView 0.19 |
| Database | PostgreSQL 16 (6 schemas, full-text search) |
| Cache | Valkey 8 (Redis-compatible) |
| Background Jobs | Oban (PostgreSQL-backed, 16 workers) |
| ML/AI Service | Python 3.11, FastAPI, scikit-learn, NumPy |
| AI | Anthropic Claude (Haiku + Sonnet) |
| Search | Exa.ai (neural web search) |
| Payments | Stripe (Checkout Sessions) |
| Infrastructure | AWS (EKS, RDS, ElastiCache, S3, Route 53) |
| IaC | Terraform, Kubernetes, ArgoCD |

## Project Structure

```
lib/sports_fanatic/              # Business logic
  accounts/, billing/            # Auth + Stripe
  agents/                        # Agentic chatbot (NewsAgent, Actions, AgentSupervisor)
  chat_bot/                      # Chat sessions, messages, query clusters
  content/, mlb/, news/          # Domain schemas and contexts
  external_apis/                 # Exa.ai client
  python_bridge.ex               # HTTP client with circuit breaker
  workers/                       # 16 Oban workers

lib/sports_fanatic_web/          # Web layer
  controllers/                   # 8 SEO controllers
  live/                          # 9 LiveViews (NewsLive, AdminLive, etc.)
  plugs/                         # Auth, subscription, admin gates
  components/                    # SEO components (JSON-LD, breadcrumbs)

python_bridge/src/               # FastAPI microservice
  api/                           # predict, scouting, gameday, news, agents, chat
  news/                          # Claude classification engine
  simulation/                    # Monte Carlo engine

infra/
  terraform/                     # AWS infrastructure (VPC, EKS, RDS, S3, etc.)
  k8s/                           # Kubernetes manifests (base + overlays)
  argocd/                        # GitOps configuration

c4/                              # C4 architecture model (context, containers, components)
docs/                            # Developer guide, architecture, security, devops
scripts/                         # Deployment, backup/restore, bootstrap
```

## Environment Variables

Copy `.env.example` and set:

| Variable | Description |
|----------|-------------|
| `SECRET_KEY_BASE` | Phoenix secret — `mix phx.gen.secret` |
| `DATABASE_URL` | PostgreSQL connection string |
| `VALKEY_URL` | Valkey/Redis connection URL |
| `FANTASY_NERDS_API_KEY` | FantasyNerds API key |
| `ANTHROPIC_API_KEY` | Anthropic Claude API key |
| `EXA_API_KEY` | Exa.ai search API key |
| `STRIPE_SECRET_KEY` | Stripe secret key |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret |
| `JOSHUA_USERNAME` / `JOSHUA_PASSWORD` | Admin panel credentials |

See `.env.example` for the full list including AWS and S3 configuration.

## Development

```bash
mix deps.get              # Install dependencies
mix phx.server            # Start dev server (http://localhost:4000)
iex -S mix phx.server     # Interactive shell

mix test.unit             # ~400 unit tests (no DB required)
mix test                  # All tests (requires PostgreSQL)

mix format                # Format code
mix compile --warnings-as-errors  # Strict compilation
```

## Deployment

Production runs on AWS EKS via ArgoCD GitOps:

```bash
# Infrastructure
./scripts/deploy-infra.sh prod apply

# Bootstrap cluster (ArgoCD, ESO, ALB Controller)
./scripts/bootstrap-cluster.sh

# Build and deploy
./scripts/deploy.sh prod
```

See [docs/devops.md](docs/devops.md) for the full deployment guide including Terraform, Kubernetes, database operations, and cost estimates (~$230/mo for ~100 users).

## Documentation

| Document | Description |
|----------|-------------|
| [CLAUDE.md](CLAUDE.md) | Detailed project reference (routes, schemas, workers, caching, conventions) |
| [docs/architecture.md](docs/architecture.md) | System architecture, request flows, database design |
| [docs/developers-guide.md](docs/developers-guide.md) | Setup, commands, common tasks, testing, conventions |
| [docs/security.md](docs/security.md) | Auth, input validation, rate limiting, known issues |
| [docs/devops.md](docs/devops.md) | Terraform, Kubernetes, ArgoCD, deployment, monitoring |
| [c4/context.md](c4/context.md) | C4 Level 1 — System context diagram |
| [c4/containers.md](c4/containers.md) | C4 Level 2 — Container diagram |
| [c4/components.md](c4/components.md) | C4 Level 3 — Component diagram (Phoenix app) |
| [infra/README.md](infra/README.md) | Infrastructure deployment guide |

## License

Private. All rights reserved.
