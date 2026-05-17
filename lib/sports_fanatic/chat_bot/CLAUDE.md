Parent: `../../../CLAUDE.md`

# CLAUDE.md — ChatBot context

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

Conversational agent backing the news feed (`news_chatbot_enabled` flag).

## Schemas (`accounts` PostgreSQL prefix)

| Module | File | Table |
|--------|------|-------|
| `SportsFanatic.ChatBot.ChatSession` | `chat_session.ex` | `accounts.chat_sessions` |
| `SportsFanatic.ChatBot.ChatMessage` | `chat_message.ex` | `accounts.chat_messages` |
| `SportsFanatic.ChatBot.QueryCluster` | `query_cluster.ex` | `accounts.query_clusters` |
| `SportsFanatic.ChatBot.QueryClusterMember` | `query_cluster_member.ex` | `accounts.query_cluster_members` |
| `SportsFanatic.ChatBot.SkillRouter` | `skill_router.ex` | (pure routing logic) |

## Session lifecycle

- Sessions expire after **30 minutes** of inactivity (`last_activity_at`).
- New sessions start automatically when the previous expires.
- Last **10 messages** (5 user + 5 assistant) are sent to the LLM as context
  for follow-up queries.

## Rate limits (enforced in `chat_bot.ex` context)

- 10 queries / hour per user
- 50 queries / day per user
- At most 1 active agent per user (new submission cancels in-flight agent)

## Message roles

- `user` — the user's natural language input
- `assistant` — the final LLM response
- `progress` — interim status (tool calls, fetching, etc.)

`content` is HTML-sanitized via `HtmlSanitizeEx.strip_tags/1` **before storage**.
Never call `raw/1` on this column in templates (CHAT-001).

## Query clusters

`ConsolidateQueriesWorker` runs hourly and groups new chat messages into
`accounts.query_clusters` via:

1. Player/team entity overlap (UUID set intersection)
2. Lowercased keyword intersection
3. Jaro distance > 0.85 for surface-form matching

Admin can mark a cluster as `scheduled` and pick a `schedule_frequency`
(`hourly` / `daily` / `disabled`). Scheduled clusters trigger
`ScheduledExaSearchWorker`.

See CHAT-004 in `docs/KNOWN_ISSUES.md` for the planned upgrade to embedding-
based similarity post-MVP.

## Joshua admin Queries tab

Surfaces all unique clusters with entity tags, topic tags, and frequency counts.
Per-cluster controls: schedule toggle, frequency selector, "Run Now" button.

Detailed event map lives in `lib/sports_fanatic_web/live/CLAUDE.md`.
