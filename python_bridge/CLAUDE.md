Parent: `../CLAUDE.md`

# CLAUDE.md — Python Bridge (FastAPI :8000)

> See the Documentation Placement Rule in `../CLAUDE.md` before adding
> content here.

---

FastAPI microservice that hosts ML models, Monte Carlo simulation, Claude
prompts (scouting, game day, news classification, agent parsing, X agent
content), and Exa.ai search (scouting only — the Elixir side has its own Exa
client for the chatbot path).

## Architecture

```
Elixir SportsFanatic.PythonBridge (Req)
   └── http://python-bridge:8000 (Docker internal network)
       └── FastAPI app (src/main.py)
           ├── routers: predict, scouting, gameday, news, agents, schedule,
           │           chat, simulation, x_agent, injury_report, team_magazine
           ├── Claude API (Anthropic Python SDK)
           └── Exa.ai (scouting search only)
```

`SportsFanatic.PythonBridge.CircuitBreaker` (Elixir side) trips after 50
consecutive failures with a 30-second cooldown. This is tuned for high-volume
internal RPC; the X agent's `SportsFanatic.X.CircuitBreaker` uses tighter
thresholds (3 / 5 min) because each call costs real money.

`SportsFanatic.PythonBridge.HealthCheck` pings `/health` every 30 seconds.

## Endpoint catalogue

| Path | Module | Purpose |
|------|--------|---------|
| `POST /predict/hit`, `/predict/hr` | `api/predict.py` | ML game predictions |
| `POST /scouting/search`, `/scouting/generate`, `/scouting/search_multi`, `/scouting/classify` | `api/scouting.py` | AI scouting reports |
| `POST /gameday/generate` | `api/gameday.py` | Game Day Magazine |
| `POST /news/analyze` | `api/news.py` | Headline + excerpt classification |
| `POST /agents/parse-setting`, `/agents/execute` | `api/agents.py` | News agent parser + executor stub |
| `POST /schedule/fetch`, `/schedule/teams`, `/schedule/roster` | `api/schedule.py` | MLB schedule via MLB Stats API |
| `POST /chat/resolve-context`, `/chat/synthesize-research` | `api/chat.py` | Chatbot helpers |
| `POST /simulation/run` | `simulation/engine.py` | Monte Carlo (NumPy) |
| `POST /x-agent/draft-post`, `/x-agent/draft-reply` | `api/x_agent.py` | Tweet body drafting |
| `POST /injury-report/generate` | `api/injury_report.py` | Per-player injury page generator |
| `POST /team-magazine/generate` | `api/team_magazine.py` | Per-team daily magazine |

Routers are registered in `src/main.py`. New endpoints follow the existing
`APIRouter()` + `BaseModel` request pattern.

## Prompts

- `src/agents/parser.py` — news agent setting parser
- `src/agents/x_agent_prompts.py` — X content + reply system prompts (top hits,
  injury, team magazine, reply)

All Claude calls use **Claude Haiku 4.5** (`claude-haiku-4-5-20260201` or the
env-pinned tag) via `anthropic.Anthropic().messages.create(...)`.

## Prompt-injection guardrails

`src/agents/parser.py` and `src/api/x_agent.py` (draft-reply) reject inbound
text containing: `"ignore previous"`, `"system prompt"`, `"<|"`, control
characters. They return HTTP 422 with a generic message; the Elixir caller
logs and falls back. Tool-use is used instead of string interpolation so the
LLM cannot confuse user content for instructions.

## Env vars

| Var | Required | Purpose |
|-----|----------|---------|
| `ANTHROPIC_API_KEY` | Yes | Claude API |
| `EXA_API_KEY` | When `/scouting/search` used | Exa.ai search (scouting path only) |
| `MLB_STATS_API_BASE` | Optional | MLB Stats API base URL (default: official) |

## Production note

`python-bridge` must **not** expose port 8000 to the host. The dev
`docker-compose.yml` exposes it but production should drop the `ports`
entry (SEC-007). The bridge is reachable only on the internal Docker
network from `web`.

## Adding a new endpoint

1. Create `src/api/<name>.py` with `router = APIRouter()` and a single
   `@router.post(...)` function.
2. Add `app.include_router(<name>_router, prefix="/<name>", tags=["<name>"])`
   to `src/main.py`.
3. Add a corresponding `SportsFanatic.PythonBridge.<verb>/<n>` function in
   `lib/sports_fanatic/python_bridge.ex` calling `post("/path", body)`.
4. Document the JSON shape (request + response) in this file's catalogue.
5. If the endpoint touches Claude, factor the prompt into a separate constant
   module in `src/agents/` for testability.
