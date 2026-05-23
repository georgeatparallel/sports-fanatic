defmodule SportsFanatic.Workers.FetchScheduleWorker do
  @moduledoc """
  Fetches daily MLB schedule from the MLB Stats API and upserts
  `mlb.scheduled_games` + `mlb.games` rows.

  Runs at 6 AM ET daily via cron, and is also called synchronously by
  `SportsFanatic.Workers.DailyHitPredictionsWorker`.
  """

  use Oban.Worker,
    queue: :data_fetch,
    max_attempts: 3,
    unique: [period: 600]

  alias SportsFanatic.ExternalApis.MlbStats
  alias SportsFanatic.Mlb.{Game, ScheduledGame}
  alias SportsFanatic.Predictions.Progress
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    date = parse_date(args["date"]) || SportsFanatic.DateHelper.today()
    run_id = parse_run_id(args["pipeline_run_id"])
    fetch_for_date(date, run_id)
  end

  @doc """
  Synchronous entrypoint used by the predictions orchestrator. Returns
  `{:ok, count}` or `{:error, reason}`.
  """
  @spec fetch_for_date(Date.t(), binary() | nil) :: {:ok, integer} | {:error, term}
  def fetch_for_date(date, run_id \\ nil)

  def fetch_for_date(%Date{} = date, run_id) do
    Progress.step_started(run_id, :fetch_schedule, total: 1, for_date: date)

    case MlbStats.fetch_schedule(date) do
      {:ok, games} when is_list(games) ->
        Enum.each(games, &upsert_game/1)
        Logger.info("FetchScheduleWorker: fetched #{length(games)} games for #{date}")

        invalidate_game_card_cache(date)

        Progress.step_completed(run_id, :fetch_schedule,
          processed: length(games),
          total: length(games),
          for_date: date
        )

        {:ok, length(games)}

      {:error, reason} = err ->
        Logger.warning("FetchScheduleWorker error: #{inspect(reason)}")

        Progress.step_failed(run_id, :fetch_schedule, reason,
          current_item: "MLB schedule #{Date.to_iso8601(date)}",
          endpoint: "https://statsapi.mlb.com/api/v1/schedule",
          http_status: extract_http_status(reason),
          for_date: date
        )

        err
    end
  rescue
    e ->
      Progress.step_failed(run_id, :fetch_schedule, e,
        current_item: "MLB schedule #{Date.to_iso8601(date)}",
        endpoint: "https://statsapi.mlb.com/api/v1/schedule",
        for_date: date
      )

      reraise e, __STACKTRACE__
  end

  defp upsert_game(g) do
    game_date = parse_date(g["game_date"])
    game_dt = parse_datetime(g["game_datetime"])

    %ScheduledGame{}
    |> ScheduledGame.changeset(%{
      game_id: g["game_id"],
      game_date: game_date,
      game_datetime: game_dt,
      away_mlb_id: g["away_mlb_id"],
      home_mlb_id: g["home_mlb_id"],
      away_name: g["away_name"],
      home_name: g["home_name"],
      away_probable_pitcher: g["away_probable_pitcher"],
      home_probable_pitcher: g["home_probable_pitcher"],
      venue_id: g["venue_id"],
      venue_name: g["venue_name"]
    })
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :game_id)

    # Also write to mlb.games for training-data joins.
    %Game{}
    |> Game.changeset(%{
      game_id: g["game_id"],
      game_date: game_date,
      game_datetime: game_dt,
      status: g["status"],
      away_mlb_id: g["away_mlb_id"],
      home_mlb_id: g["home_mlb_id"],
      away_name: g["away_name"],
      home_name: g["home_name"],
      away_starter_mlb_id: g["away_starter_mlb_id"],
      home_starter_mlb_id: g["home_starter_mlb_id"],
      venue_id: g["venue_id"],
      venue_name: g["venue_name"]
    })
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :game_id)

    upsert_venue(g)
  end

  # Upserts public.venues using MLB external_id so ForecastWeatherWorker's
  # coords_from_db/1 fallback can resolve venues outside the 32-stadium static
  # map (spring training facilities, neutral-site games, etc.).
  defp upsert_venue(%{"venue_id" => ext_id, "venue_name" => name} = g)
       when is_integer(ext_id) and is_binary(name) do
    Repo.query!(
      """
      INSERT INTO venues (
        id, name, city, state, latitude, longitude, external_id,
        inserted_at, updated_at
      ) VALUES (
        gen_random_uuid(), $1, $2, $3, $4, $5, $6, NOW(), NOW()
      )
      ON CONFLICT (external_id) DO UPDATE SET
        name = EXCLUDED.name,
        city = COALESCE(EXCLUDED.city, venues.city),
        state = COALESCE(EXCLUDED.state, venues.state),
        latitude = COALESCE(EXCLUDED.latitude, venues.latitude),
        longitude = COALESCE(EXCLUDED.longitude, venues.longitude),
        updated_at = NOW()
      """,
      [name, g["venue_city"], g["venue_state"], g["venue_latitude"], g["venue_longitude"], ext_id]
    )
  rescue
    e -> Logger.warning("FetchScheduleWorker.upsert_venue failed: #{inspect(e)}")
  end

  defp upsert_venue(_), do: :ok

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

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_run_id(nil), do: nil
  defp parse_run_id(s) when is_binary(s), do: s

  defp invalidate_game_card_cache(%Date{} = date) do
    pattern = "sf:data:game_card:player:*:#{Date.to_iso8601(date)}"
    SportsFanatic.Cache.del_pattern(pattern)
  rescue
    _ -> :ok
  end
end
