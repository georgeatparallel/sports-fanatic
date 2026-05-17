defmodule SportsFanatic.Workers.SeedStatcastWorker do
  @moduledoc """
  Seeds `mlb.player_statcast` with per-player current-season aggregates
  for hitters in today's lineups. Skips players refreshed within 7 days.

  Concurrency: `statcast_concurrency` (default 4). Idempotent via the
  unique index on `(player_mlb_id, season)`.
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
      Application.get_env(:sports_fanatic, :predictions, [])[:statcast_concurrency] || 4

    players = candidates(date)
    Logger.info("SeedStatcastWorker: #{length(players)} hitters")

    count =
      players
      |> Task.async_stream(&fetch_one(&1, date.year),
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

  defp fetch_one(player_mlb_id, season) do
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

        :ok

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.warning("SeedStatcastWorker player=#{player_mlb_id} error=#{inspect(e)}")
      :ok
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
