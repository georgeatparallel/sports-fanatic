# C4 Model — Level 1: System Context

Sports Fanatic is an MLB platform serving two user populations through a single system.

```mermaid
C4Context
    title System Context — Sports Fanatic

    Person(visitor, "Visitor", "Anonymous user browsing MLB content via search engines or direct links")
    Person(subscriber, "Subscriber", "Paying user with access to premium scouting reports and Game Day Magazines")
    Person(admin, "Admin", "Platform operator managing workers, feature flags, and agent queries via Joshua")

    System(sf, "Sports Fanatic", "MLB SEO and subscription platform with AI-generated content and agentic chatbot")

    System_Ext(fantasynerds, "FantasyNerds API", "MLB lineups, player news, injury updates")
    System_Ext(mlbstats, "MLB Stats API", "Game schedules, box scores, rosters")
    System_Ext(stripe, "Stripe", "Payment processing, subscription management")
    System_Ext(claude, "Anthropic Claude API", "AI content generation, news classification, chatbot reasoning")
    System_Ext(exa, "Exa.ai", "Neural web search for article discovery")
    System_Ext(aws, "AWS", "EKS hosting, RDS database, S3 storage, ElastiCache, Route 53 DNS")

    Rel(visitor, sf, "Browses MLB pages, uses chatbot", "HTTPS")
    Rel(subscriber, sf, "Accesses premium content", "HTTPS/WebSocket")
    Rel(admin, sf, "Manages via Joshua admin panel", "HTTPS")

    Rel(sf, fantasynerds, "Fetches lineups and news", "HTTPS")
    Rel(sf, mlbstats, "Fetches schedules and results", "HTTPS")
    Rel(sf, stripe, "Processes payments, receives webhooks", "HTTPS")
    Rel(sf, claude, "Generates content, classifies articles", "HTTPS")
    Rel(sf, exa, "Discovers external articles", "HTTPS")
    Rel(sf, aws, "Deployed on", "Internal")
```

## Actors

| Actor | Description |
|-------|-------------|
| Visitor | Anonymous user. Accesses all public SEO pages and the agentic chatbot. Arrives via Google or direct link. |
| Subscriber | Authenticated user with active Stripe subscription. Accesses premium scouting reports, Game Day Magazines, and live game dashboards. |
| Admin | Operator authenticated via Joshua gate (`/joshua`). Manages Oban workers, feature flags, agentic query clusters, and monitors the platform. |

## External Systems

| System | Integration | Frequency |
|--------|-------------|-----------|
| FantasyNerds | REST API for lineups (every 30 min) and news (every 1 min) | High |
| MLB Stats API | REST API for schedules, rosters, game results | Daily + event-driven |
| Stripe | Checkout sessions, webhooks for subscription lifecycle | On-demand |
| Anthropic Claude | Content generation (Haiku for classification, Sonnet for reports) | Per-article + daily |
| Exa.ai | Neural search for external article discovery via chatbot | Per user query |
| AWS | Full deployment target (EKS, RDS, ElastiCache, S3, Route 53) | Always |
