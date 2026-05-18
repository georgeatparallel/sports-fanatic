defmodule SportsFanatic.Workers.InitialSeedWorker do
  @moduledoc """
  Backfills MLB data from `seed_from → seed_through` (Eastern dates),
  date by date, broadcasting the same `SportsFanatic.Predictions.Progress`
  events as the daily pipeline so the admin UI streams the backfill
  identically.

  Sequential by default (`PREDICTIONS_INITIAL_SEED_CONCURRENCY=1`). Each
  per-date step is idempotent (ON CONFLICT upserts), so re-running a
  partially-completed date is safe. The worker persists per-date
  checkpoints in `system.pipeline_runs.checkpoint.completed_dates` and
  resumes from the next un-completed date on retry.

  Steps run per date (matches the spec — `predict_hits` is NOT run during
  seed because predictions are only generated for today):

    1. fetch_schedule_for_date
    2. seed_pitcher_history_for_date
    3. seed_statcast_for_date
    4. fetch_pitcher_stats_for_date (force: true)
    5. fetch_bvp_for_date
    6. archive_weather_for_date  (OpenMeteo /archive)

  `fetch_lineups` is skipped because FantasyNerds has no historical
  archive — see spec NG6.
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 5,
    unique: [
      period: :infinity,
      fields: [:worker, :args],
      keys: [:seed_from, :seed_through],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias SportsFanatic.Predictions
  alias SportsFanatic.Predictions.Progress
  alias SportsFanatic.Repo

  alias SportsFanatic.Workers.{
    FetchBvpWorker,
    FetchPitcherStatsWorker,
    FetchScheduleWorker,
    ForecastWeatherWorker,
    SeedPitcherHistoryWorker,
    SeedStatcastWorker
  }

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    with {:ok, seed_from} <- parse_date(args["seed_from"]),
         {:ok, seed_through} <- parse_date(args["seed_through"]) do
      run_id = parse_run_id(args["pipeline_run_id"]) || open_pipeline_run(seed_from, seed_through)
      do_run(run_id, seed_from, seed_through)
    else
      _ -> {:error, :invalid_args}
    end
  end

  defp do_run(run_id, seed_from, seed_through) do
    Progress.start_run(run_id,
      run_kind: :initial_seed,
      seed_from: seed_from,
      seed_through: seed_through
    )

    completed = previous_completed_dates(run_id)
    completed_set = MapSet.new(completed)
    dates = Date.range(seed_from, seed_through) |> Enum.to_list()

    pending =
      Enum.reject(dates, fn d -> MapSet.member?(completed_set, Date.to_iso8601(d)) end)

    Logger.info(
      "InitialSeedWorker: run=#{run_id} from=#{seed_from} through=#{seed_through} " <>
        "total=#{length(dates)} pending=#{length(pending)}"
    )

    result =
      Enum.reduce_while(pending, {:ok, completed}, fn date, {:ok, acc} ->
        case run_one_date(date, run_id) do
          :ok ->
            iso = Date.to_iso8601(date)
            new_completed = acc ++ [iso]

            Progress.checkpoint(run_id, %{
              "v" => 1,
              "completed_dates" => new_completed,
              "current_date" => nil,
              "current_step" => nil,
              "failed_at" => nil
            })

            {:cont, {:ok, new_completed}}

          {:error, reason} ->
            iso = Date.to_iso8601(date)

            Progress.checkpoint(run_id, %{
              "v" => 1,
              "completed_dates" => acc,
              "current_date" => iso,
              "current_step" => nil,
              "failed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            })

            {:halt, {:error, reason, iso}}
        end
      end)

    case result do
      {:ok, completed_all} ->
        Progress.run_completed(run_id, processed: length(completed_all))
        close_pipeline_run(run_id, "completed", length(completed_all), nil)
        :ok

      {:error, reason, iso} ->
        Progress.run_failed(run_id, reason, current_item: iso)
        close_pipeline_run(run_id, "failed", 0, "date=#{iso}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp run_one_date(date, run_id) do
    Predictions.mark_current_date(run_id, date)
    Progress.mark_current_step(run_id, "seed_date_#{Date.to_iso8601(date)}")

    steps = [
      {:fetch_schedule, fn -> FetchScheduleWorker.fetch_for_date(date, run_id) end},
      {:seed_pitcher_history, fn -> SeedPitcherHistoryWorker.run_for_date(date, run_id) end},
      {:seed_statcast, fn -> SeedStatcastWorker.run_for_date(date, run_id) end},
      {:fetch_pitcher_stats,
       fn -> FetchPitcherStatsWorker.run_for_date(date, run_id: run_id, force: true) end},
      {:fetch_bvp, fn -> FetchBvpWorker.run_for_date(date, run_id) end},
      {:forecast_weather,
       fn -> ForecastWeatherWorker.run_for_date(date, run_id: run_id, mode: :archive) end}
    ]

    Enum.reduce_while(steps, :ok, fn {name, fun}, _acc ->
      Progress.mark_current_step(run_id, name)

      case safe_invoke(fun) do
        :ok -> {:cont, :ok}
        {:ok, _} -> {:cont, :ok}
        {:ok, _, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, %{step: name, date: date, error: reason}}}
        other -> {:halt, {:error, %{step: name, date: date, error: other}}}
      end
    end)
  end

  defp safe_invoke(fun) do
    fun.()
  rescue
    e -> {:error, e}
  end

  defp previous_completed_dates(nil), do: []

  defp previous_completed_dates(run_id) do
    sql = """
    SELECT checkpoint FROM system.pipeline_runs WHERE id = $1
    """

    case Repo.query!(sql, [run_id]).rows do
      [[%{"completed_dates" => dates}] | _] when is_list(dates) -> dates
      _ -> []
    end
  rescue
    _ -> []
  end

  defp open_pipeline_run(seed_from, seed_through) do
    metadata = %{
      "run_kind" => "initial_seed",
      "seed_from" => Date.to_iso8601(seed_from),
      "seed_through" => Date.to_iso8601(seed_through),
      "steps" => []
    }

    sql = """
    INSERT INTO system.pipeline_runs (
      id, pipeline_name, status, started_at, metadata, run_kind,
      seed_from_date, seed_through_date, checkpoint, inserted_at, updated_at
    )
    VALUES (
      gen_random_uuid(), 'hit_predict_initial_seed', 'running', NOW(),
      $1, 'initial_seed', $2, $3, '{}'::jsonb, NOW(), NOW()
    )
    RETURNING id
    """

    case Repo.query!(sql, [metadata, seed_from, seed_through]).rows do
      [[id] | _] -> id
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp close_pipeline_run(nil, _status, _count, _err), do: :ok

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

  defp parse_date(%Date{} = d), do: {:ok, d}

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> {:ok, d}
      _ -> :error
    end
  end

  defp parse_date(_), do: :error

  defp parse_run_id(nil), do: nil
  defp parse_run_id(s) when is_binary(s), do: s
end
