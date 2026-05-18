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
    concurrency =
      Application.get_env(:sports_fanatic, :predictions, [])[:bvp_concurrency] || 6

    pairs = build_pairs(date)
    total = length(pairs)
    Logger.info("FetchBvpWorker: #{total} batter/pitcher pairs for #{date}")

    Progress.step_started(run_id, :fetch_bvp, total: total)

    started = System.monotonic_time(:millisecond)

    {count, errors} =
      pairs
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {pair, idx} -> upsert_pair(pair, date.year, run_id, idx, total) end,
        max_concurrency: concurrency,
        timeout: 15_000,
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
        Progress.step_completed(run_id, :fetch_bvp,
          processed: count,
          total: total,
          elapsed_ms: elapsed
        )

        {:ok, count}

      [first | _] ->
        {:error, first}
    end
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

  defp upsert_pair(%{batter_mlb_id: b, pitcher_mlb_id: p} = pair, season, run_id, idx, total)
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

        Progress.item_progress(run_id, :fetch_bvp, idx,
          total: total,
          current_item: "batter=#{b} vs pitcher=#{p}",
          item_id: b
        )

        :ok

      {:ok, _empty} ->
        Progress.item_progress(run_id, :fetch_bvp, idx,
          total: total,
          current_item: "batter=#{b} vs pitcher=#{p} — empty",
          item_id: b
        )

        :ok

      {:error, reason} ->
        Progress.step_failed(run_id, :fetch_bvp, reason,
          current_item: "batter=#{b} vs pitcher=#{p}",
          item_id: b,
          endpoint: "https://statsapi.mlb.com/api/v1/people/#{b}/stats?stats=vsPlayer",
          http_status: extract_http_status(reason),
          processed: idx,
          total: total
        )

        {:error, reason}
    end
  rescue
    e ->
      Progress.step_failed(run_id, :fetch_bvp, e,
        current_item: "batter=#{pair.batter_mlb_id} vs pitcher=#{pair.pitcher_mlb_id}",
        item_id: pair.batter_mlb_id,
        processed: idx,
        total: total
      )

      {:error, e}
  end

  defp upsert_pair(_, _, _, _, _), do: :ok

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
