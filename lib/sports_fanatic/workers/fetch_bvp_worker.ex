defmodule SportsFanatic.Workers.FetchBvpWorker do
  @moduledoc """
  Refreshes `mlb.batter_vs_pitcher` for today's (batter × probable pitcher)
  pairs. Concurrency: `bvp_concurrency` (default 6).
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
      Application.get_env(:sports_fanatic, :predictions, [])[:bvp_concurrency] || 6

    pairs = build_pairs(date)
    Logger.info("FetchBvpWorker: #{length(pairs)} batter/pitcher pairs for #{date}")

    count =
      pairs
      |> Task.async_stream(
        fn pair -> upsert_pair(pair, date.year) end,
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

  defp build_pairs(date) do
    # batter_mlb_id × pitcher_mlb_id derived from lineups joined to scheduled_games
    sql = """
    SELECT DISTINCT
      (p.external_ids->>'mlb_id')::int AS batter_mlb_id,
      CASE WHEN tt.id = sg.home_mlb_id THEN g.away_starter_mlb_id
           ELSE g.home_starter_mlb_id END AS pitcher_mlb_id
    FROM mlb.lineups l
    JOIN public.players p ON p.id = l.player_id
    JOIN public.teams tt ON tt.id = p.team_id
    JOIN mlb.scheduled_games sg ON sg.game_date = l.game_date
                                AND (sg.home_mlb_id = (tt.external_ids->>'mlb_id')::int
                                  OR sg.away_mlb_id = (tt.external_ids->>'mlb_id')::int)
    JOIN mlb.games g ON g.game_id = sg.game_id
    WHERE l.game_date = $1
      AND p.external_ids ? 'mlb_id'
    """

    Repo.query!(sql, [date]).rows
    |> Enum.map(fn [b, p] -> %{batter_mlb_id: b, pitcher_mlb_id: p} end)
    |> Enum.reject(fn p -> is_nil(p.pitcher_mlb_id) end)
  rescue
    e ->
      Logger.warning("FetchBvpWorker: pair query failed (#{inspect(e)})")
      []
  end

  defp upsert_pair(%{batter_mlb_id: b, pitcher_mlb_id: p}, season)
       when not is_nil(b) and not is_nil(p) do
    case MlbStats.fetch_batter_vs_pitcher(b, p, season) do
      {:ok, %{} = stat} ->
        Repo.query!(
          """
          WITH bp AS (
            SELECT id FROM public.players WHERE (external_ids->>'mlb_id')::int = $1
          ),
          pp AS (
            SELECT id FROM public.players WHERE (external_ids->>'mlb_id')::int = $2
          )
          INSERT INTO mlb.batter_vs_pitcher (batter_id, pitcher_id, season, at_bats, hits, home_runs, batting_avg, inserted_at, updated_at)
          SELECT bp.id, pp.id, $3, $4, $5, $6, $7, NOW(), NOW()
            FROM bp, pp
          ON CONFLICT (batter_id, pitcher_id, season) DO UPDATE SET
            at_bats = EXCLUDED.at_bats,
            hits = EXCLUDED.hits,
            home_runs = EXCLUDED.home_runs,
            batting_avg = EXCLUDED.batting_avg,
            updated_at = NOW()
          """,
          [
            b,
            p,
            season,
            stat["at_bats"],
            stat["hits"],
            stat["home_runs"],
            stat["batting_avg"]
          ]
        )

        :ok

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp upsert_pair(_, _), do: :ok

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end
