# C4 Model — Level 2: Container Diagram

```mermaid
C4Container
    title Container Diagram — Sports Fanatic

    Person(user, "User", "Visitor, subscriber, or admin")

    System_Boundary(sf, "Sports Fanatic Platform") {
        Container(phoenix, "Phoenix Application", "Elixir 1.17, Phoenix 1.7, OTP 27", "Serves HTML pages, LiveView WebSocket connections, processes webhooks, runs background jobs via Oban")
        Container(python, "Python Bridge", "Python 3.11, FastAPI", "ML predictions (GradientBoosting), Monte Carlo simulation, Claude AI content generation, Exa search, news classification")
        Container(db, "PostgreSQL", "PostgreSQL 16", "6 schemas: public, mlb, content, accounts, system, scouting. Stores all application data.")
        Container(cache, "Valkey", "Valkey 8 (Redis-compatible)", "Page-level HTML caching (2-24 min TTL), news feed caching (60s), prediction caching (5 min)")
        Container(s3, "S3 Bucket", "AWS S3", "Raw news article JSON storage, date-partitioned (news/raw/YYYY/MM/DD/)")
    }

    System_Ext(stripe, "Stripe")
    System_Ext(claude, "Claude API")
    System_Ext(exa, "Exa.ai")
    System_Ext(fantasynerds, "FantasyNerds")

    Rel(user, phoenix, "HTTPS / WebSocket (LiveView)")
    Rel(phoenix, python, "HTTP (internal network, port 8000)", "Circuit breaker: 3 failures → 5 min cooldown")
    Rel(phoenix, db, "Ecto / PostgreSQL protocol", "Connection pool via DBConnection")
    Rel(phoenix, cache, "Redix client", "TCP port 6379")
    Rel(phoenix, s3, "ExAws S3", "HTTPS")
    Rel(phoenix, exa, "Req HTTP client", "Direct for chatbot, via Python Bridge for scouting")
    Rel(phoenix, stripe, "Stripity Stripe", "HTTPS")
    Rel(python, claude, "Anthropic SDK", "HTTPS")
    Rel(python, exa, "Exa SDK", "HTTPS")
    Rel(python, fantasynerds, "HTTP", "HTTPS")
    Rel(stripe, phoenix, "Webhooks", "POST /webhooks/stripe")
```

## Container Details

### Phoenix Application (Elixir)
- **Runtime**: Erlang/OTP 27 release, Elixir 1.17
- **Web framework**: Phoenix 1.7.22, LiveView 0.19
- **Background jobs**: Oban 2.x (PostgreSQL-backed, 16 workers)
- **Key responsibilities**: HTML rendering, WebSocket connections, authentication, subscription gating, Oban job scheduling, PubSub broadcasting, agentic chatbot orchestration
- **Ports**: 4000 (HTTP)

### Python Bridge (FastAPI)
- **Runtime**: Python 3.11+, Uvicorn
- **ML models**: scikit-learn GradientBoosting (hit/HR prediction), NumPy Monte Carlo (10k trials)
- **AI integration**: Anthropic SDK (Claude Haiku for classification, Sonnet for reports), Exa SDK (scouting search)
- **Endpoints**: `/predict/*`, `/scouting/*`, `/gameday/*`, `/news/*`, `/agents/*`, `/chat/*`
- **Ports**: 8000 (internal only)

### PostgreSQL
- **Version**: 16-alpine
- **Schemas**: `public` (entities), `mlb` (game data), `content` (AI content + news), `accounts` (auth + chat + agents), `system` (operations), `scouting`
- **Key features**: Full-text search (tsvector on news_items), UUID primary keys, JSONB for flexible schemas

### Valkey
- **Version**: 8-alpine (Redis-compatible)
- **Pattern**: Read-through cache with proactive invalidation
- **TTL strategy**: 60s for feeds, 2-15 min for pages, 6h for sitemaps

### S3
- **Usage**: Raw news article JSON archival
- **Path pattern**: `news/raw/{YYYY}/{MM}/{DD}/{external_id}.json`
- **Access**: Application-layer only (bucket not public)
