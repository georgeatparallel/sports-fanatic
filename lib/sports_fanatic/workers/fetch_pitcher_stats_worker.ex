defmodule SportsFanatic.Workers.FetchPitcherStatsWorker do
  @moduledoc """
  Refreshes `mlb.pitcher_stats` for the probable pitchers of `date`'s games.
  Skips pitchers whose `last_updated` is within 24 hours. Internal
  parallelism uses `Task.async_stream` with runtime-configured concurrency.
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]

  alias SportsFanatic.ExternalApis.MlbStats
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    date = parse_date(args["date"]) || SportsFanatic.DateHelper.today()
    run_for_date(date)
  end

  @spec run_for_date(Date.t()) :: {:ok, integer}
  def run_for_date(%Date{} = date) do
    concurrency =
      Application.get_env(:sports_fanatic, :predictions, [])[:pitcher_stats_concurrency] || 4

    pitchers = candidate_pitchers(date)
    Logger.info("FetchPitcherStatsWorker: #{length(pitchers)} pitchers for #{date}")

    count =
      pitchers
      |> Task.async_stream(&fetch_and_upsert(&1, date),
        max_concurrency: concurrency,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.count(fn
        {:ok, :ok} -> true
        _ -> false
      end)

    {:ok, count}
  end

  defp candidate_pitchers(date) do
    sql = """
    SELECT DISTINCT name, mlb_id
      FROM (
        SELECT sg.away_probable_pitcher AS name,
               g.away_starter_mlb_id   AS mlb_id
          FROM mlb.scheduled_games sg
          LEFT JOIN mlb.games g ON g.game_id = sg.game_id
         WHERE sg.game_date = $1
        UNION
        SELECT sg.home_probable_pitcher AS name,
               g.home_starter_mlb_id   AS mlb_id
          FROM mlb.scheduled_games sg
          LEFT JOIN mlb.games g ON g.game_id = sg.game_id
         WHERE sg.game_date = $1
      ) p
     WHERE name IS NOT NULL
    """

    Repo.query!(sql, [date]).rows
    |> Enum.map(fn [name, mlb_id] -> %{name: name, mlb_id: mlb_id} end)
  end

  defp fetch_and_upsert(%{mlb_id: nil}, _date), do: :skip

  defp fetch_and_upsert(%{mlb_id: pid}, date) do
    season = date.year

    if fresh?(pid, season) do
      :ok
    else
      case MlbStats.fetch_pitcher_season_stats(pid, season) do
        {:ok, stat} when stat != %{} ->
          upsert(pid, season, stat)
          :ok

        _ ->
          :ok
      end
    end
  end

  defp fresh?(pid, season) do
    case Repo.query!(
           """
           SELECT last_updated FROM mlb.pitcher_stats
             WHERE COALESCE(pitcher_mlb_id, 0) = $1 AND season = $2
             LIMIT 1
           """,
           [pid, season]
         ).rows do
      [[%DateTime{} = ts] | _] ->
        DateTime.diff(DateTime.utc_now(), ts, :second) < 24 * 60 * 60

      _ ->
        false
    end
  end

  defp upsert(pid, season, stat) do
    Repo.query!(
      """
      INSERT INTO mlb.pitcher_stats (
        pitcher_mlb_id, season, batting_avg_against, k_per_9, whip, bb_per_9,
        hr_per_9, era, games_played, innings_pitched, games_started,
        hits_allowed, hr_allowed, bb_allowed, strikeouts, last_updated, inserted_at, updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW(), NOW(), NOW()
      )
      ON CONFLICT DO NOTHING
      """,
      [
        pid,
        season,
        f(stat["batting_avg_against"]),
        f(stat["k_per_9"]),
        f(stat["whip"]),
        f(stat["bb_per_9"]),
        f(stat["hr_per_9"]),
        f(stat["era"]),
        i(stat["games_played"]),
        f(stat["innings_pitched"]),
        i(stat["games_started"]),
        i(stat["hits_allowed"]),
        i(stat["hr_allowed"]),
        i(stat["bb_allowed"]),
        i(stat["strikeouts"])
      ]
    )

    # If a row already existed (matching player_id + season) we still want
    # to refresh `last_updated`. Best-effort UPDATE:
    Repo.query!(
      """
      UPDATE mlb.pitcher_stats
         SET batting_avg_against = COALESCE($3, batting_avg_against),
             k_per_9            = COALESCE($4, k_per_9),
             whip               = COALESCE($5, whip),
             bb_per_9           = COALESCE($6, bb_per_9),
             hr_per_9           = COALESCE($7, hr_per_9),
             era                = COALESCE($8, era),
             games_played       = COALESCE($9, games_played),
             innings_pitched    = COALESCE($10, innings_pitched),
             games_started      = COALESCE($11, games_started),
             hits_allowed       = COALESCE($12, hits_allowed),
             hr_allowed         = COALESCE($13, hr_allowed),
             bb_allowed         = COALESCE($14, bb_allowed),
             strikeouts         = COALESCE($15, strikeouts),
             last_updated       = NOW(),
             updated_at         = NOW()
       WHERE pitcher_mlb_id = $1 AND season = $2
      """,
      [
        pid,
        season,
        f(stat["batting_avg_against"]),
        f(stat["k_per_9"]),
        f(stat["whip"]),
        f(stat["bb_per_9"]),
        f(stat["hr_per_9"]),
        f(stat["era"]),
        i(stat["games_played"]),
        f(stat["innings_pitched"]),
        i(stat["games_started"]),
        i(stat["hits_allowed"]),
        i(stat["hr_allowed"]),
        i(stat["bb_allowed"]),
        i(stat["strikeouts"])
      ]
    )
  end

  defp f(nil), do: nil
  defp f(v) when is_float(v), do: v
  defp f(v) when is_integer(v), do: v * 1.0
  defp f(_), do: nil

  defp i(nil), do: nil
  defp i(v) when is_integer(v), do: v
  defp i(_), do: nil

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
