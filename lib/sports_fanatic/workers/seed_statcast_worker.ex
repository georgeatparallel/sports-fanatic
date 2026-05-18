defmodule SportsFanatic.Workers.SeedStatcastWorker do
  @moduledoc """
  Seeds `mlb.player_statcast` with per-player current-season aggregates
  for hitters in today's lineups. Skips players refreshed within 7 days.

  Concurrency: `statcast_concurrency` (default 4). Idempotent via the
  unique index on `(player_mlb_id, season)`.

  Historical mode: `run_for_date_range/2` walks every season covering the
  provided date range and re-seeds hitters who appeared in lineups during
  that range.
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]

  alias SportsFanatic.ExternalApis.MlbStats
  alias SportsFanatic.Predictions.Progress
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    date = parse_date(args["date"]) || SportsFanatic.DateHelper.today()
    run_id = parse_run_id(args["pipeline_run_id"])
    run_for_date(date, run_id)
  end

  @spec run_for_date(Date.t(), binary() | nil) :: {:ok, integer} | {:error, term}
  def run_for_date(date, run_id \\ nil)

  def run_for_date(%Date{} = date, run_id) do
    do_run(candidates(date), date.year, run_id, "date=#{date}")
  end

  @doc """
  Historical-mode entrypoint. Iterates seasons covered by the range and
  seeds statcast aggregates for any hitter in lineups on those dates.
  """
  @spec run_for_date_range(Date.t(), Date.t(), binary() | nil) ::
          {:ok, integer} | {:error, term}
  def run_for_date_range(%Date{} = from, %Date{} = through, run_id \\ nil) do
    seasons = Enum.uniq(Enum.map(from.year..through.year, & &1))

    Enum.reduce_while(seasons, {:ok, 0}, fn season, {:ok, acc} ->
      case do_run(
             candidates_for_season(from, through, season),
             season,
             run_id,
             "season=#{season}"
           ) do
        {:ok, n} -> {:cont, {:ok, acc + n}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp do_run(players, season, run_id, label) do
    concurrency =
      Application.get_env(:sports_fanatic, :predictions, [])[:statcast_concurrency] || 4

    total = length(players)
    Logger.info("SeedStatcastWorker: #{total} hitters (#{label})")

    Progress.step_started(run_id, :seed_statcast, total: total, note: label)

    started = System.monotonic_time(:millisecond)

    {count, errors} =
      players
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {pid, idx} -> fetch_one(pid, season, run_id, idx, total) end,
        max_concurrency: concurrency,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce({0, []}, fn
        {:ok, :ok}, {n, errs} -> {n + 1, errs}
        {:ok, {:error, e}}, {n, errs} -> {n, [e | errs]}
        _, {n, errs} -> {n, [:task_failed | errs]}
      end)

    elapsed = System.monotonic_time(:millisecond) - started

    case errors do
      [] ->
        Progress.step_completed(run_id, :seed_statcast,
          processed: count,
          total: total,
          elapsed_ms: elapsed
        )

        {:ok, count}

      [first | _] ->
        {:error, first}
    end
  end

  defp candidates(date) do
    sql = """
    SELECT DISTINCT (p.external_ids->>'mlb_id')::int AS mlb_id
      FROM mlb.lineups l
      JOIN public.players p ON p.id = l.player_id
     WHERE l.game_date = $1
       AND p.external_ids ? 'mlb_id'
       AND (
         NOT EXISTS (
           SELECT 1 FROM mlb.player_statcast sc
            WHERE sc.player_mlb_id = (p.external_ids->>'mlb_id')::int
              AND sc.season = $2
              AND sc.pulled_at > NOW() - INTERVAL '7 days'
         )
       )
    """

    Repo.query!(sql, [date, date.year]).rows
    |> Enum.map(fn [id] -> id end)
    |> Enum.reject(&is_nil/1)
  end

  defp candidates_for_season(from, through, season) do
    sql = """
    SELECT DISTINCT (p.external_ids->>'mlb_id')::int AS mlb_id
      FROM mlb.lineups l
      JOIN public.players p ON p.id = l.player_id
     WHERE l.game_date BETWEEN $1 AND $2
       AND p.external_ids ? 'mlb_id'
       AND NOT EXISTS (
         SELECT 1 FROM mlb.player_statcast sc
          WHERE sc.player_mlb_id = (p.external_ids->>'mlb_id')::int
            AND sc.season = $3
       )
    """

    Repo.query!(sql, [from, through, season]).rows
    |> Enum.map(fn [id] -> id end)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_one(player_mlb_id, season, run_id, idx, total) do
    case MlbStats.fetch_player_statcast(player_mlb_id, season) do
      {:ok, %{} = stat} when stat != %{} ->
        Repo.query!(
          """
          INSERT INTO mlb.player_statcast (
            player_mlb_id, season, avg_exit_velocity, max_exit_velocity, hard_hit_pct, pulled_at, inserted_at, updated_at
          ) VALUES ($1, $2, $3, $4, $5, NOW(), NOW(), NOW())
          ON CONFLICT (player_mlb_id, season) DO UPDATE SET
            avg_exit_velocity = EXCLUDED.avg_exit_velocity,
            max_exit_velocity = EXCLUDED.max_exit_velocity,
            hard_hit_pct = EXCLUDED.hard_hit_pct,
            pulled_at = NOW(),
            updated_at = NOW()
          """,
          [
            player_mlb_id,
            season,
            stat["avg_exit_velocity"],
            stat["max_exit_velocity"],
            stat["hard_hit_pct"]
          ]
        )

        Progress.item_progress(run_id, :seed_statcast, idx,
          total: total,
          current_item: "player=#{player_mlb_id} season=#{season}",
          item_id: player_mlb_id
        )

        :ok

      {:ok, _empty} ->
        Progress.item_progress(run_id, :seed_statcast, idx,
          total: total,
          current_item: "player=#{player_mlb_id} season=#{season} — empty",
          item_id: player_mlb_id
        )

        :ok

      {:error, reason} ->
        Progress.step_failed(run_id, :seed_statcast, reason,
          current_item: "player=#{player_mlb_id} season=#{season}",
          item_id: player_mlb_id,
          endpoint:
            "https://baseballsavant.mlb.com/statcast_search/csv?player_id=#{player_mlb_id}",
          http_status: extract_http_status(reason),
          processed: idx,
          total: total
        )

        {:error, reason}
    end
  rescue
    e ->
      Progress.step_failed(run_id, :seed_statcast, e,
        current_item: "player=#{player_mlb_id} season=#{season}",
        item_id: player_mlb_id,
        endpoint: "https://baseballsavant.mlb.com/statcast_search/csv?player_id=#{player_mlb_id}",
        processed: idx,
        total: total
      )

      {:error, e}
  end

  defp extract_http_status({:http_error, s}) when is_integer(s), do: s
  defp extract_http_status({_, %{status: s}}) when is_integer(s), do: s
  defp extract_http_status(_), do: nil

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_run_id(nil), do: nil
  defp parse_run_id(s) when is_binary(s), do: s
end
