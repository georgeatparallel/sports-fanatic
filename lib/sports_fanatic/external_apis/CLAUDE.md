Parent: `../../../CLAUDE.md`

# CLAUDE.md — External API clients

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

Thin HTTP clients that talk to non-Python-Bridge third-party APIs. Every client
uses `Req` and is intended to be replaced by a `Req.Test.stub/2` in tests.

## Clients

| Module | File | API |
|--------|------|-----|
| `SportsFanatic.ExternalApis.Exa` | `exa.ex` | Exa.ai REST (chatbot article discovery, X agent research) |
| `SportsFanatic.ExternalApis.FantasyNerds` | `fantasy_nerds.ex` | FantasyNerds REST (lineups, projections) |

## Exa.ai client (`exa.ex`)

Called directly from the Elixir side rather than through the Python Bridge.
This keeps the chatbot's article discovery path and the X agent's source
gathering path independent of the scouting pipeline.

Key invariants:

- Only `http` / `https` URLs are accepted via the private `valid_url?/1` check.
  Anything else (`javascript:`, `data:`, custom schemes) is dropped before
  storage (CHAT-SEC-006).
- Per-call options: `:num_results`, `:category` (one of Exa's enum values),
  `:include_domains`, `:exclude_domains`.
- Returns `{:ok, [%{title, url, author, published_date, text, domain}]}` or
  `{:error, reason}`.

Configure via `EXA_API_KEY` in `runtime.exs`. Without the key the client
returns `{:error, :no_api_key}` without making a network call.

The Python Bridge's existing `/scouting/search` Exa endpoint is unchanged and
continues to serve the scouting feature only.

## FantasyNerds client (`fantasy_nerds.ex`)

Provides game data, projections, and lineup snapshots. See the project memory
note (`feedback_api_field_mapping.md`) — always verify the actual API field
names before adjusting parsing logic; vendor sometimes renames silently.

Configure via `FANTASY_NERDS_API_KEY` in `runtime.exs`.

## Adding a new external API client

1. Create `lib/sports_fanatic/external_apis/<vendor>.ex` with a clear
   `@moduledoc` and per-call typespecs.
2. Validate inputs and outputs at the boundary — strip control chars, reject
   `nil` where unexpected, log only the response status / counts (never
   payload).
3. Add an env var to `runtime.exs` and to the cross-cutting env-var table in
   the root `CLAUDE.md`.
4. Add a unit test using `Req.Test.stub/2` in
   `test/sports_fanatic/external_apis/<vendor>_test.exs`.
5. Register the test path in the `unit_test_files` block in `mix.exs`.
