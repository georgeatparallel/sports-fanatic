defmodule SportsFanatic.Predictions.Progress do
  @moduledoc """
  Streaming progress event sink for the hit-predictions pipeline.

  ## Contract

  Every public function is **fire-and-forget**: any DB or PubSub error is
  rescued and logged at `:warning` — calls never raise. This guarantees the
  pipeline itself cannot fail because progress reporting failed (e.g. the
  `system.pipeline_run_events` table not yet migrated on a fresh deploy).

  When `run_id` is `nil`, every function no-ops.

  Events are also broadcast on Phoenix.PubSub:

  - `"predictions:pipeline:<run_id>"` — fine-grained subscription
  - `"predictions:pipeline:all"` — fan-in topic for the admin UI

  Per-run monotonic sequence numbers come from the ETS table
  `:predictions_progress_seq` (started in `SportsFanatic.Application`).

  ## Security

  Payloads are sanitised before persistence:

  - nil-valued keys are stripped (keeps jsonb small)
  - `endpoint` values are scrubbed of `?key=`/`?apikey=` query params
  - `error` strings are truncated to 4 KB
  """

  alias Phoenix.PubSub
  alias SportsFanatic.Predictions.PipelineRunEvent
  alias SportsFanatic.Repo

  require Logger

  @counter_table :predictions_progress_seq
  @topic_prefix "predictions:pipeline:"
  @all_topic "predictions:pipeline:all"
  @max_error_bytes 4_096

  @type run_id :: binary() | nil
  @type step :: atom() | String.t()
  @type kind :: :started | :item | :completed | :failed

  # -- Public API ------------------------------------------------------------

  @doc "Marks a run as started; broadcasts `:run_started` and inserts a row."
  @spec start_run(run_id(), keyword()) :: :ok
  def start_run(nil, _opts), do: :ok

  def start_run(run_id, opts) when is_binary(run_id) do
    payload =
      %{
        run_kind: opts[:run_kind] && to_string(opts[:run_kind]),
        date: opts[:date] && Date.to_iso8601(opts[:date]),
        seed_from: opts[:seed_from] && Date.to_iso8601(opts[:seed_from]),
        seed_through: opts[:seed_through] && Date.to_iso8601(opts[:seed_through]),
        note: opts[:note]
      }
      |> sanitize_payload()

    write_event(run_id, :run, :started, payload)

    broadcast(run_id, %{
      kind: :run_started,
      run_id: run_id,
      run_kind: opts[:run_kind] || :daily,
      payload: payload
    })

    :ok
  end

  @doc "Records that a pipeline step has started."
  @spec step_started(run_id(), step(), keyword()) :: :ok
  def step_started(nil, _step, _opts), do: :ok

  def step_started(run_id, step, opts) when is_binary(run_id) do
    step = step_name(step)

    payload =
      %{total: opts[:total], note: opts[:note]}
      |> sanitize_payload()

    write_event(run_id, step, :started, payload)
    broadcast_step_event(run_id, step, :started, payload, opts)
    :ok
  end

  @doc """
  Records progress within a step. `processed` is the 1-based item index.

  Pass `:every` to throttle inserts — e.g. `every: 50` writes one event per
  50 items but always writes the first and any explicitly forced index.
  """
  @spec item_progress(run_id(), step(), non_neg_integer(), keyword()) :: :ok
  def item_progress(nil, _step, _processed, _opts), do: :ok

  def item_progress(run_id, step, processed, opts) when is_binary(run_id) do
    every = opts[:every] || 1

    if should_record?(processed, every, opts[:total]) do
      step = step_name(step)

      payload =
        %{
          processed: processed,
          total: opts[:total],
          current_item: opts[:current_item],
          item_id: opts[:item_id],
          elapsed_ms: opts[:elapsed_ms]
        }
        |> sanitize_payload()

      write_event(run_id, step, :item, payload)
      broadcast_step_event(run_id, step, :item, payload, opts)
    end

    :ok
  end

  @doc "Records a successful step completion."
  @spec step_completed(run_id(), step(), keyword()) :: :ok
  def step_completed(nil, _step, _opts), do: :ok

  def step_completed(run_id, step, opts) when is_binary(run_id) do
    step = step_name(step)

    payload =
      %{
        processed: opts[:processed],
        total: opts[:total],
        elapsed_ms: opts[:elapsed_ms],
        note: opts[:note]
      }
      |> sanitize_payload()

    write_event(run_id, step, :completed, payload)
    broadcast_step_event(run_id, step, :completed, payload, opts)
    :ok
  end

  @doc "Records a step failure with rich context."
  @spec step_failed(run_id(), step(), term(), keyword()) :: :ok
  def step_failed(nil, _step, _error, _opts), do: :ok

  def step_failed(run_id, step, error, opts) when is_binary(run_id) do
    step = step_name(step)

    payload =
      %{
        processed: opts[:processed],
        total: opts[:total],
        current_item: opts[:current_item],
        item_id: opts[:item_id],
        endpoint: scrub_endpoint(opts[:endpoint]),
        http_status: opts[:http_status],
        error: truncate_error(inspect(error))
      }
      |> sanitize_payload()

    write_event(run_id, step, :failed, payload)
    broadcast_step_event(run_id, step, :failed, payload, opts)
    :ok
  end

  @doc "Records overall run completion."
  @spec run_completed(run_id(), keyword()) :: :ok
  def run_completed(nil, _opts), do: :ok

  def run_completed(run_id, opts) when is_binary(run_id) do
    payload =
      %{processed: opts[:processed], note: opts[:note]}
      |> sanitize_payload()

    write_event(run_id, :run, :completed, payload)

    broadcast(run_id, %{
      kind: :run_completed,
      run_id: run_id,
      payload: payload
    })

    cleanup_counter(run_id)
    :ok
  end

  @doc "Records overall run failure."
  @spec run_failed(run_id(), term(), keyword()) :: :ok
  def run_failed(nil, _error, _opts), do: :ok

  def run_failed(run_id, error, opts) when is_binary(run_id) do
    payload =
      %{
        step: opts[:step] && step_name(opts[:step]),
        current_item: opts[:current_item],
        endpoint: scrub_endpoint(opts[:endpoint]),
        http_status: opts[:http_status],
        error: truncate_error(inspect(error))
      }
      |> sanitize_payload()

    write_event(run_id, :run, :failed, payload)

    broadcast(run_id, %{
      kind: :run_failed,
      run_id: run_id,
      payload: payload
    })

    cleanup_counter(run_id)
    :ok
  end

  @doc """
  Sets `system.pipeline_runs.current_step` so a re-mount of the admin UI
  can show the panel without waiting for the next live event.
  """
  @spec mark_current_step(run_id(), step()) :: :ok
  def mark_current_step(nil, _step), do: :ok

  def mark_current_step(run_id, step) when is_binary(run_id) do
    step = step_name(step)

    safe_db(fn ->
      Repo.query!(
        """
        UPDATE system.pipeline_runs
           SET current_step = $2, updated_at = NOW()
         WHERE id = $1
        """,
        [run_id, step]
      )
    end)

    :ok
  end

  @doc """
  Merges `data` into `system.pipeline_runs.checkpoint` jsonb. Caller passes
  the *whole* desired checkpoint shape (we overwrite, not deep-merge).
  """
  @spec checkpoint(run_id(), map()) :: :ok
  def checkpoint(nil, _data), do: :ok

  def checkpoint(run_id, data) when is_binary(run_id) and is_map(data) do
    safe_db(fn ->
      Repo.query!(
        """
        UPDATE system.pipeline_runs
           SET checkpoint = $2::jsonb, updated_at = NOW()
         WHERE id = $1
        """,
        [run_id, data]
      )
    end)

    :ok
  end

  # -- Internals -------------------------------------------------------------

  defp should_record?(_processed, 1, _total), do: true

  defp should_record?(processed, every, total) when is_integer(every) and every > 1 do
    cond do
      processed == 1 -> true
      rem(processed, every) == 0 -> true
      is_integer(total) and processed >= total -> true
      true -> false
    end
  end

  defp should_record?(_, _, _), do: true

  defp step_name(s) when is_atom(s), do: Atom.to_string(s)
  defp step_name(s) when is_binary(s), do: s
  defp step_name(other), do: inspect(other)

  defp next_seq(run_id) do
    :ets.update_counter(@counter_table, run_id, {2, 1}, {run_id, 0})
  rescue
    ArgumentError ->
      # Counter table missing — return a non-zero number derived from the
      # monotonic clock so events still order deterministically per process.
      System.unique_integer([:positive, :monotonic])
  end

  defp cleanup_counter(run_id) do
    :ets.delete(@counter_table, run_id)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp write_event(run_id, step, kind, payload) do
    seq = next_seq(run_id)

    safe_db(fn ->
      Repo.insert(%PipelineRunEvent{
        pipeline_run_id: run_id,
        step: step_name(step),
        kind: Atom.to_string(kind),
        seq: seq,
        payload: payload,
        inserted_at: DateTime.utc_now()
      })
    end)

    seq
  end

  defp broadcast_step_event(run_id, step, kind, payload, opts) do
    run_kind = opts[:run_kind]

    msg =
      {:predictions_pipeline_event,
       %{
         run_id: run_id,
         run_kind: run_kind,
         step: step,
         kind: kind,
         inserted_at: DateTime.utc_now(),
         payload: payload
       }}

    safe_broadcast(@topic_prefix <> run_id, msg)
    safe_broadcast(@all_topic, msg)
  end

  defp broadcast(run_id, %{kind: kind} = data) do
    msg = {:predictions_pipeline_event, Map.put(data, :inserted_at, DateTime.utc_now())}
    safe_broadcast(@topic_prefix <> run_id, msg)
    safe_broadcast(@all_topic, msg)
    _ = kind
    :ok
  end

  defp safe_broadcast(topic, msg) do
    PubSub.broadcast(SportsFanatic.PubSub, topic, msg)
  rescue
    e ->
      Logger.warning("Progress PubSub broadcast failed: #{inspect(e)}")
      :ok
  end

  defp safe_db(fun) do
    fun.()
  rescue
    e in Postgrex.Error ->
      Logger.warning("Progress DB write failed: #{inspect(e.postgres && e.postgres[:code])}")

      :ok

    e in DBConnection.ConnectionError ->
      Logger.warning("Progress DB connection error: #{inspect(e.message)}")
      :ok

    e in [ArgumentError, FunctionClauseError] ->
      Logger.warning("Progress payload error: #{inspect(e)}")
      :ok

    e in Ecto.ChangeError ->
      # Raised when a field value (e.g. pipeline_run_id) does not match the
      # expected Ecto type. Caught here so Progress calls don't crash when
      # called with a non-UUID run_id (e.g. in unit tests or pre-migration).
      Logger.warning("Progress schema error: #{inspect(e.message)}")
      :ok

    e ->
      # Catch-all for other unexpected DB / schema errors (e.g. Ecto.Query,
      # Ecto.InvalidChangesetError). Progress must never crash the pipeline.
      Logger.warning(
        "Progress unexpected error: #{inspect(e.__struct__)}: #{inspect(Exception.message(e))}"
      )

      :ok
  catch
    :exit, reason ->
      Logger.warning("Progress DB exit: #{inspect(reason)}")
      :ok
  end

  @doc false
  @spec sanitize_payload(map()) :: map()
  def sanitize_payload(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp truncate_error(s) when is_binary(s) do
    if byte_size(s) > @max_error_bytes do
      binary_part(s, 0, @max_error_bytes) <> "...[truncated]"
    else
      s
    end
  end

  defp truncate_error(other), do: inspect(other)

  # Strip query-param secrets (apikey, key, token) from URLs so we never
  # persist them to jsonb. Preserves the path + other params.
  @doc false
  @spec scrub_endpoint(String.t() | nil) :: String.t() | nil
  def scrub_endpoint(nil), do: nil

  def scrub_endpoint(url) when is_binary(url) do
    case String.split(url, "?", parts: 2) do
      [_only] ->
        url

      [base, qs] ->
        scrubbed =
          qs
          |> String.split("&")
          |> Enum.reject(fn part ->
            name = part |> String.split("=", parts: 2) |> List.first() |> to_string()

            name_lc = String.downcase(name)
            name_lc in ~w(apikey api_key key token access_token secret password)
          end)
          |> Enum.join("&")

        if scrubbed == "" do
          base
        else
          base <> "?" <> scrubbed
        end
    end
  end

  def scrub_endpoint(other), do: inspect(other)
end
