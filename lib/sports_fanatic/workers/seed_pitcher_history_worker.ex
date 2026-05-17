defmodule SportsFanatic.Workers.SeedPitcherHistoryWorker do
  @moduledoc """
  Walks `mlb.games` rows in the last 30 days that are missing starter
  pitcher IDs, fetches the boxscore from MLB Stats API, updates starter
  IDs, and upserts pitcher game logs into `mlb.pitcher_game_logs`.

  Concurrency: `seed_pitcher_concurrency` (default 4). Idempotent via the
  unique index on `(pitcher_mlb_id, game_id)`.
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
    days = args["days"] || 30
    run(days)
  end

  @spec run(pos_integer) :: {:ok, integer}
  def run(days_back \\ 30) do
    concurrency =
      Application.get_env(:sports_fanatic, :predictions, [])[:seed_pitcher_concurrency] || 4

    games = backfillable_games(days_back)
    Logger.info("SeedPitcherHistoryWorker: #{length(games)} games to backfill")

    count =
      games
      |> Task.async_stream(&seed_game/1,
        max_concurrency: concurrency,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.count(fn
        {:ok, :ok} -> true
        _ -> false
      end)

    {:ok, count}
  end

  defp backfillable_games(days_back) do
    sql = """
    SELECT game_id
      FROM mlb.games
     WHERE game_datetime::date >= CURRENT_DATE - $1::int
       AND game_datetime::date <  CURRENT_DATE
       AND (away_starter_mlb_id IS NULL OR home_starter_mlb_id IS NULL)
    """

    Repo.query!(sql, [days_back]).rows |> Enum.map(fn [g] -> g end)
  end

  defp seed_game(game_id) do
    case MlbStats.fetch_boxscore(game_id) do
      {:ok, body} ->
        process_boxscore(game_id, body)
        :ok

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.warning("SeedPitcherHistoryWorker game=#{game_id} error=#{inspect(e)}")
      :ok
  end

  defp process_boxscore(game_id, body) do
    away_starter = starter_id(body, "away")
    home_starter = starter_id(body, "home")

    Repo.query!(
      """
      UPDATE mlb.games
         SET away_starter_mlb_id = COALESCE($2, away_starter_mlb_id),
             home_starter_mlb_id = COALESCE($3, home_starter_mlb_id),
             updated_at = NOW()
       WHERE game_id = $1
      """,
      [game_id, away_starter, home_starter]
    )

    Enum.each(["away", "home"], fn side ->
      body
      |> get_in(["teams", side, "pitchers"]) || []
    end)

    # Insert all pitching log rows
    Enum.each(["away", "home"], fn side ->
      pitchers = get_in(body, ["teams", side, "pitchers"]) || []
      players_map = get_in(body, ["teams", side, "players"]) || %{}

      Enum.each(pitchers, fn pid ->
        person_key = "ID#{pid}"

        stats =
          get_in(players_map, [person_key, "stats", "pitching"]) || %{}

        insert_pitcher_game_log(game_id, pid, stats)
      end)
    end)
  end

  defp starter_id(body, side) do
    case get_in(body, ["teams", side, "pitchers"]) do
      [first | _] when is_integer(first) -> first
      _ -> nil
    end
  end

  defp insert_pitcher_game_log(_game_id, nil, _), do: :ok

  defp insert_pitcher_game_log(game_id, pid, stats) do
    Repo.query!(
      """
      INSERT INTO mlb.pitcher_game_logs (
        pitcher_mlb_id, game_id, game_date, innings_pitched, hits_allowed,
        hr_allowed, bb_allowed, strikeouts, earned_runs, pitches_thrown
      )
      SELECT $1, $2, g.game_datetime::date, $3, $4, $5, $6, $7, $8, $9
        FROM mlb.games g WHERE g.game_id = $2
      ON CONFLICT (pitcher_mlb_id, game_id) DO NOTHING
      """,
      [
        pid,
        game_id,
        parse_ip(stats["inningsPitched"]),
        to_int(stats["hits"]),
        to_int(stats["homeRuns"]),
        to_int(stats["baseOnBalls"]),
        to_int(stats["strikeOuts"]),
        to_int(stats["earnedRuns"]),
        to_int(stats["numberOfPitches"])
      ]
    )
  end

  defp parse_ip(nil), do: nil
  defp parse_ip(v) when is_float(v), do: v
  defp parse_ip(v) when is_integer(v), do: v * 1.0

  defp parse_ip(v) when is_binary(v) do
    case String.split(v, ".") do
      [whole, third] ->
        with {w, _} <- Integer.parse(whole), {t, _} <- Integer.parse(third) do
          w + t / 3.0
        else
          _ -> nil
        end

      [whole] ->
        case Integer.parse(whole) do
          {w, _} -> w * 1.0
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_ip(_), do: nil

  defp to_int(nil), do: nil
  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      _ -> nil
    end
  end

  defp to_int(_), do: nil
end
