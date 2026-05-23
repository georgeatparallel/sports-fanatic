defmodule SportsFanatic.Workers.DailyHitPredictionsWorker do
  @moduledoc """
  Daily hit-prediction pipeline orchestrator. Runs at 8 AM ET via cron.

  Each step is invoked synchronously inside this single Oban job so the
  sequencing is unambiguous; step-internal parallelism stays governed by
  `Task.async_stream` with concurrency from `Application.get_env`.

  Streaming progress goes through `SportsFanatic.Predictions.Progress`.
  Halt-on-any-failure: any non-`:ok` step short-circuits the chain and
  records the failed step + item in `system.pipeline_runs` so Oban's
  retry attempt can resume via `checkpoint.completed_steps`.

  The legacy `metadata.steps[]` append continues for backwards compat
  (AC-17 — Recent Runs table still reads `records_processed` from
  metadata).

  Cluster safety: `unique: [period: 3600]` prevents duplicate runs in a
  multi-container deployment.
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]

  alias SportsFanatic.{FeatureFlags, Repo}
  alias SportsFanatic.Predictions.Progress

  alias SportsFanatic.Workers.{
    FetchBvpWorker,
    FetchLineupsWorker,
    FetchPitcherStatsWorker,
    FetchScheduleWorker,
    ForecastWeatherWorker,
    PredictHitsWorker,
    SeedPitcherHistoryWorker,
    SeedStatcastWorker
  }

  require Logger

  @flag "hit_predictions_enabled"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    if not enabled?() and args["force"] != true do
      Logger.info("DailyHitPredictionsWorker: flag #{@flag} off, skipping")
      :ok
    else
      date = parse_date(args["date"]) || SportsFanatic.DateHelper.today()
      run_kind = if args["force"] == true, do: :manual, else: :daily
      do_run(date, run_kind)
    end
  end

  defp do_run(date, run_kind) do
    {run_id, completed_steps} = open_pipeline_run(date, run_kind)

    Progress.start_run(run_id, run_kind: run_kind, date: date)
    Progress.put_for_date(date)

    Logger.info(
      "DailyHitPredictionsWorker: starting pipeline run=#{run_id} date=#{date} kind=#{run_kind}"
    )

    all_steps = [
      {:fetch_schedule, fn -> FetchScheduleWorker.fetch_for_date(date, run_id) end},
      {:fetch_lineups, fn -> FetchLineupsWorker.fetch_for_date(date, run_id) end},
      {:seed_pitcher_history, fn -> SeedPitcherHistoryWorker.run(30, run_id) end},
      {:seed_statcast, fn -> SeedStatcastWorker.run_for_date(date, run_id) end},
      {:fetch_pitcher_stats,
       fn -> FetchPitcherStatsWorker.run_for_date(date, run_id: run_id) end},
      {:fetch_bvp, fn -> FetchBvpWorker.run_for_date(date, run_id) end},
      {:forecast_weather,
       fn -> ForecastWeatherWorker.run_for_date(date, run_id: run_id, mode: :forecast) end},
      {:predict_hits, fn -> PredictHitsWorker.run_for_date(date, run_id) end}
    ]

    steps = filter_completed(all_steps, completed_steps)

    case Enum.reduce_while(steps, {:ok, 0, completed_steps}, &run_step(&1, &2, run_id)) do
      {:ok, prediction_count, _completed} ->
        Progress.run_completed(run_id, processed: prediction_count)
        close_pipeline_run(run_id, "completed", prediction_count, nil)
        Logger.info("DailyHitPredictionsWorker: completed (#{prediction_count} predictions)")
        :ok

      {:error, %{step: step, error: error}} ->
        error_text = "step=#{step}: #{inspect(error)}"
        Progress.run_failed(run_id, error, step: step)
        close_pipeline_run(run_id, "failed", 0, error_text)
        {:error, error_text}
    end
  end

  defp filter_completed(steps, completed) when is_list(completed) do
    Enum.reject(steps, fn {name, _} -> Atom.to_string(name) in completed end)
  end

  defp filter_completed(steps, _), do: steps

  defp run_step({name, fun}, {:ok, _acc, completed}, run_id) do
    started = System.monotonic_time(:millisecond)
    Progress.mark_current_step(run_id, name)

    record =
      try do
        fun.()
      rescue
        e -> {:error, e}
      end

    duration_ms = System.monotonic_time(:millisecond) - started

    {status, count, error} =
      case record do
        {:ok, n} when is_integer(n) -> {"completed", n, nil}
        {:ok, n, _v} when is_integer(n) -> {"completed", n, nil}
        :ok -> {"completed", 0, nil}
        {:error, reason} -> {"failed", 0, reason}
        other -> {"failed", 0, {:unexpected_return, other}}
      end

    # Backwards-compat: keep appending to pipeline_runs.metadata.steps[]
    insert_pipeline_step(run_id, name, status, count, duration_ms, error)

    if status == "failed" do
      # Halt-on-any-failure (was: only :predict_hits halted before).
      {:halt, {:error, %{step: name, error: error}}}
    else
      new_completed = completed ++ [Atom.to_string(name)]

      # Persist the checkpoint so an Oban retry can resume from here.
      Progress.checkpoint(run_id, %{
        "v" => 1,
        "completed_steps" => new_completed,
        "current_step" => nil,
        "failed_at" => nil
      })

      carry =
        case name do
          :predict_hits -> count
          _ -> 0
        end

      {:cont, {:ok, carry, new_completed}}
    end
  end

  ## --- Helpers --------------------------------------------------------------

  defp enabled? do
    case FeatureFlags.enabled?(@flag) do
      true -> true
      false -> false
      _ -> true
    end
  rescue
    _ -> true
  end

  # Returns `{run_id, completed_steps_list}`. If `run_kind=:manual` we always
  # open a fresh run; for `:daily` we also open fresh (the Oban retry case
  # is handled by Oban scheduling a new attempt with the same args; that new
  # attempt opens a new pipeline_runs row but we still benefit from the
  # checkpoint because `Progress.checkpoint/2` is keyed on the run_id, and
  # the orchestrator reads the most recent failed run's checkpoint if we
  # are retrying the same date).
  defp open_pipeline_run(date, run_kind) do
    metadata = %{"run_date" => Date.to_iso8601(date), "steps" => []}
    kind_str = Atom.to_string(run_kind)

    sql = """
    INSERT INTO system.pipeline_runs (
      id, pipeline_name, status, started_at, metadata, run_kind, checkpoint, inserted_at, updated_at
    )
    VALUES (
      gen_random_uuid(), 'hit_predict_daily', 'running', NOW(),
      $1, $2, '{}'::jsonb, NOW(), NOW()
    )
    RETURNING id
    """

    run_id =
      case Repo.query!(sql, [metadata, kind_str]).rows do
        [[id] | _] -> id
        _ -> nil
      end

    {run_id, previous_completed_steps(run_id, date)}
  rescue
    _ ->
      # Fallback path for pre-migration deploys: opens row without run_kind
      # column (column hasn't been added yet).
      legacy = legacy_open_run(date)
      {legacy, []}
  end

  defp legacy_open_run(date) do
    metadata = %{"run_date" => Date.to_iso8601(date), "steps" => []}

    sql = """
    INSERT INTO system.pipeline_runs (id, pipeline_name, status, started_at, metadata, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'hit_predict_daily', 'running', NOW(), $1, NOW(), NOW())
    RETURNING id
    """

    case Repo.query!(sql, [metadata]).rows do
      [[id] | _] -> id
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # Look up the most recent failed run for the same date and return its
  # `checkpoint.completed_steps` array (or []). This is the resume-on-retry
  # mechanism: Oban's `max_attempts: 3` means a transient failure on
  # attempt 1 should let attempt 2 skip the already-completed steps.
  defp previous_completed_steps(_run_id, date) do
    sql = """
    SELECT checkpoint
      FROM system.pipeline_runs
     WHERE pipeline_name = 'hit_predict_daily'
       AND status = 'failed'
       AND metadata->>'run_date' = $1
     ORDER BY started_at DESC
     LIMIT 1
    """

    case Repo.query!(sql, [Date.to_iso8601(date)]).rows do
      [[%{"completed_steps" => steps}] | _] when is_list(steps) -> steps
      _ -> []
    end
  rescue
    _ -> []
  end

  # Postgrex expects a 16-byte binary for `uuid` parameters. `open_pipeline_run`
  # returns the binary form, but callers may pass the 36-char string form
  # (e.g. when the run_id was round-tripped through Oban job args or LiveView
  # assigns). Accept both transparently.
  defp normalize_run_id(nil), do: nil
  defp normalize_run_id(<<_::128>> = bin), do: bin

  defp normalize_run_id(str) when is_binary(str) do
    case Ecto.UUID.dump(str) do
      {:ok, bin} -> bin
      :error -> str
    end
  end

  defp close_pipeline_run(nil, _, _, _), do: :ok

  defp close_pipeline_run(id, status, count, error) do
    Repo.query!(
      """
      UPDATE system.pipeline_runs
         SET status = $2,
             completed_at = NOW(),
             error = $3,
             metadata = COALESCE(metadata, '{}'::jsonb) || jsonb_build_object('records_processed', $4),
             updated_at = NOW()
       WHERE id = $1
      """,
      [normalize_run_id(id), status, error, count]
    )
  rescue
    e ->
      Logger.error(
        "DailyHitPredictionsWorker: close_pipeline_run FAILED (run stays 'running'): " <>
          Exception.message(e)
      )

      :ok
  end

  defp insert_pipeline_step(nil, _, _, _, _, _), do: :ok

  defp insert_pipeline_step(run_id, step_name, status, count, duration_ms, error) do
    # `system.pipeline_steps` does not exist as a separate table; append to
    # the run's metadata.steps[] array instead.
    step = %{
      "name" => Atom.to_string(step_name),
      "status" => status,
      "records_processed" => count,
      "duration_ms" => duration_ms,
      "error" => format_error(error),
      "finished_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Repo.query!(
      """
      UPDATE system.pipeline_runs
         SET metadata = jsonb_set(
                          COALESCE(metadata, '{}'::jsonb),
                          '{steps}',
                          COALESCE(metadata->'steps', '[]'::jsonb) || $2::jsonb,
                          true
                        ),
             updated_at = NOW()
       WHERE id = $1
      """,
      [normalize_run_id(run_id), step]
    )
  rescue
    _ -> :ok
  end

  defp format_error(nil), do: nil
  defp format_error(s) when is_binary(s), do: s
  defp format_error(other), do: inspect(other)

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
