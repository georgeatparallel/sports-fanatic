# Implementation Plan: Agentic News Feed with Command Input

Based on architect spec in `agent-notes/architect.md`.

## Phase Order & Dependencies

### Step 1: Database Migration & Schemas (no dependencies)
- Create migration `create_news_agent_tables` with:
  - `accounts.news_agent_settings` table (user_id, raw_prompt, parsed_criteria JSONB, status, last_run_at, last_result, error_message, timestamps)
  - `accounts.news_agent_results` table (user_id, setting_id, matched_news_item_ids UUID[], exa_results JSONB, explanation, run_date, timestamps)
  - `ALTER content.news_items ADD COLUMN domain_tags TEXT[] DEFAULT '{}'` with GIN index
- Create Ecto schemas:
  - `lib/sports_fanatic/agents/news_agent_setting.ex`
  - `lib/sports_fanatic/agents/news_agent_result.ex`
- Update `lib/sports_fanatic/content/news_item.ex` to add `:domain_tags` field

### Step 2: Agents Context (depends on Step 1)
- Create `lib/sports_fanatic/agents.ex` with:
  - `create_setting/2` — insert with status "pending"
  - `list_user_settings/1` — all settings for a user
  - `get_setting!/2` — with user_id guard
  - `update_setting/2` — update parsed_criteria, status
  - `delete_setting/2` — with user_id guard
  - `clear_user_settings/1` — delete all for user
  - `count_user_settings/1` — for rate limiting (max 20)
  - `create_result/1` — insert agent result
  - `list_user_results/2` — results for user, optionally by setting_id
  - `latest_results_for_user/1` — most recent run's results
  - `users_with_active_settings/0` — for worker
  - `settings_for_user/1` — active settings for execution

### Step 3: Python Bridge Endpoints (parallel with Step 2)
- Add to `python_bridge/src/api/agents.py`:
  - `POST /agents/parse-setting` — Claude Haiku tool_use to decompose natural language into structured criteria
  - System prompt for baseball-domain setting interpretation
  - Tool schema matching FR-004 output format
- Add to `python_bridge/src/agents/parser.py`:
  - `parse_setting()` function with Claude Haiku
  - 500-char prompt limit
  - Prompt injection guardrails
- Update `python_bridge/src/news/analyzer.py`:
  - Add `domain_tags` to CLASSIFY_TOOL schema output
  - Add domain tag extraction instructions to system prompt
- Update `python_bridge/src/news/models.py`:
  - Add `domain_tags: list[str]` to response model
- Update `python_bridge/src/main.py`:
  - Register agents router
- Update `lib/sports_fanatic/python_bridge.ex`:
  - Add `parse_setting/2` function
  - Add `execute_agents/2` function (stub for Phase 2)

### Step 4: Oban Workers (depends on Step 2)
- Create `lib/sports_fanatic/workers/parse_setting_worker.ex`:
  - Queue: `content_generation`
  - Takes setting_id, calls Python Bridge, updates setting with parsed_criteria
  - On success: status → "active", broadcast PubSub
  - On failure: status → "failed", store error_message
- Create `lib/sports_fanatic/workers/run_news_agents_worker.ex`:
  - Queue: `content_generation`
  - Cron: `0 13 * * *` (9am ET/EDT)
  - Feature flag check: `news_agents_enabled`
  - For each user with active settings:
    - Bundle settings into query criteria
    - Query news_items matching criteria (players, teams, categories, domain_tags)
    - Create news_agent_results
    - Update setting status and last_run_at
    - Broadcast results via PubSub
- Update `config/config.exs`:
  - Add RunNewsAgentsWorker to crontab

### Step 5: NewsLive UI Changes (depends on Steps 2, 3)
- Modify `lib/sports_fanatic_web/live/news_live.ex`:
  - New assigns: `active_tab` (feed/agents), `search_query`, `user_settings`, `agent_results`, `filtered_feed`
  - Mount: load user settings if authenticated, subscribe to `agent:settings:#{user_id}`
  - `handle_event("submit_command")` — parse /settings-apply, /settings-clear, or plain search
  - `handle_event("switch_news_tab")` — toggle tab
  - `handle_event("delete_setting")` — remove setting
  - `handle_event("search_feed")` — filter feed client-side
  - `handle_info({:setting_updated, setting})` — PubSub update
  - `handle_info({:agent_results, results})` — PubSub update
- Modify `lib/sports_fanatic_web/live/news_live.html.heex`:
  - Sticky command input at top (fixed z-10, 4-line textarea)
  - Tab switcher (Feed | Agents)
  - Feed tab: existing feed + unhidden player/team data
  - Agents tab: settings list with status badges, results, delete buttons
  - Player links: `<a href="/mlb/players/{team_slug}/{player_slug}">`
  - Team badges: abbreviation + league (AL/NL)
  - Domain tags as small badges below category

### Step 6: Joshua Admin Agents Tab (depends on Step 2)
- Modify `lib/sports_fanatic_web/live/admin_live.ex`:
  - Add "agents" tab to existing tab system
  - Feature flag toggle for `news_agents_enabled`
  - View all users' settings (read-only)
  - Manual "Run All Agents" trigger button
  - Display next scheduled run time

### Step 7: Domain Tags Backfill (depends on Step 3)
- Update `lib/sports_fanatic/content/news_item.ex`:
  - Add `domain_tags` field to schema and changeset
- Update `lib/sports_fanatic/workers/fetch_news_worker.ex`:
  - Store domain_tags from AI analysis response
- Consider: backfill worker for existing articles (optional, can be deferred)

## Critical Implementation Notes

- **PubSub topics**: `agent:settings:#{user_id}` for setting updates, `agent:results:#{user_id}` for execution results
- **Auth check**: Every agent-related `handle_event` must verify `socket.assigns.current_user`
- **Rate limits**: Max 20 settings/user, max 5 /settings-apply per hour
- **Enter submits**: Use `phx-keydown` with `key: "Enter"` (not Shift+Enter) for submit
- **Sticky CSS**: `sticky top-0 z-10 bg-white` on the command input container
- **Circuit breaker**: Use existing PythonBridge circuit breaker for parse_setting calls
- **Timezone**: Oban cron is UTC. 9am ET = 13:00 UTC (EDT) or 14:00 UTC (EST). Use 13:00 and accept 1hr drift during EST.
