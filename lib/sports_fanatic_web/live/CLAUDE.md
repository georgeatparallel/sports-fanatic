Parent: `../../../CLAUDE.md`

# CLAUDE.md — LiveView modules

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

| Module | File | Purpose |
|--------|------|---------|
| `ChatLive` | `chat_live.ex` | Conversational chatbot (replaces NewsLive on `/` and `/chat`) |
| `NewsLive` | `news_live.ex` | News feed with patch-based date nav; chat or legacy command mode |
| `FeedsLive` | `feeds_live.ex` | User feed import / browsing |
| `DashboardLive` | `dashboard_live.ex` | Subscription dashboard |
| `ScoutingLive` | `scouting_live.ex` | Premium scouting report viewer |
| `GameDayLive` | `game_day_live.ex` | Premium Game Day Magazine viewer |
| `GameDayIndexLive` | `game_day_index_live.ex` | Premium index |
| `ArchiveScoutingLive` | `archive_scouting_live.ex` | Premium archive |
| `ArchiveGameDayLive` | `archive_game_day_live.ex` | Premium archive |
| `AdminLive` | `admin_live.ex` | Joshua-gated admin dashboard (multi-tab) |

## NewsLive events

| Event | Payload | Auth | Description |
|-------|---------|------|-------------|
| `submit_command` | `%{"input" => text}` | Yes | Parses slash command and dispatches |
| `delete_setting` | `%{"id" => uuid}` | Yes | Deletes the user's agent setting |
| `switch_news_tab` | `%{"tab" => "feed"\|"agents"}` | No | Toggles Feed / Agents tab |
| `search_feed` | `%{"query" => text}` | No | Client-side substring filter (debounced 300ms) |
| `run_setting_now` | `%{"id" => uuid}` | Premium | Enqueues immediate agent execution |

## NewsLive PubSub topics

- `"news:feed:{date}"` — new articles for that date
- `"news:feed"` — global news broadcast
- `"agent:settings:{user_id}"` — `ParseSettingWorker` broadcasts
  `{:setting_updated, setting}` after LLM parsing
- `"chat:agent:{user_id}"` — chatbot mode: `:agent_progress`,
  `:agent_complete`, `:agent_error`

## AdminLive — tabs

| Tab | Subject |
|-----|---------|
| `workers` | Oban worker health + manual enqueue |
| `scouting_pipeline` | Scouting generation status |
| `agents` | News agent settings; `news_agents_enabled` flag |
| `queries` | Chat query clusters; schedule on/off; `news_chatbot_enabled` flag |
| `feeds` | User feeds + research |
| `feature_flags` | Generic feature flag table |
| `x_agent` | X (Twitter) agent — approval queue, cost, posts, watched targets |

## AdminLive — Queries tab events

| Event | Payload | Description |
|-------|---------|-------------|
| `switch_tab` (tab: `"queries"`) | — | Load clusters |
| `toggle_query_schedule` | `%{"cluster_id" => uuid}` | Toggle `scheduled` flag |
| `set_query_frequency` | `%{"cluster_id" => uuid, "freq" => string}` | hourly / daily / disabled |
| `run_query_now` | `%{"cluster_id" => uuid}` | Enqueue immediate Exa search |

## AdminLive — X Agent tab events

| Event | Payload | Side effect |
|-------|---------|-------------|
| `switch_tab` (tab: `"x_agent"`) | — | Loads X state + subscribes to `"admin:x_agent"` |
| `toggle_x_agent` | `%{"enabled" => bool_str}` | `FeatureFlags.update/2` |
| `toggle_x_approval` | `%{"required" => bool_str}` | `FeatureFlags.update/2` |
| `toggle_x_outbound` | `%{"enabled" => bool_str}` | `FeatureFlags.update/2` |
| `approve_post` | `%{"post_id" => uuid}` | `X.approve_post/1` → enqueues `MainPostWorker` |
| `edit_post` | `%{"post_id" => uuid, "main" => str, "reply" => str}` | Re-sanitizes, persists |
| `reject_post` | `%{"post_id" => uuid}` | sets `status="rejected"` |
| `post_now` | `%{"type" => string}` | Rate-limited 1/min |
| `reschedule_day` | `%{}` | Rate-limited 1/5min; reruns `Scheduler.plan_day/1` |
| `add_watched_target` | `%{"handle" => str, "focus" => str}` | Validates handle regex |
| `remove_watched_target` | `%{"id" => uuid}` | Deletes row |
| `refresh_oauth` | `%{}` | Calls `X.refresh_if_needed/0` |
| `connect_x_account` | `%{}` | `push_navigate(to: "/admin/x/oauth/start")` |

Rate limiting uses an in-memory ETS table `:x_admin_rate_limit` keyed on
`{event_name, action_key}` mapping to `last_at_ms`. Rejections set
`put_flash(:error, ...)`.

## AdminLive — X Agent PubSub topic

`"admin:x_agent"` — broadcast targets:

- `{:post_state_change, post}` — every worker state transition
- `{:budget_exceeded, today_mills}` — `SpendLedger` cap tripped
- `{:token_failure, reason}` — `RefreshXTokenWorker` error
- `{:circuit_state_change, state}` — X CircuitBreaker open/closed

## Joshua admin gate

`/admin` lives in `live_session :admin` and pipes through
`[:browser, :require_joshua]`. The passphrase login lives at `/joshua` with
`JoshuaRateLimiter` on the POST. Env vars: `JOSHUA_USERNAME`, `JOSHUA_PASSWORD`.

## Premium routes

All `/premium/*` LiveViews require `[:browser, :require_subscription]`.
`SubscriptionGate` plug checks `Accounts.has_active_subscription?/1`. See
SEC-005 in `docs/KNOWN_ISSUES.md` — the gate currently lets through users
whose `subscription_expires_at` is nil for non-free tier.

## Chat UI (`news_chatbot_enabled`)

The chat container uses `phx-update="append"` (LiveView 0.19 — no `streams`).
A `ScrollBottom` JS hook in `assets/js/app.js` auto-scrolls on new messages
(CHAT-002). When `news_chatbot_enabled` is off, NewsLive falls back to the
legacy textarea/command mode.
