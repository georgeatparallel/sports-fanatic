# Reviewer Agent Notes

## Summary

The Agentic News Feed feature introduces a well-structured agent system with command input, LLM-powered setting parsing, daily execution, and admin controls. The implementation follows existing codebase patterns (Ecto schemas, Oban workers, PythonBridge, LiveView PubSub). The two HIGH security findings from the security agent have been remediated. However, there is one HIGH correctness bug in `RunNewsAgentsWorker` where `or_where` bypasses the date range filter, and the build agent's formatting issues appear to have been fixed (format check now passes). Overall the feature is well-implemented with good separation of concerns, proper user isolation, and thoughtful error handling.

## Verdict: REQUEST_CHANGES

## Review Checklist Results

### Correctness: ISSUES

- [HIGH] `or_where` in `RunNewsAgentsWorker.apply_player_filter/2` and `apply_team_filter/2` breaks the date range constraint. The initial query establishes `WHERE published_date >= from AND published_date <= to`. When `or_where` is then called with `ilike(n.title, ^pattern)`, the resulting SQL becomes `WHERE (published_date >= from AND published_date <= to) OR (title ILIKE '%Judge%')`, which matches ALL articles whose title contains "Judge" regardless of date. The same issue applies to `apply_team_filter`. The fix is to use a subquery or dynamic `where` with `or` composition within a single `where` clause. Recommended fix:

  ```elixir
  defp apply_player_filter(query, %{"target_players" => players})
       when is_list(players) and players != [] do
    conditions =
      Enum.reduce(players, dynamic(false), fn player_name, acc ->
        pattern = "%#{sanitize_like(player_name)}%"
        dynamic([n], ^acc or ilike(n.title, ^pattern) or ilike(n.ai_summary, ^pattern))
      end)

    where(query, ^conditions)
  end
  ```

  Same pattern for `apply_team_filter`.

- [PASS] FR-001 through FR-010 are all addressed at the Phase 1 level described in the spec. Sticky command input, slash commands, settings persistence, LLM parsing, agent execution, Agents tab, entity display, domain_tags, admin panel, and client-side search are all present.
- [PASS] Edge cases: empty input, missing user, max settings cap, hourly rate limit, circuit breaker open, setting not found -- all handled.
- [PASS] Date navigation and PubSub handlers are preserved correctly from the existing NewsLive implementation.

### Security: PASS

- [PASS] SEC-NEW-001 (HIGH - error detail leakage) remediated: `ParseSettingWorker` now stores a generic "Unable to parse your setting. Please try again later." message and logs the real error via `Logger.error`.
- [PASS] SEC-NEW-002 (HIGH - missing hourly rate limit) remediated: `count_user_settings_last_hour/1` query added, `create_setting/2` checks it before the max-settings check, LiveView handles `:hourly_rate_limit_exceeded`.
- [PASS] SEC-NEW-003 (MEDIUM - validate_required on status) remediated: `validate_required([:status])` added to `update_changeset/2`.
- [PASS] SEC-NEW-006 (LOW - Float.round crash) remediated: `(confidence + 0.0)` coerces integer to float.
- [PASS] No `raw/1` calls in any template. All user content is auto-escaped via HEEx interpolation.
- [PASS] All Ecto queries use parameterized bindings. ILIKE patterns are sanitized via `sanitize_like/1`.
- [PASS] User isolation enforced consistently: all context functions scope by `user_id`.
- [PASS] Prompt injection guardrails present in Python parser system prompt with tool_use forced output.
- [INFO] SEC-NEW-004 (prompt injection) and SEC-NEW-005 (PubSub topic) are acceptable for Phase 1 as documented.
- [INFO] SEC-NEW-007 (admin Run All confirmation) is low-risk given admin gate but would be a nice-to-have.

### Performance: PASS

- [PASS] `users_with_active_settings/0` uses `distinct` to avoid loading duplicate user rows.
- [PASS] `find_matching_news` queries only `select([n], n.id)` -- no full row loads during agent execution.
- [PASS] Sequential per-user processing with `try/rescue` isolation prevents cascade failures.
- [PASS] `filter_feed/2` operates on the in-memory feed assign (already loaded), no additional DB queries.
- [PASS] The `domain_tags` GIN index supports the `&&` array overlap operator efficiently.
- [INFO] The `latest_results_for_user/1` function makes two queries (one for max date, one for results). This is acceptable for the expected result set size but could be combined with a subquery in a future optimization.

### Code Quality: ISSUES

- [MEDIUM] The `or_where` bug described above is a logic error, not just a style issue.
- [PASS] Code follows existing codebase patterns: Ecto schemas with changesets, Phoenix contexts, Oban workers with `content_generation` queue, PythonBridge HTTP client.
- [PASS] Module organization is clean: `agents/` directory for schemas, `agents.ex` for context, workers in `workers/`.
- [PASS] The `setting_status_class/1` helper is a good pattern for template status styling.
- [PASS] `format_changeset_error/1` helper properly handles both changeset and non-changeset errors.
- [INFO] `load_user_from_session/1` duplicates the FetchCurrentUser plug pattern. This is standard for LiveView since plugs don't run in the WebSocket path. No issue.

### Testing: PASS (with noted gaps)

- [PASS] 295 tests, 0 failures. All new tests pass.
- [PASS] Schema changeset tests cover required fields, valid/invalid statuses, length validation, optional fields, defaults.
- [PASS] Worker tests verify Oban job structure (queue, max_attempts, args).
- [PASS] Domain tags regression tests verify the field doesn't break existing validations.
- [INFO] No integration tests for `Agents` context functions or `RunNewsAgentsWorker` query logic. The `or_where` bug would likely have been caught by an integration test with seeded data. This is acceptable for Phase 1 given the DB-less testing approach, but the query logic gap should be prioritized for integration test coverage.
- [INFO] No LiveView tests for the command input, tab switching, or search filtering. Acceptable for Phase 1 but recommended for Phase 2.

### Documentation: PASS

- [PASS] CLAUDE.md comprehensively updated with Agents System section, updated architecture, file structure, routing conventions, database schemas, workers, known issues, and common tasks.
- [PASS] Known issues AGENTS-001 through AGENTS-003 properly document Phase 1 limitations.
- [PASS] PubSub topics documented in routing conventions.
- [INFO] The CLAUDE.md test count ("84 tests total" in Testing Strategy) was updated from the pre-feature count but doesn't match the current 295. This is a minor documentation drift noted by the documentation agent.

### Build & CI: PASS

- [PASS] `mix compile --warnings-as-errors` passes cleanly.
- [PASS] `mix format --check-formatted` passes (formatting issues from build agent's report have been fixed).
- [PASS] No new Elixir dependencies added (Jido deferred to Phase 2 as spec intended).
- [PASS] No new Python dependencies needed.
- [PASS] Oban crontab entry at `0 13 * * *` correctly configured.
- [PASS] `test.unit` alias includes all 5 new test file paths (4 new + the domain_tags test).

## Issues Found

- [HIGH] `or_where` bypasses date range in `RunNewsAgentsWorker` -- `lib/sports_fanatic/workers/run_news_agents_worker.ex:125-128,133-138` -- Replace `or_where` with `dynamic` composition inside a `where` clause to preserve the date range constraint. See recommendation in Correctness section above.

## Decisions

- REQUEST_CHANGES due to the HIGH correctness bug in `RunNewsAgentsWorker`. The `or_where` issue means agent execution will match articles from any date when player or team filters are present, producing incorrect and potentially very large result sets. This is a data correctness issue that will be visible to users in the Agents tab results.
- All security remediations from the security agent have been properly addressed. No new security issues found.
- The remaining MEDIUM and LOW findings from the security agent (SEC-NEW-004 prompt injection, SEC-NEW-005 PubSub, SEC-NEW-007 admin confirm) are acceptable for Phase 1.

## Files Reviewed

- `priv/repo/migrations/20260515190000_create_news_agent_tables.exs` -- correct
- `lib/sports_fanatic/agents/news_agent_setting.ex` -- correct
- `lib/sports_fanatic/agents/news_agent_result.ex` -- correct
- `lib/sports_fanatic/agents.ex` -- correct
- `lib/sports_fanatic/workers/parse_setting_worker.ex` -- correct
- `lib/sports_fanatic/workers/run_news_agents_worker.ex` -- HAS BUG (or_where)
- `python_bridge/src/api/agents.py` -- correct
- `python_bridge/src/agents/parser.py` -- correct
- `lib/sports_fanatic/python_bridge.ex` -- correct
- `lib/sports_fanatic_web/live/news_live.ex` -- correct
- `lib/sports_fanatic_web/live/news_live.html.heex` -- correct
- `lib/sports_fanatic_web/live/admin_live.ex` -- correct
- `lib/sports_fanatic/content/news_item.ex` -- correct
- `python_bridge/src/news/analyzer.py` -- correct
- `python_bridge/src/news/models.py` -- correct
- `python_bridge/src/main.py` -- correct (agents router registered)
- `lib/sports_fanatic/workers/fetch_news_worker.ex` -- correct (domain_tags stored)
- `lib/sports_fanatic/news.ex` -- correct (domain_tags and league in feed)
- `config/config.exs` -- correct (crontab entry)
- `mix.exs` -- correct (test.unit alias updated)
- `CLAUDE.md` -- correct (comprehensive update)
- All 5 test files -- correct

## Commendations

- The context module (`Agents`) has clean separation of concerns with proper user isolation on every function. The rate limiting implementation with both a max-settings cap and hourly rate limit is thorough.
- The `ParseSettingWorker` error handling is well-structured: circuit breaker retries, generic user-facing messages, detailed internal logging.
- The Python Bridge parser uses `tool_choice: {"type": "tool", "name": "parse_setting"}` with forced tool use, which is the correct pattern for structured output extraction and significantly reduces prompt injection surface.
- The LiveView command input implementation is clean -- proper auth gating, command parsing, flash messages, and PubSub integration without blocking the LiveView process for LLM calls.
- Good defensive coding in the template: null checks on players, teams, domain_tags, and optional fields throughout the HEEx template.
- The migration is well-structured with proper foreign keys, ON DELETE CASCADE, CHECK constraint on status, and GIN index for domain_tags.

## Recommendations for Next Agent

- **Fix the `or_where` bug** in `lib/sports_fanatic/workers/run_news_agents_worker.ex` lines 122-139. Replace `or_where` with `Ecto.Query.dynamic/2` composition. Both `apply_player_filter/2` and `apply_team_filter/2` need the same fix. The pattern should be:

  ```elixir
  defp apply_player_filter(query, %{"target_players" => players})
       when is_list(players) and players != [] do
    conditions =
      Enum.reduce(players, dynamic(false), fn player_name, acc ->
        pattern = "%#{sanitize_like(player_name)}%"
        dynamic([n], ^acc or ilike(n.title, ^pattern) or ilike(n.ai_summary, ^pattern))
      end)

    where(query, ^conditions)
  end
  ```

  Apply the same pattern to `apply_team_filter/2`.

- After fixing, verify with `mix compile --warnings-as-errors` and `mix test.unit` that everything still passes.
