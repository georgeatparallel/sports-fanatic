# Security Agent Notes — Elixir Hit-Predictions Pipeline

**Session**: 20260517_111655_elixir-hit-predictions-pipeline
**Date**: 2026-05-17
**Scope**: Only the delta in `changes.log` (predictions context, workers, LiveView, admin tab, redirect controller, external API clients, Python inference endpoint, config, docker-compose).

---

## Summary

Audited the new hit-predictions pipeline (38 added/modified files). No CRITICAL findings. One MEDIUM finding (LiveView prediction input parsing tolerates oversized floats with no clamp) and a handful of LOW hygiene items. All external HTTP requests are constructed from constants + typed integer/float path parameters; admin routes are protected by `:require_joshua`; `python-bridge` is now `expose:` (internal-only) — SEC-007 is effectively addressed in this branch. `.env` is gitignored (SEC-006 already addressed). HEEx templates render predictions via `today_hit_banner` and the LiveView card builder with default-escape (no `raw/1` on player_name, vs_team, venue_name, probable_pitcher_name, or any other AI/external string). All Ecto/PG queries use `$N` parameter binding (no string interpolation of user input). Recommendation: **PASS_WITH_TODOS**.

---

## CRITICAL findings

None.

---

## HIGH findings

None.

---

## MEDIUM findings

### [MED-PRED-001] `filter_min_prob` accepts unbounded float, returned to client unchanged
- **Location**: `lib/sports_fanatic_web/live/predictions_live.ex:68-76`
- **Description**: `handle_event("filter_min_prob", %{"min" => min}, …)` calls `Float.parse(min || "")` and assigns the raw float to `:filter_min_prob`. There is no clamp to `0.0..1.0`, no NaN/Infinity rejection, and no length cap on the incoming string before parsing. The Elixir `Float.parse/1` will not raise but the value flows back into a `value=` attribute on the input field and into `Enum.filter`. Not exploitable today (no SQL/Ecto path consumes it server-side; the filter is in-memory), but it permits arbitrary float values to round-trip through user UI state. If a future change pushes this value into a DB filter via `min_prob` it would bypass intended bounds.
- **Impact**: Defense-in-depth gap. Future regression risk if `:filter_min_prob` is wired to `Predictions.list_for_date/2`'s `:min_prob` option (which uses parameter binding so SQL is safe — but a non-finite float could break sort/comparison logic).
- **Remediation**: Clamp parsed value to `0.0..1.0`, reject non-finite (`is_float(f) and f == f and f > -1.0e15`), cap input string length to e.g. 16 bytes before parsing.
- **Reference**: CWE-20 (Improper Input Validation).

---

## LOW findings / hygiene

### [LOW-PRED-001] `OpenMeteo.fetch_forecast/4` does not validate `lat`/`lon` ranges before building URL
- **Location**: `lib/sports_fanatic/external_apis/open_meteo.ex:21-35`
- **Description**: `is_number(lat) and is_number(lon)` is the only guard; values can be any finite float. URL is then built via `URI.encode_query/1`, so injection is impossible, but a caller passing nonsense coordinates burns rate budget. Currently called only with values from `Stadiums.coordinates/1` (server-controlled), so not a runtime concern.
- **Remediation**: Add guards `lat >= -90.0 and lat <= 90.0 and lon >= -180.0 and lon <= 180.0` and return `{:error, :invalid_coords}` otherwise.
- **Reference**: CWE-20.

### [LOW-PRED-002] `MlbStats` URLs are built via string concatenation rather than `URI.encode_query/1`
- **Location**: `lib/sports_fanatic/external_apis/mlb_stats.ex:32-93`
- **Description**: All callers pass integers (game_id, player_mlb_id, season) typed via `is_integer(...)` guards or a `Date.t()` — no user-supplied string flows in unencoded except `lookup_player/1`, which correctly `URI.encode_www_form/1`s the name. SSRF is not possible because the base URL is a constant. Style nit only.
- **Remediation**: Optional — use `URI.encode_query/1` for clarity. No exploit path today.
- **Reference**: CWE-20.

### [LOW-PRED-003] Inference circuit-breaker bypass when GenServer is not started
- **Location**: `lib/sports_fanatic/predictions/inference.ex:41-54`
- **Description**: When `Process.whereis(CircuitBreaker)` is nil the request proceeds without breaker accounting. This is intentional for tests but is silent in prod — a misconfigured supervision tree would silently disable the breaker.
- **Remediation**: Log a `Logger.warning/1` once when `cb_available == false` in non-test environments. No security exploit; reliability/observability nit.
- **Reference**: CWE-754.

### [LOW-PRED-004] No timeout on overall pipeline orchestrator
- **Location**: `lib/sports_fanatic/workers/daily_hit_predictions_worker.ex:46-71`
- **Description**: Each step has its own `Task.async_stream` timeout, but the orchestrator itself has no cumulative ceiling. A degraded `/inference/hit` (no response within 120s × retries) plus 8 step retries could pin an Oban worker for many minutes. Oban's `max_attempts: 3` provides eventual termination, but no soft global timeout.
- **Remediation**: Wrap `do_run/1` in `Task.async/1` + `Task.await/2` with e.g. 15-minute global timeout; on timeout, close pipeline run as `failed`. Out of scope for this PR if NFR-001 (12 min budget) is sufficient.
- **Reference**: CWE-400 (Uncontrolled Resource Consumption).

### [LOW-PRED-005] `Predictions.run_now/1` not rate-limited per admin
- **Location**: `lib/sports_fanatic_web/live/admin_live.ex:246-254`, `lib/sports_fanatic/predictions.ex:107-113`
- **Description**: Spec called for `run_predictions_now` to be rate-limited to 1/min/admin (SEC-PRED-004). The current handler relies solely on `DailyHitPredictionsWorker`'s Oban uniqueness (`period: 3600, fields: [:worker, :args]`), which deduplicates equal args within 1 hour but does not throttle distinct `force: true` requests. An admin user clicking "Run Now" many times within an hour creates redundant `:executing` jobs (Oban dedupes equal args, so impact is bounded, but the UX/observability spec asked for an explicit limiter). Admin auth (`:require_joshua`) is in place, so this is an internal-abuse concern only.
- **Remediation**: Add a per-session or per-Joshua-user `ets`-backed token bucket (existing `JoshuaRateLimiter` pattern), or rely on Oban's `unique: [period: 60, fields: [:worker]]` for the manual-trigger path.
- **Reference**: CWE-799 (Improper Control of Interaction Frequency).

### [LOW-PRED-006] Statcast CSV parser trusts column ordering
- **Location**: `lib/sports_fanatic/external_apis/mlb_stats.ex:195-243`
- **Description**: `summarize_statcast_csv/1` finds `launch_speed` by column header (good), but the parser does not validate the row width. A malformed row from Baseball Savant (the project pulls a public, untrusted endpoint over HTTPS) can produce mis-indexed reads. `to_float(v)` is nil-safe and `Enum.reject(&is_nil/1)` filters out parse failures, so the worst case is silently degraded stats — no crash, no injection. The CSV body is never rendered to HTML.
- **Remediation**: Add `length(parts) == length(cols)` check before `Enum.at(parts, ev_idx)`.
- **Reference**: CWE-20.

### [LOW-PRED-007] `Predictions.list_runs/1` consumes raw `metadata` JSONB without sanitization for admin render
- **Location**: `lib/sports_fanatic/predictions.ex:81-103`
- **Description**: `metadata` (which contains step error strings from `inspect/1`) is rendered in the admin Predictions tab. Because errors come from internal `inspect/1` of exceptions (e.g. `Req.TransportError`), no user-controlled string flows here. Admin route is gated. HEEx escapes by default. Not exploitable; flagged only as a reminder that future error sources entering metadata must avoid PII / secrets.
- **Remediation**: Ensure `Logger`-equivalent redaction is applied if any future step writes secrets (API keys) into metadata. Today the only writers are pipeline workers under our control.
- **Reference**: CWE-209 (Information Exposure Through Error Message).

### [LOW-PRED-008] Python `/inference/hit` has no auth and trusts the JSON shape
- **Location**: `python_bridge/src/api/inference.py:54-161`
- **Description**: Endpoint listens on the Python container's `expose:8000` (Docker internal network). Any service on that network can POST. FastAPI parses input via Pydantic models with `dict[str, Any]` for row contents; a malicious payload could submit very large `training_rows`/`inference_rows` arrays — `pd.DataFrame` materialization is O(N) memory. The 25MB FastAPI default body cap bounds this, but DoS is still possible from inside the trusted Docker network.
- **Impact**: Only callable by services on the internal Docker network (currently only `web`). Not internet-exposed.
- **Remediation**: Add a row-count cap (e.g. `len(training_rows) <= 200_000`, `len(inference_rows) <= 5_000`) in `infer_hit/1` and raise `HTTPException(413)` if exceeded. Optionally add a shared-secret header check that Elixir's `Inference.score/2` sends.
- **Reference**: CWE-400, CWE-770.

---

## OWASP Top 10 Mapping (delta only)

| # | Category | Status |
|---|---|---|
| A01 Broken Access Control | OK — admin tab gated by `:require_joshua` pipeline at router; LiveView events inherit auth from the live_session. Public LiveView (`/predictions`) and player banner are read-only with public data. |
| A02 Cryptographic Failures | OK — `OpenMeteo` rejects non-HTTPS URLs (`:insecure_url` short-circuit). `MlbStats` uses `https://` constants. `Inference.score/2` calls `http://python-bridge:8000` on the Docker internal network only (acceptable inside the trust boundary). |
| A03 Injection | OK — all Ecto/PG queries use `$N` parameter binding (`Repo.query!(sql, [params])`). MLB Stats / Open-Meteo URLs built from typed integer/Date/float values; no user strings interpolated. HEEx default-escapes all rendered strings (no `raw/1`). |
| A04 Insecure Design | LOW — no global pipeline timeout (LOW-PRED-004); no admin-run rate limit (LOW-PRED-005). |
| A05 Security Misconfiguration | OK — `python-bridge` switched from `ports:` to `expose:` (SEC-007 fixed for this delta). `.env` already gitignored. |
| A06 Vulnerable Components | OK (delta) — no new Elixir deps. Python adds `sklearn`/`numpy`/`pandas` already present. |
| A07 Auth Failures | OK — no auth changes. |
| A08 Data Integrity Failures | OK — unique index `(prediction_date, player_mlb_id)` enforced; `Repo.insert_all` uses `on_conflict: {:replace_all_except, …}` with explicit `conflict_target`. |
| A09 Logging Failures | LOW — `Logger.info`/`Logger.warning` outputs are clean. No API keys logged. `inspect/1` on errors may surface internal types but not secrets. |
| A10 SSRF | OK — `OpenMeteo` URLs built from constants + typed numerics; `MlbStats` likewise. `Inference` calls a fixed internal hostname. No user-controlled URLs reach `Req.get/post`. |

---

## STRIDE Notes (high-risk surfaces only)

| Component | Threat | Mitigation Status |
|-----------|--------|-------------------|
| `/predictions` LiveView | Tampering (filter inputs) | Floats parsed defensively, but not clamped (MED-PRED-001). |
| Admin Predictions tab | EoP / DoS via Run-Now spam | `:require_joshua` + Oban uniqueness; no rate limit (LOW-PRED-005). |
| MLB Stats / Open-Meteo clients | SSRF | URLs use constant bases; numeric path params. No user URLs. |
| Python `/inference/hit` | DoS by large payload | 25MB FastAPI cap; no per-row count cap (LOW-PRED-008). |
| `mlb.hit_predictions` schema | Tampering / dup writes | Unique index + `ON CONFLICT` upsert. |

---

## Compliance Notes

- **SOC2 (CC6 access controls)**: Admin Predictions tab gated by Joshua plug — pass.
- **GDPR**: No PII added. Player names are public information.
- **NIST 800-53 SI-10 (input validation)**: Float filter not clamped (MED-PRED-001) — partial.

---

## Recommendation

**PASS_WITH_TODOS** — no CRITICAL or HIGH findings. MED-PRED-001 and LOW-PRED-005/008 should be tracked but do not block merge. SEC-007 (python-bridge port exposure) is effectively addressed in this branch's `docker-compose.yml`.

Suggested follow-up tickets:
1. Clamp `filter_min_prob` to `[0.0, 1.0]` and reject non-finite floats (MED-PRED-001).
2. Add a per-admin rate limiter on `run_predictions_now` (LOW-PRED-005).
3. Add row-count caps on `/inference/hit` request (LOW-PRED-008).
4. Add a global timeout to `DailyHitPredictionsWorker.do_run/1` (LOW-PRED-004).
