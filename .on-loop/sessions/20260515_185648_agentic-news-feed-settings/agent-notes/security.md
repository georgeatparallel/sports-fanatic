# Security Agent Notes

## Summary

The Agentic News Feed feature introduces a user-facing LLM-powered command system with natural language input, async background processing, and a new Python Bridge endpoint. Overall security posture is **acceptable with caveats**. No CRITICAL findings. Two HIGH findings require remediation. The implementation correctly uses Ecto parameterized queries throughout, properly gates agent commands behind authentication, enforces user isolation on all CRUD operations, avoids `raw/1` in templates, and includes prompt injection guardrails in the LLM system prompt. However, there are gaps in error information leakage, missing rate limiting per the spec, and a status validation defect that could cause data integrity issues.

## OWASP Top 10 Review

### A01: Broken Access Control
- [PASS] All `Agents` context functions that operate on user data include `user_id` scoping in WHERE clauses (`get_setting!/2`, `delete_setting/2`, `list_user_settings/1`, `clear_user_settings/1`).
- [PASS] All LiveView `handle_event` callbacks check `socket.assigns.current_user` before processing agent commands.
- [PASS] The `delete_setting` event uses `Agents.delete_setting(setting_id, user.id)` which scopes the delete to the authenticated user, preventing IDOR.
- [PASS] Admin tab is within `AdminLive` which is gated by the `:require_admin` live_session in the router.
- [INFO] `get_setting/1` (no user_id) exists for worker use. Acceptable since it is only called from `ParseSettingWorker` which receives the `setting_id` from the Oban job args, not from user input.

### A02: Cryptographic Failures
- [PASS] No new cryptographic operations introduced. Existing session token mechanism is reused.

### A03: Injection
- [PASS] All database queries use Ecto parameterized queries. No string interpolation in SQL.
- [PASS] The ILIKE patterns in `RunNewsAgentsWorker.apply_player_filter/2` properly escape `%` and `_` via `sanitize_like/1`.
- [PASS] Template does not use `raw/1` anywhere -- all user content (`raw_prompt`, `interpretation`, `error_message`, `explanation`, domain tags, player/team names) is rendered via standard HEEx interpolation which auto-escapes HTML.
- [PASS] The `fragment("? && ?", n.domain_tags, ^tags)` in `apply_domain_tag_filter` uses parameterized fragment, not string interpolation.

### A04: Insecure Design
- [FINDING - HIGH] Missing hourly rate limit. See SEC-NEW-002 below.
- [FINDING - MEDIUM] Status validation gap in `update_changeset`. See SEC-NEW-003 below.

### A05: Security Misconfiguration
- [INFO] Python Bridge `/docs` endpoint is conditionally enabled based on `settings.debug`. Ensure `debug=False` in production.
- [PASS] The `/agents/parse-setting` endpoint enforces 500-char max at both the Pydantic model layer (`max_length=MAX_PROMPT_LENGTH`) and in the handler body.

### A06: Vulnerable Components
- [INFO] No new dependencies added in this PR (Jido deferred to Phase 2). No new CVE exposure.

### A07: Auth Failures
- [PASS] LiveView `mount/3` loads `current_user` from session token via existing `Accounts.get_user_by_session_token/1`.
- [PASS] Unauthenticated users see a disabled textarea and all event handlers return flash errors.

### A08: Data Integrity Failures
- [FINDING - MEDIUM] Status can be set to nil. See SEC-NEW-003 below.
- [PASS] Parsed criteria from the LLM is stored as JSONB via Ecto cast (not raw JSON string manipulation).

### A09: Logging Failures
- [FINDING - HIGH] Error reason from Python Bridge/LLM stored in `error_message` and displayed to user. See SEC-NEW-001 below.
- [PASS] Logger calls in workers do not log user PII (only user_id and setting_id).

### A10: SSRF
- [PASS] The `parse_setting` call goes to the internal Python Bridge only. No user-controlled URLs are fetched.
- [INFO] The `exa_query` field in parsed criteria is stored but not executed in Phase 1. When Phase 2 implements Exa search, the `exa_query` value (which comes from LLM output, not directly from user input) must be validated before use.

## STRIDE Analysis

### Command Input (NewsLive)

| Threat | Risk | Mitigation |
|--------|------|------------|
| Spoofing | LOW | Auth check via session token in mount + event handlers |
| Tampering | LOW | LiveView WebSocket is CSRF-protected by Phoenix |
| Repudiation | LOW | Settings have timestamps and user_id. No audit log but DB records provide traceability |
| Information Disclosure | MEDIUM | Error messages from LLM/Python Bridge leak to UI (SEC-NEW-001) |
| Denial of Service | MEDIUM | Missing hourly rate limit (SEC-NEW-002). Max 20 settings cap provides partial mitigation |
| Elevation of Privilege | LOW | No privilege escalation path. Agent features are available to all authenticated users |

### Python Bridge /agents/parse-setting

| Threat | Risk | Mitigation |
|--------|------|------------|
| Spoofing | LOW | Internal-only endpoint (Docker network). Not exposed to browser |
| Tampering | LOW | Input validated via Pydantic model. 500-char max enforced |
| Repudiation | LOW | Python logger records parse requests |
| Information Disclosure | LOW | Exception handler returns `str(e)` which could leak internal details, but only to the Elixir worker, not directly to users (except via error_message storage -- see SEC-NEW-001) |
| Denial of Service | LOW | Circuit breaker protects against cascading failures. Claude Haiku has its own rate limits |
| Elevation of Privilege | N/A | No auth context in Python Bridge |

### RunNewsAgentsWorker

| Threat | Risk | Mitigation |
|--------|------|------------|
| Spoofing | N/A | Backend worker, no user interaction |
| Tampering | LOW | Ecto parameterized queries, sanitize_like for ILIKE patterns |
| Repudiation | LOW | Results stored with timestamps and user/setting IDs |
| Information Disclosure | LOW | Worker logs contain user_id but no PII |
| Denial of Service | LOW | Feature flag gate. Sequential user processing with try/rescue isolation |
| Elevation of Privilege | N/A | No privilege boundaries crossed |

## Findings

### [HIGH] SEC-NEW-001: Internal Error Details Exposed to Users

- **Location**: `lib/sports_fanatic/workers/parse_setting_worker.ex:54-59`
- **Description**: When LLM parsing fails, the raw error reason is stored in the `error_message` field via `"Failed to parse setting: #{inspect(reason)}"`. This field is rendered in the template at `news_live.html.heex:282-284` as `<%= setting.error_message %>`. The `reason` value can contain internal details such as HTTP error codes, Python Bridge connection errors, stack trace fragments, or Anthropic API error responses including account/key details.
- **Impact**: Information disclosure to end users. An attacker could intentionally trigger parse failures (e.g., by submitting prompts while the Python Bridge is down) to enumerate internal infrastructure details, API error formats, or service topology.
- **Remediation**: Replace the raw error message with a user-friendly generic message. Store the detailed error in logs only:
  ```elixir
  Logger.warning("ParseSettingWorker: parse failed for setting #{setting.id}: #{inspect(reason)}")
  Agents.update_setting(setting, %{
    status: "failed",
    error_message: "Unable to parse your setting. Please try again later."
  })
  ```
- **Reference**: CWE-209 (Generation of Error Message Containing Sensitive Information), OWASP A09

### [HIGH] SEC-NEW-002: Missing Hourly Rate Limit on /settings-apply

- **Location**: `lib/sports_fanatic/agents.ex:25-35`, `lib/sports_fanatic_web/live/news_live.ex:224-261`
- **Description**: The spec (NFR-004, Security Considerations) requires "Max 5 `/settings-apply` commands per user per hour." The implementation only enforces the max-20-settings-per-user cap but has no hourly rate limit. The coding agent acknowledged this gap in their notes. Without the hourly limit, an authenticated user could rapidly create and delete settings, triggering 20 `ParseSettingWorker` Oban jobs per cycle, each making a Claude Haiku API call. Over an hour, an attacker could trigger hundreds of LLM calls by cycling create/delete.
- **Impact**: LLM cost abuse. An attacker with a valid account could rack up significant Anthropic API costs by rapidly creating settings (each triggers a parse), deleting them, and creating more. The 20-setting cap only limits concurrent settings, not throughput. At $0.001 per call, 1000 cycles/hour = $1/hour per attacker, scaling linearly with number of compromised accounts.
- **Remediation**: Add a time-windowed rate limiter in `Agents.create_setting/2`. Options:
  1. Count settings created in the last hour (including deleted ones) by querying `inserted_at > now() - 1 hour` with a separate counter or by retaining soft-deleted records.
  2. Add a simple ETS-based rate limiter keyed on `{user_id, :settings_apply}` with a 5/hour window.
  3. Use the existing Oban `unique` constraint on ParseSettingWorker to limit concurrent parses.
- **Reference**: CWE-770 (Allocation of Resources Without Limits or Throttling), OWASP A04

### [MEDIUM] SEC-NEW-003: Status Field Can Be Set to Nil via update_changeset

- **Location**: `lib/sports_fanatic/agents/news_agent_setting.ex:44-48`
- **Description**: The `update_changeset/2` does not include `validate_required(:status)`. As the testing agent identified, passing `%{status: ""}` causes Ecto to cast the empty string to `nil`, which bypasses `validate_inclusion(:status, @valid_statuses)` (because `nil` is not checked by `validate_inclusion` when the field is not required). The database CHECK constraint (`status IN ('pending', ...)`) will reject `nil` at the DB layer, but this creates a confusing error path and could cause unexpected behavior if the DB constraint is ever relaxed.
- **Impact**: Data integrity issue. A buggy caller could accidentally clear the status to nil, causing a database constraint error that surfaces as an opaque Ecto error rather than a clear validation message. Low exploitability since `update_changeset` is only called from internal workers, not from user input.
- **Remediation**: Add `validate_required([:status])` to `update_changeset/2`:
  ```elixir
  def update_changeset(setting, attrs) do
    setting
    |> cast(attrs, [:parsed_criteria, :status, :last_run_at, :last_result, :error_message])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
  end
  ```
- **Reference**: CWE-20 (Improper Input Validation)

### [MEDIUM] SEC-NEW-004: Prompt Injection Guardrails Are Best-Effort

- **Location**: `python_bridge/src/agents/parser.py:88-107`
- **Description**: The system prompt includes explicit instructions to treat user input as opaque data and ignore embedded instructions. The user input is wrapped in quotes in the user message (`"Parse the following MLB news tracking setting:\n\n\"{raw_prompt}\""`). While these are reasonable mitigations for a tool_use/structured output call, they are not foolproof. An adversarial prompt could attempt to:
  1. Manipulate the parsed criteria to set `requires_exa_search: true` with a crafted `exa_query` targeting internal services (Phase 2 risk).
  2. Inject misleading `target_players` or `target_teams` values to cause unexpected query behavior.
  3. Set artificially high `confidence` scores to make junk settings appear valid.
- **Impact**: LOW in Phase 1 (parsed criteria only affects ILIKE text matching on news_items, and Exa search is not executed). MEDIUM when Phase 2 enables Exa execution -- a crafted `exa_query` could target arbitrary external URLs. The tool_use + forced tool_choice pattern significantly reduces prompt injection surface compared to free-text completion.
- **Remediation**: 
  1. In Phase 1: Validate parsed output server-side. Reject criteria where `target_players` or `target_teams` entries exceed 100 characters. Clamp `confidence` to [0.0, 1.0]. Force `requires_exa_search` to `false` until Phase 2 is ready.
  2. In Phase 2: Validate and whitelist `exa_query` domains. Never pass `exa_query` directly to Exa without sanitization.
- **Reference**: CWE-77 (Improper Neutralization of Special Elements used in a Command), OWASP LLM01 (Prompt Injection)

### [LOW] SEC-NEW-005: PubSub Topic Uses User ID Without Additional Entropy

- **Location**: `lib/sports_fanatic_web/live/news_live.ex:46-47`, `lib/sports_fanatic/workers/parse_setting_worker.ex:67-71`
- **Description**: PubSub topics use the pattern `agent:settings:#{user_id}` and `agent:results:#{user_id}`. In Phoenix PubSub, any process that subscribes to a topic receives all messages on that topic. Since the LiveView process performs the subscription and the user_id comes from the authenticated session, a user cannot subscribe to another user's topic through the LiveView. However, if any other process (e.g., IEx console, admin tool) subscribes to these topics, it would receive user-specific data.
- **Impact**: Minimal in production. PubSub is in-process (not exposed externally). The topic pattern is standard Phoenix convention.
- **Remediation**: No action required for Phase 1. Document that PubSub topics contain user-specific data for future reference.

### [LOW] SEC-NEW-006: Float.round/2 on LLM Output Could Crash

- **Location**: `lib/sports_fanatic_web/live/news_live.html.heex:275`
- **Description**: `Float.round(confidence * 100, 0)` is called on the `confidence` value from `parsed_criteria`. If the LLM returns an integer (e.g., `1` instead of `1.0`) or a string, this will raise an `ArithmeticError` or `FunctionClauseError` in the LiveView process, crashing the user's session.
- **Impact**: Denial of service for the specific user viewing the agents tab. The LiveView will crash and attempt to reconnect, but the same data will cause the same crash. The user would need to delete the offending setting to recover.
- **Remediation**: Guard the template with a type check or use a helper function:
  ```elixir
  defp format_confidence(val) when is_float(val), do: "#{Float.round(val * 100, 0)}%"
  defp format_confidence(val) when is_integer(val), do: "#{val * 100}%"
  defp format_confidence(_), do: "N/A"
  ```
- **Reference**: CWE-20 (Improper Input Validation)

### [INFO] SEC-NEW-007: Admin "Run All Agents" Has No Confirmation Gate

- **Location**: `lib/sports_fanatic_web/live/admin_live.ex:220-228`
- **Description**: The "Run All Agents Now" button in the admin panel triggers `RunNewsAgentsWorker` without a `data-confirm` dialog. An accidental click executes agent settings for all users, consuming LLM resources.
- **Impact**: Minor operational risk. The admin panel is already gated behind `:require_admin`.
- **Remediation**: Add `data-confirm="Run all user agents now? This will consume LLM API credits."` to the button.

## Compliance Notes

- **SOC2**: Access controls are properly implemented with user isolation. Audit trail exists via database timestamps and Oban job history. Encryption in transit depends on TLS configuration (not changed by this PR).
- **PCI-DSS**: Not applicable -- no cardholder data involved in agent features.
- **NIST 800-53**: AC-3 (Access Enforcement) satisfied via user-scoped queries. SI-10 (Information Input Validation) partially satisfied -- 500-char limit enforced but hourly rate limit missing.
- **GDPR**: Agent settings contain user-generated text (raw_prompt) which could contain PII if a user types personal information. The `ON DELETE CASCADE` on `user_id` FK ensures settings are deleted when a user account is deleted, supporting right-to-erasure. No new PII collection beyond what was already possible in existing features.

## Dependency Audit

- No new runtime dependencies added in this PR (Jido deferred to Phase 2).
- Python-side: Uses existing `anthropic` SDK. No new Python dependencies added.
- No lockfile changes to audit.

## Decisions

- The prompt injection mitigation (system prompt guardrails + tool_use forced output) is adequate for Phase 1 where parsed criteria only drives ILIKE queries. Phase 2 must add server-side validation of LLM output before executing Exa searches.
- The 20-settings-per-user cap provides a coarse cost ceiling but is insufficient without the hourly rate limit. The cycling attack (create/delete/create) makes the cap easy to circumvent for LLM cost abuse.
- Template rendering is safe from XSS. All user and external content uses HEEx auto-escaping. No `raw/1` calls found in any new or modified template code.

## Recommendations for Next Agent

- **Documentation agent**: Document the security model for agent settings (user isolation, rate limits, prompt injection mitigations). Include the hourly rate limit requirement as a known gap for Phase 1.
- **Build agent**: No new security scanning configuration needed for Phase 1. When Phase 2 adds Jido, run `mix deps.audit` to check for known vulnerabilities.
- **Coding agent** (if remediation cycle triggered): Fix SEC-NEW-001 (generic error messages), SEC-NEW-002 (hourly rate limit), and SEC-NEW-003 (validate_required on status).
