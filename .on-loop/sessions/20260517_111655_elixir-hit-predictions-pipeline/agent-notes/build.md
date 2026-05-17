# Build Agent Notes

## Summary

Ran all build verification checks against the elixir-hit-predictions-pipeline worktree.
No files were modified. All checks passed.

## Decisions

- No Makefile added — the project uses Mix tasks exclusively and the existing CI covers all targets. Adding one would be redundant.
- No CI changes needed — `.github/workflows/ci.yml` already runs `mix format --check-formatted`, `mix compile --force --warnings-as-errors`, `mix credo --strict`, `mix test`, `mix deps.audit`, and Python bridge `ruff` + `pytest`. The new `inference.py` file lives under `python_bridge/src/api/` which is exactly what the `ruff check src/` step targets.
- No pyproject.toml exists; the project uses `python_bridge/requirements.txt` directly. `scikit-learn==1.5.1` is already pinned there. No change needed.

## Files Modified

None.

## CI Pipeline

- Triggers: push to `main` or `on-loop/**`; all PRs targeting `main`
- Steps (from `.github/workflows/ci.yml`):
  1. `elixir-quality` — format check, compile (warnings-as-errors), credo strict
  2. `elixir-test` — `mix test --exclude python_bridge_required` (with Postgres + Valkey services)
  3. `elixir-security` — `mix deps.audit`
  4. `python-bridge` — `ruff check src/`, `ruff format --check src/`, `pytest tests/` (guarded by directory existence check)
- Estimated duration: ~4-5 minutes (Elixir jobs are parallelized; Python job runs independently)

## Results

| Check | Result |
|-------|--------|
| `mix format --check-formatted` | PASS (exit 0, no output) |
| `mix compile --warnings-as-errors` | PASS (exit 0, no output — already compiled) |
| `mix test.unit` | PASS — 545 tests, 0 failures |
| `mix deps.get` | PASS — no-op, all dependencies unchanged |
| `docker compose config` | PASS — YAML valid; new prediction env vars (`OPENMETEO_API_KEY`, `PREDICTIONS_CONCURRENCY`, `PREDICTIONS_CRON_OVERRIDE`, and 6 more step-level concurrency vars) present on `web` service |
| Dockerfile (Elixir) | PASS — `elixir:1.17-otp-27-slim` base, multi-stage build, no syntax issues |
| Dockerfile (python_bridge) | PASS — `python:3.12-slim` base, no syntax issues |
| `python_bridge/requirements.txt` scikit-learn | PASS — `scikit-learn==1.5.1` already present |
| CI workflow coverage of `inference.py` | PASS — `ruff check src/` covers the new file |

## Issues Found

- [INFO] `docker compose config` emits warnings for unset vars (`ANTHROPIC_API_KEY`, `EXA_API_KEY`, `OPENMETEO_API_KEY`, etc.) — expected in a local env without `.env`. These are all documented in `.env.example`.
- [INFO] Two compiler warnings surface in `test/sports_fanatic_web/controllers/lineup_html_test.exs` (default values for optional args never used). These are pre-existing test-file warnings and do not affect production compilation.

## Recommendations for Next Agent

- The `PREDICTIONS_CRON_OVERRIDE` env var is passed through to the web service but its handling in `runtime.exs` should be confirmed by the reviewer (verify it actually overrides the Oban crontab entry).
- Consider adding `OPENMETEO_API_KEY` to the CI `elixir-test` job env block (currently absent); the circuit breaker pattern means tests won't fail without it, but it is worth noting.
