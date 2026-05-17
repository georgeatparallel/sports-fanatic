# Documentation Agent Notes

## Summary

Updated `CLAUDE.md` with full documentation for the Elixir-native hit predictions pipeline. No new documentation files were created — all content was added to the single-source-of-truth `CLAUDE.md`. `.env.example` already contained all required variables (added by the coder); no changes were needed there.

## Decisions

- All documentation placed in `CLAUDE.md` only; no new top-level Markdown files created per the project's single-source-of-truth convention.
- Used coding.md as ground truth throughout (e.g. `PREDICTIONS_SEED_PITCHER_CONCURRENCY` rather than the spec's `PREDICTIONS_STATCAST_CONCURRENCY` for the seeder step; 44-column feature count rather than 38; 545 unit tests rather than 396).
- `system.pipeline_steps` table absence documented under PRED-003 (matches coder's workaround of appending step metadata to `system.pipeline_runs.metadata` JSONB).
- SEC-007 noted as addressed in this branch (`expose:` vs `ports:`).
- Did not document `hit_prediction_run.ex` from the architect spec because coding.md does not list it as a created file (the context module reads `system.pipeline_runs` directly rather than via a wrapper schema).

## Files Modified

- `/Users/charmalloc/dev/sports-fanatic/.claude/worktrees/elixir-hit-predictions-pipeline/CLAUDE.md` — added `## Hit Predictions Pipeline` section; updated File Structure, Routing Conventions, Database Schemas, Valkey Caching, Python Bridge, Oban Workers, Testing Strategy, Known Issues, Common Tasks, and env vars table sections.

## Issues Found

- [LOW] The architect spec's `hit_prediction_run.ex` wrapper schema is not present in the codebase (not in coding.md's files-created list). The `Predictions.list_runs/1` function reads `system.pipeline_runs` directly. Documented as such — no wrapper schema listed.
- [LOW] `.env.example` uses `PREDICTIONS_SEED_PITCHER_CONCURRENCY` (not `PREDICTIONS_PITCHER_HISTORY_CONCURRENCY`). Documentation matches the actual env var name.

## Recommendations for Next Agent

- If a future agent adds the `system.pipeline_steps` table (PRED-003), update the Database Schemas table list and remove the workaround note.
- When the scouting pipeline is migrated off `search_player_multi/1` and `classify_content/2` (PRED-002), remove those functions from `python_bridge.ex` and update the Python Bridge section here.
- If the admin cron/concurrency UI inputs are implemented (PRED-001), add the corresponding `AdminLive` events to the Predictions tab events table.
