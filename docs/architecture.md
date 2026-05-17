# Architecture Guide

## System Overview

Sports Fanatic is a two-layer MLB platform:

1. **Public SEO layer** — Server-rendered HTML pages for every MLB player, team, lineup, and news item. Cached in Valkey. Targeted at search engine crawlers and organic traffic.
2. **Premium subscription layer** — AI-generated scouting reports and Game Day Magazines behind Stripe subscriptions. Phoenix LiveView for real-time updates.
3. **Agentic chatbot layer** — LLM-powered conversational interface that searches local news and discovers external articles via Exa.ai.

## Technology Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Language | Elixir | 1.17 |
| Runtime | Erlang/OTP | 27 |
| Web Framework | Phoenix | 1.7.22 |
| Real-time | Phoenix LiveView | 0.19 |
| Database | PostgreSQL | 16 |
| Cache | Valkey (Redis-compatible) | 8 |
| Background Jobs | Oban | 2.x |
| ML/AI Service | Python FastAPI | 3.11 |
| ML Models | scikit-learn (GradientBoosting) | 1.5 |
| AI | Anthropic Claude (Haiku + Sonnet) | Latest |
| Search | Exa.ai | Neural search |
| Payments | Stripe | Checkout Sessions |
| Infrastructure | AWS (EKS, RDS, ElastiCache, S3) | - |
| IaC | Terraform | 1.5+ |
| GitOps | ArgoCD | 2.x |
| Container Runtime | Kubernetes | 1.29+ |

## Request Flow

### Public SEO Pages
```
Browser → Route 53 → ALB → EKS → Phoenix Router
  → :browser plug pipeline (CSRF, session, FetchCurrentUser)
  → SEO Controller (PlayerController, TeamController, etc.)
  → Valkey cache check
    → (hit) return cached HTML
    → (miss) PostgreSQL query → render HEEx → cache → return HTML
```

Every public page includes:
- `<title>` and `<meta description>` for SEO
- JSON-LD structured data (BreadcrumbList, SportsTeam, Person, CollectionPage)
- Open Graph and Twitter Card meta tags
- Self-referencing canonical URL

### Agentic Chatbot
```
User types query → LiveView WebSocket → handle_event("submit_chat")
  → Build conversation context (last 10 messages)
  → AgentSupervisor.start_agent (DynamicSupervisor + Registry)
  → Task process spawned
    → [Context resolution] POST /chat/resolve-context (Python Bridge → Claude Haiku)
      → Detect continuation vs new topic, resolve pronouns, generate search prompts
    → [Local search] PostgreSQL full-text search (tsvector/websearch_to_tsquery)
    → [External research] Exa.ai search with LLM-generated prompts (up to 25 results)
    → [Classify new articles] POST /news/analyze (Python Bridge → Claude Haiku)
    → [Entity resolution] EntityMatcher (jaro_distance ≥ 0.85)
    → [Store] INSERT news_items, cache invalidate, PubSub broadcast
  → PubSub progress messages → LiveView → WebSocket push → browser render
  → PubSub completion → LiveView loads articles → render in chat thread
```

### Premium Content
```
Browser → Phoenix Router
  → :browser pipeline → :require_auth → :require_subscription
  → SubscriptionGate checks Accounts.has_active_subscription?/1
    → (no subscription) redirect to /subscribe
    → (active) mount LiveView → WebSocket connection
```

### Stripe Webhooks
```
Stripe → POST /webhooks/stripe
  → :stripe_webhook pipeline (CacheRawBody, VerifyStripeWebhook)
  → StripeWebhookController.handle/2
  → Billing context handles event type:
    checkout.session.completed → create subscription
    invoice.paid → extend subscription
    customer.subscription.deleted → downgrade to free
```

## Database Architecture

Six PostgreSQL schemas isolate concerns:

| Schema | Purpose | Key Tables |
|--------|---------|------------|
| `public` | Core MLB entities | sports, teams, players, venues |
| `mlb` | Game data and predictions | games, scheduled_games, lineups, player_boxscores, picks, hr_picks |
| `content` | AI-generated content | scouting_reports, game_day_magazines, news_items, sitemaps |
| `accounts` | Auth, billing, and agents | users, subscriptions, sessions, chat_sessions, chat_messages, news_agent_settings, query_clusters |
| `system` | Operations | pipeline_runs, pipeline_steps, cache_invalidations, feature_flags |
| `scouting` | Legacy scouting data | (retained from sports-fan-agent) |

### Full-Text Search

`content.news_items` has a `search_vector` tsvector generated column:
```sql
search_vector tsvector GENERATED ALWAYS AS (
  setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
  setweight(to_tsvector('english', coalesce(ai_summary, '')), 'B') ||
  setweight(to_tsvector('english', coalesce(body, '')), 'C')
) STORED
```
Indexed with GIN for fast full-text queries via `websearch_to_tsquery`.

## Caching Strategy

Valkey (Redis-compatible) provides multi-tier caching:

| Tier | TTL | Pattern | Invalidation |
|------|-----|---------|--------------|
| Feed cache | 60s | `sf:data:news:feed:{date}` | FetchNewsWorker on new articles |
| Page cache | 2-15 min | `sf:page:{type}:{params}` | Content generation workers |
| Lineup cache | 2 min (today), 24h (past) | `sf:page:lineup:{date}` | FetchLineupsWorker |
| Sitemap cache | 6h | `sf:sitemap:*` | GenerateSitemapWorker |
| Prediction cache | 5 min | `sf:data:predictions:*` | GeneratePredictionsWorker |

Cache reads use a read-through pattern: check Valkey first, fall back to PostgreSQL, write result to Valkey.

## Background Job Architecture (Oban)

16 Oban workers across 4 queues:

| Queue | Concurrency | Workers |
|-------|-------------|---------|
| `data_fetch` | 5 | FetchSchedule, FetchLineups, FetchNews |
| `content_generation` | 3 | GenerateScouting, GenerateGameDay, GeneratePredictions, GeneratePlayerSeo, RunNewsAgents, ScheduledExaSearch, ParseSetting |
| `cache` | 2 | WarmCache |
| `system` | 1 | GenerateSitemap, Cleanup, ConsolidateQueries, ReclassifyNews |

All workers use `max_attempts: 3` with exponential backoff. Cron schedules are defined in `config/config.exs`.

## Agent Architecture

The agentic chatbot uses a custom Action behaviour (Jido-compatible API but without the Jido dependency, which requires Elixir 1.18+):

```
User Query
  ↓
AgentSupervisor (DynamicSupervisor)
  ↓ spawns Task
NewsAgent (ReAct orchestrator)
  ↓
[Step 0] Context Resolution (if conversation history exists)
  → POST /chat/resolve-context → Claude Haiku
  → Returns: is_continuation, resolved_query, search_prompts
  ↓
[Step 1] SearchLocalNews (tsvector full-text search)
  → PostgreSQL query on news_items
  ↓
[Step 2] Deep Research (if <3 local results)
  → SearchExa (Exa.ai, up to 25 results, 30 days)
  → ClassifyArticle for each new URL
    → POST /news/analyze → Claude Haiku
    → EntityMatcher → player_ids, team_ids
    → INSERT news_items (source: "exa")
    → Cache invalidate + PubSub broadcast
  ↓
[Step 3] Build Summary
  → Return article IDs + natural language summary
```

Progress updates broadcast via PubSub to `chat:{user_id}` at every step.

## PubSub Topics

| Topic | Publisher | Subscriber | Payload |
|-------|-----------|------------|---------|
| `news:feed:{date}` | FetchNewsWorker | NewsLive | `{:news_updated, date}` |
| `news:feed` | FetchNewsWorker | NewsLive | `{:news_updated, date}` |
| `chat:{user_id}` | NewsAgent (via AgentSupervisor) | NewsLive | `{:agent_progress, %{message}}`, `{:agent_complete, %{summary, ids}}`, `{:agent_error, %{error}}` |
| `agent:settings:{user_id}` | ParseSettingWorker | NewsLive (legacy) | `{:setting_updated, setting}` |

## Circuit Breaker

The Python Bridge uses a circuit breaker pattern (`SportsFanatic.PythonBridge.CircuitBreaker`):

- **Closed**: Normal operation, requests pass through
- **Open**: After 3 consecutive failures, all requests fail fast for 5 minutes
- **Half-open**: After cooldown, one request allowed through to test recovery
- Health check (`/health`) pings every 30 seconds via `PythonBridge.HealthCheck`
