defmodule SportsFanatic.Workers.DailyHitPredictionsWorker do
  @moduledoc """
  Daily hit-prediction pipeline orchestrator. Runs at 8 AM ET via cron.

  Each step is invoked synchronously inside this single Oban job so the
  sequencing is unambiguous; step-internal parallelism stays governed by
  `Task.async_stream` with concurrency from `Application.get_env`.

  Cluster safety: `unique: [period: 3600]` prevents duplicate runs in a
  multi-container deployment.
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]

  alias SportsFanatic.{FeatureFlags, Repo}

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
      do_run(date)
    end
  end

  defp do_run(date) do
    run_id = open_pipeline_run(date)
    Logger.info("DailyHitPredictionsWorker: starting pipeline run=#{run_id} date=#{date}")

    steps = [
      {:fetch_schedule, fn -> FetchScheduleWorker.fetch_for_date(date) end},
      {:fetch_lineups, fn -> FetchLineupsWorker.fetch_for_date(date) end},
      {:seed_pitcher_history, fn -> SeedPitcherHistoryWorker.run(30) end},
      {:seed_statcast, fn -> SeedStatcastWorker.run_for_date(date) end},
      {:fetch_pitcher_stats, fn -> FetchPitcherStatsWorker.run_for_date(date) end},
      {:fetch_bvp, fn -> FetchBvpWorker.run_for_date(date) end},
      {:forecast_weather, fn -> ForecastWeatherWorker.run_for_date(date) end},
      {:predict_hits, fn -> PredictHitsWorker.run_for_date(date, run_id) end}
    ]

    case Enum.reduce_while(steps, {:ok, 0}, &run_step(&1, &2, run_id)) do
      {:ok, prediction_count} ->
        close_pipeline_run(run_id, "completed", prediction_count, nil)
        Logger.info("DailyHitPredictionsWorker: completed (#{prediction_count} predictions)")
        :ok

      {:error, reason} ->
        close_pipeline_run(run_id, "failed", 0, inspect(reason))
        {:error, reason}
    end
  end

  defp run_step({name, fun}, _acc, run_id) do
    started = System.monotonic_time(:millisecond)

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
        {:error, reason} -> {"failed", 0, inspect(reason)}
        _ -> {"completed", 0, nil}
      end

    insert_pipeline_step(run_id, name, status, count, duration_ms, error)

    cond do
      status == "failed" and name == :predict_hits ->
        {:halt, {:error, error}}

      name == :predict_hits ->
        # Bubble up the prediction count for final logging
        {:cont, {:ok, count}}

      true ->
        {:cont, {:ok, 0}}
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

  defp open_pipeline_run(date) do
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
      [id, status, error, count]
    )
  rescue
    _ -> :ok
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
      "error" => error,
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
      [run_id, step]
    )
  rescue
    _ -> :ok
  end

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
