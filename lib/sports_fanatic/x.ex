defmodule SportsFanatic.X do
  @moduledoc """
  X (Twitter) v2 API client + posting/engagement business logic.

  Wraps OAuth2 user-context flows via `Req`. All write calls flow through:

    1. `SpendLedger.budget_remaining?/0` (hard daily cap)
    2. `X.CircuitBreaker.check/0`
    3. `sanitize_and_validate/1` (NFC, control chars, ≤ 280 graphemes,
       URL-in-body rejection)
    4. `refresh_if_needed/0` (re-encrypt and store)
    5. `Req.post/2` against `https://api.x.com/2/tweets`
    6. `SpendLedger.record!/1` (audit log + cost accounting)

  Reads do not consume the spend ledger because X read endpoints are free.

  Sanitization, sanitizer rejection of URLs in main bodies, and audit
  logging are part of the public contract.
  """

  require Logger
  import Ecto.Query

  alias SportsFanatic.Repo
  alias SportsFanatic.X
  alias SportsFanatic.X.{CircuitBreaker, Credentials, SpendLedger, TokenVault}

  @api_base "https://api.x.com/2"
  @max_chars 280
  @text_cost_mills 15
  @url_cost_mills 200

  # ── Public API ─────────────────────────────────────────────

  @doc """
  Returns the authorize URL for the OAuth 2.0 PKCE flow. Caller stores the
  verifier in the session and supplies it again to `exchange_code/2`.
  """
  @spec authorize_url(state :: String.t(), verifier :: String.t()) :: String.t()
  def authorize_url(state, verifier) do
    challenge = pkce_challenge(verifier)
    cfg = config!()

    params = %{
      response_type: "code",
      client_id: cfg[:client_id] || "",
      redirect_uri: cfg[:redirect_uri] || "",
      scope: "tweet.read tweet.write users.read offline.access",
      state: state,
      code_challenge: challenge,
      code_challenge_method: "S256"
    }

    "https://x.com/i/oauth2/authorize?" <> URI.encode_query(params)
  end

  @doc """
  Generates a fresh PKCE verifier — 64 bytes of URL-safe base64.
  """
  @spec generate_verifier() :: String.t()
  def generate_verifier do
    :crypto.strong_rand_bytes(48) |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates a fresh random `state` parameter for CSRF protection.
  """
  @spec generate_state() :: String.t()
  def generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Exchanges an authorization code for tokens, encrypts them via
  `TokenVault`, and upserts the singleton credentials row.
  """
  @spec exchange_code(code :: String.t(), verifier :: String.t()) ::
          {:ok, Credentials.t()} | {:error, term()}
  def exchange_code(code, verifier) when is_binary(code) and is_binary(verifier) do
    cfg = config!()

    body =
      %{
        code: code,
        grant_type: "authorization_code",
        client_id: cfg[:client_id] || "",
        redirect_uri: cfg[:redirect_uri] || "",
        code_verifier: verifier
      }

    case Req.post("https://api.x.com/2/oauth2/token",
           form: body,
           auth: {:basic, "#{cfg[:client_id]}:#{cfg[:client_secret]}"},
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: %{} = resp}} ->
        store_tokens(resp)

      {:ok, %{status: status, body: resp}} ->
        Logger.error("X exchange_code failed: status=#{status}")
        {:error, {status, resp}}

      {:error, reason} ->
        Logger.error("X exchange_code transport error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Refreshes the access token if it expires within 5 minutes. Otherwise
  returns the current credentials unchanged.
  """
  @spec refresh_if_needed() :: {:ok, Credentials.t()} | {:error, term()}
  def refresh_if_needed do
    case current_credentials() do
      {:ok, creds} ->
        if needs_refresh?(creds), do: do_refresh(creds), else: {:ok, creds}

      error ->
        error
    end
  end

  @doc """
  Returns the singleton credentials row with virtual `:access_token` and
  `:refresh_token` populated by decrypting via `TokenVault`. When the
  credentials are missing or the vault key is misconfigured, returns
  `{:error, :missing}` or `{:error, :missing_key}`.
  """
  @spec current_credentials() ::
          {:ok, Credentials.t()} | {:error, :missing | :missing_key | term()}
  def current_credentials do
    case Repo.one(from c in Credentials, limit: 1) do
      nil ->
        {:error, :missing}

      %Credentials{} = creds ->
        with {:ok, access} <-
               TokenVault.decrypt(creds.access_token_ciphertext, creds.access_token_iv),
             {:ok, refresh} <-
               TokenVault.decrypt(creds.refresh_token_ciphertext, creds.refresh_token_iv) do
          {:ok, %{creds | access_token: access, refresh_token: refresh}}
        end
    end
  end

  @doc """
  Posts a tweet through the full safety funnel.

  Options:
  - `:in_reply_to` — String tweet id; required for self-reply or reply
  - `:actor` — String, default `"system"`; "joshua:{ts}" or "watcher"
  - `:allow_url` — boolean, default false. When false, any URL in body
    causes `{:error, :url_in_body}`. The self-reply path passes `true`.
  """
  @spec post_tweet(body :: String.t(), opts :: keyword()) ::
          {:ok, %{tweet_id: String.t(), cost_mills: integer(), had_url: boolean()}}
          | {:error, term()}
  def post_tweet(body, opts \\ []) when is_binary(body) do
    allow_url = Keyword.get(opts, :allow_url, false)
    actor = Keyword.get(opts, :actor, "system") |> String.slice(0, 100)
    in_reply_to = Keyword.get(opts, :in_reply_to)

    started = System.monotonic_time(:millisecond)

    with :ok <- ensure_budget(),
         :ok <- ensure_circuit_closed(),
         {:ok, sanitized, had_url} <- sanitize_and_validate(body, allow_url: allow_url),
         {:ok, creds} <- refresh_if_needed(),
         {:ok, tweet_id, http_status} <- do_post(sanitized, creds, in_reply_to) do
      duration_ms = System.monotonic_time(:millisecond) - started
      cost = if had_url, do: @url_cost_mills, else: @text_cost_mills

      SpendLedger.record!(
        endpoint: "/2/tweets",
        method: "POST",
        http_status: http_status,
        tweet_id: tweet_id,
        had_url: had_url,
        cost_mills: cost,
        actor: actor,
        duration_ms: duration_ms
      )

      CircuitBreaker.record_success()

      {:ok, %{tweet_id: tweet_id, cost_mills: cost, had_url: had_url}}
    else
      {:error, reason} = err ->
        log_failure(reason, actor, started)
        err
    end
  end

  @doc """
  Reads metrics and replies for a tweet. Free endpoint; no spend.
  """
  @spec fetch_metrics_and_replies(tweet_id :: String.t()) ::
          {:ok, %{metrics: map(), replies: [map()]}} | {:error, term()}
  def fetch_metrics_and_replies(tweet_id) when is_binary(tweet_id) do
    with {:ok, creds} <- refresh_if_needed(),
         {:ok, metrics} <-
           get(@api_base <> "/tweets/#{tweet_id}", creds, %{"tweet.fields" => "public_metrics"}),
         {:ok, replies} <- get(@api_base <> "/tweets/#{tweet_id}/replies", creds, %{}) do
      {:ok, %{metrics: Map.get(metrics, "data", %{}), replies: Map.get(replies, "data", [])}}
    end
  end

  @doc """
  Fetches a watched account's tweets newer than the given DateTime cutoff.
  Free read endpoint; no spend.
  """
  @spec get_user_recent_tweets(handle :: String.t(), since :: DateTime.t() | nil) ::
          {:ok, [map()]} | {:error, term()}
  def get_user_recent_tweets(handle, since \\ nil) when is_binary(handle) do
    with {:ok, %{"id" => user_id}} <- lookup_user(handle),
         {:ok, creds} <- refresh_if_needed() do
      params =
        %{"max_results" => 10}
        |> maybe_put_start_time(since)

      case get(@api_base <> "/users/#{user_id}/tweets", creds, params) do
        {:ok, %{"data" => data}} when is_list(data) -> {:ok, data}
        {:ok, _} -> {:ok, []}
        err -> err
      end
    end
  end

  defp maybe_put_start_time(params, nil), do: params

  defp maybe_put_start_time(params, %DateTime{} = since) do
    Map.put(params, "start_time", DateTime.to_iso8601(since))
  end

  @doc """
  Looks up a user by handle (strips leading '@').
  """
  @spec lookup_user(handle :: String.t()) :: {:ok, map()} | {:error, term()}
  def lookup_user(handle) when is_binary(handle) do
    normalized = String.replace_prefix(handle, "@", "")

    with {:ok, creds} <- refresh_if_needed(),
         {:ok, %{"data" => data}} <-
           get(@api_base <> "/users/by/username/#{normalized}", creds, %{}) do
      {:ok, data}
    else
      {:ok, body} -> {:error, {:unexpected_response, body}}
      err -> err
    end
  end

  @doc """
  Sanitizes a tweet body and validates against the X v2 rules.

  Performs, in order:
    1. Removes control characters except `\\n`
    2. NFC-normalizes Unicode
    3. Rejects when length > 280 graphemes
    4. `HtmlSanitizeEx.strip_tags/1`
    5. Detects http(s) URLs; rejects when `:allow_url` is false

  Returns `{:ok, sanitized, had_url?}` or `{:error, atom}`.
  """
  @spec sanitize_and_validate(String.t(), keyword()) ::
          {:ok, String.t(), boolean()}
          | {:error, :empty | :too_long | :url_in_body | :invalid_unicode}
  def sanitize_and_validate(body, opts \\ []) when is_binary(body) do
    allow_url = Keyword.get(opts, :allow_url, false)

    with {:ok, no_ctrl} <- strip_control(body),
         {:ok, nfc} <- nfc(no_ctrl),
         stripped <- HtmlSanitizeEx.strip_tags(nfc) |> String.trim(),
         :ok <- ensure_non_empty(stripped),
         :ok <- ensure_length(stripped),
         {:ok, had_url} <- check_url(stripped, allow_url) do
      {:ok, stripped, had_url}
    end
  end

  @doc "Daily spend in mills (delegates to SpendLedger)."
  defdelegate today_mills(), to: SpendLedger

  @doc "Configured daily cap in mills (delegates to SpendLedger)."
  defdelegate daily_cap_mills(), to: SpendLedger

  @doc "Returns true when today's mills < daily cap."
  defdelegate budget_remaining?(), to: SpendLedger

  @doc """
  Transitions an existing post row from `pending` to `approved`. Used by the
  AdminLive approval queue. Returns the updated post.
  """
  def approve_post(post_id) when is_binary(post_id) do
    Repo.update_all(
      from(p in X.Post, where: p.id == ^post_id and p.status == "pending"),
      set: [status: "approved", updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )
  end

  # ── private ─────────────────────────────────────────────────

  defp config!, do: Application.get_env(:sports_fanatic, :x_agent, [])

  defp ensure_budget do
    if budget_remaining?() do
      :ok
    else
      maybe_broadcast_cap()
      {:error, :budget_exceeded}
    end
  end

  defp maybe_broadcast_cap do
    if Process.whereis(SportsFanatic.PubSub) do
      Phoenix.PubSub.broadcast(
        SportsFanatic.PubSub,
        "admin:x_agent",
        {:budget_exceeded, today_mills()}
      )
    end
  rescue
    _ -> :ok
  end

  defp ensure_circuit_closed do
    case ensure_breaker_alive() do
      :ok ->
        case CircuitBreaker.check() do
          :open -> {:error, :circuit_open}
          _ -> :ok
        end

      :no_breaker ->
        :ok
    end
  end

  defp ensure_breaker_alive do
    if Process.whereis(CircuitBreaker), do: :ok, else: :no_breaker
  end

  defp pkce_challenge(verifier) do
    :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
  end

  defp strip_control(body) do
    cleaned = String.replace(body, ~r/[\x00-\x09\x0B-\x1F\x7F]/u, "")
    {:ok, cleaned}
  end

  defp nfc(body) do
    case :unicode.characters_to_nfc_binary(body) do
      bin when is_binary(bin) -> {:ok, bin}
      _ -> {:error, :invalid_unicode}
    end
  end

  defp ensure_non_empty(""), do: {:error, :empty}
  defp ensure_non_empty(_), do: :ok

  defp ensure_length(body) do
    if String.length(body) <= @max_chars, do: :ok, else: {:error, :too_long}
  end

  defp check_url(body, allow_url) do
    had_url? = String.contains?(body, "http://") or String.contains?(body, "https://")

    if had_url? and not allow_url do
      {:error, :url_in_body}
    else
      {:ok, had_url?}
    end
  end

  defp needs_refresh?(%Credentials{expires_at: %DateTime{} = exp}) do
    DateTime.diff(exp, DateTime.utc_now()) < 300
  end

  defp needs_refresh?(_), do: true

  defp do_refresh(%Credentials{refresh_token: refresh} = creds) when is_binary(refresh) do
    cfg = config!()

    body = %{
      grant_type: "refresh_token",
      refresh_token: refresh,
      client_id: cfg[:client_id] || ""
    }

    case Req.post("https://api.x.com/2/oauth2/token",
           form: body,
           auth: {:basic, "#{cfg[:client_id]}:#{cfg[:client_secret]}"},
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: resp}} ->
        store_tokens(resp, creds)

      {:ok, %{status: status, body: resp}} ->
        {:error, {status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_refresh(_), do: {:error, :missing_refresh_token}

  defp store_tokens(resp, existing \\ nil) do
    with %{"access_token" => access, "refresh_token" => refresh, "expires_in" => expires_in} <-
           resp,
         {:ok, %{ciphertext: a_ct, iv: a_iv}} <- TokenVault.encrypt(access),
         {:ok, %{ciphertext: r_ct, iv: r_iv}} <- TokenVault.encrypt(refresh) do
      expires_at =
        DateTime.utc_now()
        |> DateTime.add(expires_in, :second)
        |> DateTime.truncate(:second)

      attrs = %{
        account_handle:
          (existing && existing.account_handle) || Map.get(resp, "screen_name") || "x_account",
        account_id: (existing && existing.account_id) || Map.get(resp, "user_id") || "0",
        access_token_ciphertext: a_ct,
        refresh_token_ciphertext: r_ct,
        access_token_iv: a_iv,
        refresh_token_iv: r_iv,
        expires_at: expires_at,
        scope: Map.get(resp, "scope", "tweet.read tweet.write users.read offline.access")
      }

      case existing do
        nil ->
          %Credentials{}
          |> Credentials.changeset(attrs)
          |> Repo.insert(
            on_conflict: {:replace_all_except, [:id, :inserted_at, :singleton]},
            conflict_target: [:singleton]
          )

        %Credentials{} ->
          existing
          |> Credentials.changeset(attrs)
          |> Repo.update()
      end
      |> case do
        {:ok, updated} ->
          {:ok,
           %{
             updated
             | access_token: access,
               refresh_token: refresh
           }}

        err ->
          err
      end
    else
      {:error, _} = err -> err
      _ -> {:error, :unexpected_token_response}
    end
  end

  defp do_post(text, %Credentials{access_token: token}, in_reply_to) when is_binary(token) do
    body =
      case in_reply_to do
        nil -> %{text: text}
        id when is_binary(id) -> %{text: text, reply: %{in_reply_to_tweet_id: id}}
      end

    case Req.post(@api_base <> "/tweets",
           json: body,
           auth: {:bearer, token},
           receive_timeout: 15_000
         ) do
      {:ok, %{status: status, body: %{"data" => %{"id" => id}}}} when status in 200..299 ->
        {:ok, id, status}

      {:ok, %{status: status, body: resp}} ->
        CircuitBreaker.record_failure()
        {:error, {status, resp}}

      {:error, reason} ->
        CircuitBreaker.record_failure()
        {:error, reason}
    end
  end

  defp do_post(_, _, _), do: {:error, :missing_access_token}

  defp get(url, %Credentials{access_token: token}, query) when is_binary(token) do
    case Req.get(url, auth: {:bearer, token}, params: query, receive_timeout: 15_000) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        {:ok, resp}

      {:ok, %{status: status, body: resp}} ->
        CircuitBreaker.record_failure()
        {:error, {status, resp}}

      {:error, reason} ->
        CircuitBreaker.record_failure()
        {:error, reason}
    end
  end

  defp get(_, _, _), do: {:error, :missing_access_token}

  defp log_failure(reason, actor, started) do
    duration_ms = System.monotonic_time(:millisecond) - started

    # Never log token contents; reason is sanitized by SpendLedger.
    try do
      SpendLedger.record!(
        endpoint: "/2/tweets",
        method: "POST",
        http_status: nil,
        had_url: false,
        cost_mills: 0,
        actor: actor,
        error_message: inspect_reason(reason),
        duration_ms: duration_ms
      )
    rescue
      e -> Logger.error("X.post_tweet ledger record failed: #{inspect(e)}")
    end
  end

  # Always return a generic safe string — never the raw tuple, which may
  # contain bearer tokens in upstream error responses.
  defp inspect_reason(:budget_exceeded), do: "budget_exceeded"
  defp inspect_reason(:circuit_open), do: "circuit_open"
  defp inspect_reason(:url_in_body), do: "url_in_body"
  defp inspect_reason(:too_long), do: "too_long"
  defp inspect_reason(:empty), do: "empty"
  defp inspect_reason(:invalid_unicode), do: "invalid_unicode"
  defp inspect_reason(:missing), do: "missing_credentials"
  defp inspect_reason(:missing_key), do: "missing_encryption_key"
  defp inspect_reason(:missing_access_token), do: "missing_access_token"
  defp inspect_reason({status, _resp}) when is_integer(status), do: "http_#{status}"
  defp inspect_reason(_), do: "unknown_error"
end
