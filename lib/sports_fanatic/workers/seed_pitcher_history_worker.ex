defmodule SportsFanatic.Workers.SeedPitcherHistoryWorker do
  @moduledoc """
  Walks `mlb.games` rows in the last 30 days that are missing starter
  pitcher IDs, fetches the boxscore from MLB Stats API, updates starter
  IDs, and upserts pitcher game logs into `mlb.pitcher_game_logs`.

  Concurrency: `seed_pitcher_concurrency` (default 4). Idempotent via the
  unique index on `(pitcher_mlb_id, game_id)`.

  Historical mode: `run_for_date/2` walks games on exactly that date for
  use by `InitialSeedWorker`.
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
    run_id = parse_run_id(args["pipeline_run_id"])

    if is_binary(args["date"]) do
      case parse_date(args["date"]) do
        %Date{} = d -> run_for_date(d, run_id)
        _ -> run(args["days"] || 30, run_id)
      end
    else
      run(args["days"] || 30, run_id)
    end
  end

  @spec run(pos_integer(), binary() | nil) :: {:ok, integer} | {:error, term}
  def run(days_back \\ 30, run_id \\ nil)

  def run(days_back, run_id) do
    games = backfillable_games(days_back)
    do_seed_games(games, run_id, "last #{days_back}d")
  end

  @doc """
  Historical-mode entrypoint. Walks games on `date` exactly.
  """
  @spec run_for_date(Date.t(), binary() | nil) :: {:ok, integer} | {:error, term}
  def run_for_date(%Date{} = date, run_id \\ nil) do
    games = games_for_date(date)
    do_seed_games(games, run_id, Date.to_iso8601(date))
  end

  defp do_seed_games(games, run_id, label) do
    concurrency =
      Application.get_env(:sports_fanatic, :predictions, [])[:seed_pitcher_concurrency] || 4

    total = length(games)
    Logger.info("SeedPitcherHistoryWorker: #{total} games to backfill (#{label})")

    Progress.step_started(run_id, :seed_pitcher_history, total: total)

    started = System.monotonic_time(:millisecond)
    for_date = Process.get(:predictions_for_date)

    {count, errors} =
      games
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {game_id, idx} ->
          Progress.put_for_date(for_date)
          seed_game(game_id, run_id, idx, total)
        end,
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
        Progress.step_completed(run_id, :seed_pitcher_history,
          processed: count,
          total: total,
          elapsed_ms: elapsed
        )

        {:ok, count}

      [first | _] ->
        {:error, first}
    end
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

  defp games_for_date(%Date{} = date) do
    sql = """
    SELECT game_id
      FROM mlb.games
     WHERE game_datetime::date = $1
    """

    Repo.query!(sql, [date]).rows |> Enum.map(fn [g] -> g end)
  end

  defp seed_game(game_id, run_id, idx, total) do
    case MlbStats.fetch_boxscore(game_id) do
      {:ok, body} ->
        process_boxscore(game_id, body)
        starter = starter_id(body, "away") || starter_id(body, "home")
        pitcher_name = pitcher_name(body, starter)

        Progress.item_progress(run_id, :seed_pitcher_history, idx,
          total: total,
          current_item: "game=#{game_id} pitcher=#{pitcher_name} (#{starter})",
          item_id: game_id
        )

        :ok

      {:error, reason} ->
        Progress.step_failed(run_id, :seed_pitcher_history, reason,
          current_item: "game=#{game_id}",
          item_id: game_id,
          endpoint: "https://statsapi.mlb.com/api/v1/game/#{game_id}/boxscore",
          http_status: extract_http_status(reason),
          processed: idx,
          total: total
        )

        {:error, reason}
    end
  rescue
    e ->
      Progress.step_failed(run_id, :seed_pitcher_history, e,
        current_item: "game=#{game_id}",
        item_id: game_id,
        endpoint: "https://statsapi.mlb.com/api/v1/game/#{game_id}/boxscore",
        processed: idx,
        total: total
      )

      {:error, e}
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

  defp pitcher_name(_body, nil), do: "(unknown)"

  defp pitcher_name(body, pid) do
    Enum.find_value(["away", "home"], fn side ->
      get_in(body, ["teams", side, "players", "ID#{pid}", "person", "fullName"])
    end) || "(unknown)"
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
