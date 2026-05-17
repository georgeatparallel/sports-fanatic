# Security Guide

## Authentication & Authorization

### User Authentication
- **Password hashing**: bcrypt with 12 rounds via `bcrypt_elixir`
- **Sessions**: 256-bit random tokens stored server-side in PostgreSQL, 30-day expiry
- **CSRF**: Phoenix built-in CSRF protection on all browser forms
- **Logout**: Session token deleted from database immediately

### Authorization Layers

| Layer | Plug | Purpose |
|-------|------|---------|
| User fetch | `FetchCurrentUser` | Runs on every request, sets `conn.assigns.current_user` |
| Auth required | `RequireAuthenticated` | Redirects to `/login` with `return_to` |
| Subscription | `SubscriptionGate` | Checks `has_active_subscription?/1`, redirects to `/subscribe` |
| Admin | `RequireAdmin` | Checks `user.is_admin`, redirects to `/` |
| Joshua | `RequireJoshua` | Rate-limited env-var auth for admin panel |

### Joshua Admin Gate
- Credentials: `JOSHUA_USERNAME` and `JOSHUA_PASSWORD` environment variables
- Timing-safe comparison via `Plug.Crypto.secure_compare/2`
- Session TTL: 24 hours
- Rate limiting: 5 failed attempts per IP per 5-minute window (ETS-based)

## Input Validation & Sanitization

### XSS Prevention
- All HEEx templates auto-escape by default
- Chat messages are sanitized via `HtmlSanitizeEx.strip_tags/1` before rendering
- JSON-LD structured data uses `Jason.encode!/1` (never raw strings)
- **Known issue (SEC-001)**: Some legacy templates use `raw/1` on AI content — remediation in progress

### SQL Injection
- All database queries use Ecto parameterized queries
- Full-text search uses `websearch_to_tsquery` (safe against tsquery injection)
- ILIKE patterns escape `%` and `_` via `sanitize_like/1`

### URL Validation
- Exa.ai results: only `http`/`https` schemes accepted before storage
- `return_to` parameter: **Known issue (SEC-002)** — not validated as relative path

## API Security

### Stripe Webhooks
- Signature verification via `Stripe-Signature` header in `VerifyStripeWebhook` plug
- Raw request body cached by `CacheRawBody` plug for signature computation
- **Known issue (SEC-004)**: No idempotency check — duplicate events may cause redundant writes

### Python Bridge
- Internal Docker network only — port 8000 not exposed to host in production
- Circuit breaker prevents cascade failures (3-failure threshold, 5-min cooldown)
- **Known issue (SEC-007)**: `docker-compose.yml` exposes port 8000 to host — remove for production

### External API Keys
- Stored in environment variables, loaded at runtime via `config/runtime.exs`
- Never logged, never sent to client
- `EXA_API_KEY` and `ANTHROPIC_API_KEY` used server-side only

## Rate Limiting

| Endpoint | Limit | Mechanism |
|----------|-------|-----------|
| `/joshua/login` | 5 attempts / IP / 5 min | ETS counter in `JoshuaRateLimiter` |
| Chatbot queries | 10 / user / hour, 50 / user / day | `ChatBot.check_rate_limit/1` (PostgreSQL) |
| Agent settings | 5 / user / hour, 20 max active | `Agents` context (PostgreSQL) |
| `/login`, `/register` | **Not implemented** (SEC-003) | — |

## Agent Security

### Prompt Injection Mitigation
- Agent system prompts are not user-modifiable
- User queries are treated as opaque data in the ReAct tool loop
- The context resolution endpoint (`/chat/resolve-context`) uses Claude's tool_use API for structured output, reducing free-form injection risk
- Maximum prompt length: 500 characters for settings, unlimited for chat (rate-limited instead)

### Agent Process Isolation
- Each agent runs in a supervised Task process (DynamicSupervisor)
- 60-second timeout prevents runaway processes
- `max_children: 100` on DynamicSupervisor prevents resource exhaustion
- One agent per user (new query cancels in-flight agent)
- Error messages shown to users are generic — internal details logged server-side only

### User Data Isolation
- Chat sessions and messages are scoped to `user_id` in all queries
- `clear_session/2` requires both `session_id` and `user_id`
- Admin can view all sessions (read-only) via Joshua admin panel
- Anonymous users have ephemeral sessions (no persistence)

## Known Security Issues

| ID | Severity | Description | Status |
|----|----------|-------------|--------|
| SEC-001 | HIGH | Stored XSS via `raw/1` on AI/external content | Partial mitigation (HtmlSanitizeEx added for chat) |
| SEC-002 | HIGH | Open redirect via unvalidated `return_to` parameter | Open |
| SEC-003 | MEDIUM | No rate limiting on `/login` and `/register` | Open |
| SEC-004 | MEDIUM | Stripe webhook idempotency not implemented | Open |
| SEC-005 | MEDIUM | SubscriptionGate nil expiry bypass | Open |
| SEC-006 | MEDIUM | `.env` not in `.gitignore` | Open |
| SEC-007 | MEDIUM | Python bridge port exposed to host | Open (dev only) |

## Secrets Management (Production)

In AWS production deployment:
- Secrets stored in AWS Secrets Manager
- Synced to Kubernetes via External Secrets Operator
- IRSA (IAM Roles for Service Accounts) for pod-level access control
- No secrets in container images or environment variables at build time
