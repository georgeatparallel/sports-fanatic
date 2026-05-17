Parent: `../../../CLAUDE.md`

# CLAUDE.md — Agents (Jido-pattern actions + orchestrators)

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

This folder holds **stateless action modules** (Jido-pattern) and the
orchestrators that compose them.

## Why no Jido dep

`jido` v2.2 and `jido_ai` v2.1 require Elixir >= 1.18; the project runs Elixir
1.15.7. Until upgrade, `SportsFanatic.Agents.Action` (`action.ex`) provides the
same `name/0` + `description/0` + `run/2` interface using a small macro. When
the Elixir version is bumped, replace `use SportsFanatic.Agents.Action` with
`use Jido.Action` and add `{:jido, "~> 2.2"}, {:jido_ai, "~> 2.1"}` to mix.exs
(tracked as CHAT-005 in `docs/KNOWN_ISSUES.md`).

## Action behaviour

```elixir
defmodule MyAction do
  use SportsFanatic.Agents.Action,
    name: "my_action",
    description: "Human-readable purpose for the LLM to read"

  @impl true
  def run(params, context) do
    # ... -> {:ok, %{...}} | {:error, term()}
  end
end
```

## Orchestrators

| Module | File | Purpose |
|--------|------|---------|
| `SportsFanatic.Agents.NewsAgent` | `news_agent.ex` | Chat ReAct loop; broadcasts on `"chat:#{user_id}"` |
| `SportsFanatic.Agents.AgentSupervisor` | `agent_supervisor.ex` | `DynamicSupervisor` + `Registry` for per-user processes |
| `SportsFanatic.Agents.XContentAgent` | `x_content_agent.ex` | Synchronous composer for daily X posts |
| `SportsFanatic.Agents.XReplyAgent` | `x_reply_agent.ex` | ReAct tool loop for X reply drafting |

`NewsAgent` self-terminates after completion or a 60-second timeout. Both
`AgentRegistry` and `AgentDynamicSupervisor` are children in
`application.ex`.

## Action catalogue

| Action | File | Used by |
|--------|------|---------|
| `Actions.SearchLocalNews` | `actions/search_local_news.ex` | NewsAgent |
| `Actions.SearchExa` | `actions/search_exa.ex` | NewsAgent |
| `Actions.ResolveEntities` | `actions/resolve_entities.ex` | NewsAgent |
| `Actions.ClassifyArticle` | `actions/classify_article.ex` | NewsAgent |
| `Actions.GenerateTopHitsPost` | `actions/generate_top_hits_post.ex` | XContentAgent |
| `Actions.GenerateInjuryReportPost` | `actions/generate_injury_report_post.ex` | XContentAgent |
| `Actions.GenerateTeamMagazinePost` | `actions/generate_team_magazine_post.ex` | XContentAgent |
| `Actions.FetchPlayerStats` | `actions/fetch_player_stats.ex` | XReplyAgent |
| `Actions.FetchInjuryStatus` | `actions/fetch_injury_status.ex` | XReplyAgent |
| `Actions.FetchRecentPicks` | `actions/fetch_recent_picks.ex` | XReplyAgent |

## Article discovery pipeline (chatbot)

When `Actions.SearchExa` finds articles whose URLs are not in
`content.news_items`, `Actions.ClassifyArticle` runs each through:

1. `POST /news/analyze` on the Python Bridge (classification + sentiment)
2. `EntityMatcher` for player/team resolution
3. INSERT into `content.news_items` with `source: "exa"`
4. Valkey cache invalidation + `news:feed:{date}` PubSub broadcast

Deduplication is enforced by a partial unique index on `(source_url) WHERE
source = 'exa'`.

## Adding a new action

1. Create `lib/sports_fanatic/agents/actions/<name>.ex` using
   `use SportsFanatic.Agents.Action, name: ..., description: ...`.
2. Implement `run/2` returning `{:ok, map()}` or `{:error, term()}`.
3. Register in the orchestrator's tool loop or `@actions` attribute.
4. Add a Python Bridge endpoint or external API call only if no existing one
   suffices.

## EntityMatcher caveat

`EntityMatcher.match_players/2` and `match_teams/2` require the **caller** to
preload entities from `Repo`. There is no `match_for_article/1` convenience
that hits the DB. Callers preload `Repo.all(Player |> preload(:team))` and
`Repo.all(Team)` once per worker invocation.
