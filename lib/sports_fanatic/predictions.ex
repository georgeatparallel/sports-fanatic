defmodule SportsFanatic.Predictions do
  @moduledoc """
  Context API for the hit-predictions pipeline.

  Read paths cache through Valkey under the
  `sf:data:hit_prediction:{mlb_id}:{YYYY-MM-DD}` namespace (TTL 5 minutes).
  Write paths are owned by `SportsFanatic.Workers.PredictHitsWorker`.
  """

  import Ecto.Query

  alias SportsFanatic.Cache
  alias SportsFanatic.Predictions.HitPrediction
  alias SportsFanatic.Predictions.PipelineRunEvent
  alias SportsFanatic.Repo
  alias SportsFanatic.Workers.{DailyHitPredictionsWorker, InitialSeedWorker}

  @doc "Today (Eastern) hit predictions sorted by probability desc."
  def list_today(opts \\ []), do: list_for_date(SportsFanatic.DateHelper.today(), opts)

  @doc """
  All hit predictions for `date`. Opts:

    * `:team` — filter by `player_team` (string)
    * `:limit` — max rows
    * `:min_prob` — minimum hit_prob
  """
  @spec list_for_date(Date.t(), keyword) :: [HitPrediction.t()]
  def list_for_date(%Date{} = date, opts \\ []) do
    HitPrediction
    |> where([h], h.prediction_date == ^date)
    |> maybe_team(opts[:team])
    |> maybe_min_prob(opts[:min_prob])
    |> order_by([h], desc: h.hit_prob)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  @doc """
  Fetch a per-player prediction for `date` (today by default). Reads cache
  first; falls back to Postgres and warms the cache.
  """
  @spec get_for_player(integer, Date.t() | nil) :: HitPrediction.t() | nil
  def get_for_player(player_mlb_id, date \\ nil)

  def get_for_player(player_mlb_id, nil),
    do: get_for_player(player_mlb_id, SportsFanatic.DateHelper.today())

  def get_for_player(player_mlb_id, %Date{} = date) when is_integer(player_mlb_id) do
    key = cache_key(player_mlb_id, date)

    case Cache.get(key) do
      {:ok, nil} ->
        case load_from_db(player_mlb_id, date) do
          nil ->
            nil

          %HitPrediction{} = hp ->
            with {:ok, encoded} <- Jason.encode(serialize(hp)) do
              Cache.set(key, encoded, 300)
            end

            hp
        end

      {:ok, raw} when is_binary(raw) ->
        case Jason.decode(raw) do
          {:ok, map} -> deserialize(map)
          _ -> load_from_db(player_mlb_id, date)
        end

      _ ->
        load_from_db(player_mlb_id, date)
    end
  end

  def get_for_player(_, _), do: nil

  @doc """
  Last `limit` pipeline runs of type `hit_predict_daily` for the admin tab.
  """
  def list_runs(limit \\ 30) do
    sql = """
    SELECT id, status, started_at, completed_at, error, metadata
      FROM system.pipeline_runs
     WHERE pipeline_name = 'hit_predict_daily'
     ORDER BY started_at DESC
     LIMIT $1
    """

    Repo.query!(sql, [limit]).rows
    |> Enum.map(fn [id, status, started, completed, error, metadata] ->
      %{
        id: uuid_to_string(id),
        status: status,
        started_at: started,
        completed_at: completed,
        error: error,
        metadata: metadata || %{}
      }
    end)
  rescue
    _ -> []
  end

  # Postgres returns `uuid` columns from raw `Repo.query!/2` as a 16-byte
  # binary, which is NOT valid UTF-8 and crashes Jason when LiveView tries
  # to ship it down the WebSocket. The Ecto schema layer auto-casts, but
  # these helpers go through raw SQL for projection convenience, so we
  # cast manually before anything reaches LiveView assigns.
  defp uuid_to_string(nil), do: nil

  defp uuid_to_string(<<_::128>> = bin) do
    case Ecto.UUID.cast(bin) do
      {:ok, str} -> str
      :error -> nil
    end
  end

  defp uuid_to_string(str) when is_binary(str), do: str

  @doc "Enqueue an immediate run. Pass `:today` or a `Date`."
  @spec run_now(Date.t() | :today) :: {:ok, Oban.Job.t()} | {:error, term}
  def run_now(:today), do: run_now(SportsFanatic.DateHelper.today())

  def run_now(%Date{} = date) do
    %{"date" => Date.to_iso8601(date), "force" => true}
    |> DailyHitPredictionsWorker.new()
    |> Oban.insert()
  end

  @doc "Stream of all predictions for `player_mlb_id`, newest first."
  def stream_player_results(player_mlb_id) when is_integer(player_mlb_id) do
    HitPrediction
    |> where([h], h.player_mlb_id == ^player_mlb_id)
    |> order_by([h], desc: h.prediction_date)
  end

  @doc """
  Returns the latest of the earliest dates across the three source tables
  (`mlb.scheduled_games`, `mlb.pitcher_game_logs`, `mlb.player_statcast`).

  Used by `start_initial_seed/0` to compute the seed lower bound — we seed
  back to the day before this date (or `PREDICTIONS_INITIAL_SEED_FROM`,
  whichever is later). When any of the three source tables is empty, this
  returns `nil` so the seeder runs from the configured `initial_seed_from`.
  """
  @spec earliest_data_date() :: Date.t() | nil
  def earliest_data_date do
    sql = """
    SELECT
      (SELECT MIN(game_date)   FROM mlb.scheduled_games)  AS sched_min,
      (SELECT MIN(game_date)   FROM mlb.pitcher_game_logs) AS pgl_min,
      (SELECT MIN(make_date(season, 1, 1)) FROM mlb.player_statcast) AS sc_min
    """

    case Repo.query!(sql, []).rows do
      [[sched, pgl, sc] | _] ->
        candidates = [sched, pgl, sc]

        if Enum.any?(candidates, &is_nil/1) do
          nil
        else
          Enum.max_by(candidates, &Date.to_erl/1, fn -> nil end)
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Computes the seed window and enqueues `InitialSeedWorker`.

  Returns:
    * `{:ok, :nothing_to_do}` if `seed_from > seed_through`
    * `{:ok, %{job_id, seed_from, seed_through}}` on success
    * `{:error, reason}` otherwise
  """
  @spec start_initial_seed() ::
          {:ok, :nothing_to_do}
          | {:ok, %{job_id: term(), seed_from: Date.t(), seed_through: Date.t()}}
          | {:error, term()}
  def start_initial_seed do
    cfg = Application.get_env(:sports_fanatic, :predictions, [])

    seed_from_floor =
      case cfg[:initial_seed_from] do
        s when is_binary(s) ->
          case Date.from_iso8601(s) do
            {:ok, d} -> d
            _ -> ~D[2021-03-01]
          end

        _ ->
          ~D[2021-03-01]
      end

    seed_through = Date.add(SportsFanatic.DateHelper.today(), -1)

    seed_from =
      case earliest_data_date() do
        nil -> seed_from_floor
        %Date{} = earliest -> latest(Date.add(earliest, -1), seed_from_floor)
      end

    cond do
      Date.compare(seed_from, seed_through) == :gt ->
        {:ok, :nothing_to_do}

      true ->
        # Eagerly open a pipeline_runs row so the admin UI sees the run_kind
        # before the worker boots. The worker itself will re-use this id if
        # we pass it via args.
        run_id =
          open_seed_pipeline_run(seed_from, seed_through)

        args = %{
          "seed_from" => Date.to_iso8601(seed_from),
          "seed_through" => Date.to_iso8601(seed_through),
          "pipeline_run_id" => run_id
        }

        case args |> InitialSeedWorker.new() |> Oban.insert() do
          {:ok, %Oban.Job{id: id}} ->
            {:ok, %{job_id: id, seed_from: seed_from, seed_through: seed_through}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Returns up to `limit` recent events for `run_id`, newest first.
  """
  @spec list_run_events(binary(), pos_integer()) :: [PipelineRunEvent.t()]
  def list_run_events(run_id, limit \\ 500) when is_binary(run_id) and is_integer(limit) do
    PipelineRunEvent
    |> where([e], e.pipeline_run_id == ^run_id)
    |> order_by([e], desc: e.seq)
    |> limit(^limit)
    |> Repo.all()
  rescue
    _ -> []
  end

  @doc """
  Returns the most-recent `running` pipeline_runs row enriched with the
  last `pipeline_run_events` row for that run, or nil.

  AdminLive uses this to seed the Currently-Running panel on tab switch and
  on each tick. Even when no live PubSub event has arrived (e.g. the run was
  started before the LV mounted, or the BEAM was restarted mid-run), the
  panel can still render meaningful state because we surface the legacy
  `metadata["steps"]` array AND the most-recent `pipeline_run_events` row.
  """
  @spec current_running_run() :: map() | nil
  def current_running_run do
    sql = """
    SELECT id, run_kind, started_at, current_step, metadata, checkpoint,
           seed_from_date, seed_through_date
      FROM system.pipeline_runs
     WHERE status = 'running'
     ORDER BY started_at DESC
     LIMIT 1
    """

    case Repo.query!(sql, []).rows do
      [[id, kind, started, current_step, metadata, checkpoint, sf, st] | _] ->
        run_id = uuid_to_string(id)
        metadata = metadata || %{}
        checkpoint = checkpoint || %{}
        completed_dates = Map.get(checkpoint, "completed_dates", [])

        total_dates =
          if sf && st do
            Date.diff(st, sf) + 1
          else
            nil
          end

        %{
          id: run_id,
          run_kind: kind,
          started_at: started,
          current_step: current_step,
          metadata: metadata,
          checkpoint: checkpoint,
          seed_from_date: sf,
          seed_through_date: st,
          current_date:
            Map.get(metadata, "current_date") || Map.get(checkpoint, "current_date") ||
              Map.get(metadata, "run_date"),
          completed_dates_count: length(completed_dates),
          total_dates: total_dates,
          legacy_steps: Map.get(metadata, "steps", []),
          last_event: last_event_for_run(run_id)
        }

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Marks a stuck `running` pipeline_runs row as `failed` with a manual
  error string. Used by the admin Predictions tab when a worker has
  crashed and left a `running` row that no one is updating.
  """
  @spec mark_run_failed(binary(), String.t()) :: :ok | {:error, term}
  def mark_run_failed(run_id, error_text)
      when is_binary(run_id) and is_binary(error_text) do
    # Postgrex parameter encoding for a `uuid` column expects the raw 16-byte
    # binary, NOT the 36-char hex string — we surfaced the string form via
    # uuid_to_string/1 for LiveView/JSON, so we have to dump it back here.
    with {:ok, bin_uuid} <- Ecto.UUID.dump(run_id),
         {:ok, _} <-
           Repo.query(
             """
             UPDATE system.pipeline_runs
                SET status = 'failed',
                    completed_at = NOW(),
                    error = $2,
                    updated_at = NOW()
              WHERE id = $1
                AND status = 'running'
             """,
             [bin_uuid, error_text]
           ) do
      :ok
    else
      :error -> {:error, :invalid_uuid}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Cancels any executing/scheduled/retryable Oban jobs for the orchestrator
  workers and marks the pipeline_runs row as `failed`. Used by the admin
  "Stop" button.
  """
  @spec stop_run(binary()) :: :ok | {:error, term}
  def stop_run(run_id) when is_binary(run_id) do
    workers = [
      "SportsFanatic.Workers.InitialSeedWorker",
      "SportsFanatic.Workers.DailyHitPredictionsWorker"
    ]

    cancelled_count =
      from(j in Oban.Job,
        where: j.worker in ^workers,
        where: j.state in ["executing", "available", "scheduled", "retryable"]
      )
      |> Repo.all()
      |> Enum.reduce(0, fn job, acc ->
        case Oban.cancel_job(job.id) do
          :ok -> acc + 1
          _ -> acc
        end
      end)

    note = "Manually stopped from admin UI (cancelled #{cancelled_count} Oban job(s))."
    mark_run_failed(run_id, note)
  rescue
    e -> {:error, e}
  end

  @doc """
  Updates `system.pipeline_runs.metadata.current_date` so the admin UI can
  display which historical date the InitialSeedWorker is currently
  processing. Fire-and-forget — never raises.
  """
  @spec mark_current_date(binary() | nil, Date.t() | binary() | nil) :: :ok
  def mark_current_date(nil, _date), do: :ok
  def mark_current_date(_run_id, nil), do: :ok

  def mark_current_date(run_id, %Date{} = date),
    do: mark_current_date(run_id, Date.to_iso8601(date))

  def mark_current_date(run_id, date_iso) when is_binary(run_id) and is_binary(date_iso) do
    case Ecto.UUID.dump(run_id) do
      {:ok, bin} ->
        Repo.query(
          """
          UPDATE system.pipeline_runs
             SET metadata = jsonb_set(
                              COALESCE(metadata, '{}'::jsonb),
                              '{current_date}',
                              to_jsonb($2::text),
                              true
                            ),
                 updated_at = NOW()
           WHERE id = $1
          """,
          [bin, date_iso]
        )

      :error ->
        :ok
    end

    :ok
  rescue
    _ -> :ok
  end

  defp last_event_for_run(nil), do: nil

  defp last_event_for_run(run_id) when is_binary(run_id) do
    case Repo.one(
           from(e in PipelineRunEvent,
             where: e.pipeline_run_id == ^run_id,
             order_by: [desc: e.seq],
             limit: 1
           )
         ) do
      nil -> nil
      %PipelineRunEvent{} = ev -> Map.from_struct(ev) |> Map.drop([:__meta__])
    end
  rescue
    _ -> nil
  end

  ## --- Helpers --------------------------------------------------------------

  defp latest(%Date{} = a, %Date{} = b) do
    if Date.compare(a, b) == :gt, do: a, else: b
  end

  defp open_seed_pipeline_run(seed_from, seed_through) do
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
      [[id] | _] -> uuid_to_string(id)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp load_from_db(player_mlb_id, date) do
    HitPrediction
    |> where([h], h.player_mlb_id == ^player_mlb_id and h.prediction_date == ^date)
    |> Repo.one()
  end

  defp cache_key(mlb_id, %Date{} = d),
    do: "sf:data:hit_prediction:#{mlb_id}:#{Date.to_iso8601(d)}"

  defp serialize(%HitPrediction{} = hp) do
    hp
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  defp deserialize(map) when is_map(map) do
    struct(HitPrediction, atomize_keys(map))
  end

  defp atomize_keys(m) do
    Enum.into(m, %{}, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  rescue
    _ -> %{}
  end

  defp maybe_team(q, nil), do: q
  defp maybe_team(q, team), do: where(q, [h], h.player_team == ^team)
  defp maybe_min_prob(q, nil), do: q
  defp maybe_min_prob(q, p), do: where(q, [h], h.hit_prob >= ^p)
  defp maybe_limit(q, nil), do: q
  defp maybe_limit(q, l) when is_integer(l), do: limit(q, ^l)
end
