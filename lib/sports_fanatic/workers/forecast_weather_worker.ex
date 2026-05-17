defmodule SportsFanatic.Workers.ForecastWeatherWorker do
  @moduledoc """
  Per-venue Open-Meteo forecast lookup for today's scheduled games.
  Upserts into `mlb.game_weather_forecast`. Concurrency:
  `weather_concurrency` (default 8).
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]

  alias SportsFanatic.ExternalApis.OpenMeteo
  alias SportsFanatic.Predictions.Stadiums
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
      Application.get_env(:sports_fanatic, :predictions, [])[:weather_concurrency] || 8

    venues = candidates(date)
    Logger.info("ForecastWeatherWorker: #{length(venues)} venues for #{date}")

    count =
      venues
      |> Task.async_stream(
        fn entry -> forecast_one(entry, date) end,
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

  defp candidates(date) do
    sql = """
    SELECT DISTINCT venue_id, game_datetime
      FROM mlb.scheduled_games
     WHERE game_date = $1 AND venue_id IS NOT NULL
    """

    Repo.query!(sql, [date]).rows
    |> Enum.map(fn [vid, dt] -> %{venue_id: vid, game_datetime: dt} end)
  end

  defp forecast_one(%{venue_id: venue_id, game_datetime: game_dt}, date) do
    coords = Stadiums.coordinates(venue_id) || coords_from_db(venue_id)

    cond do
      is_nil(coords) ->
        :ok

      is_nil(game_dt) ->
        :ok

      true ->
        case OpenMeteo.fetch_forecast(coords.lat, coords.lon, date, 2) do
          {:ok, hourly} ->
            game_dt_proper = ensure_datetime(game_dt)

            case OpenMeteo.extract_at_game_time(hourly, game_dt_proper) do
              nil ->
                :ok

              w ->
                upsert(venue_id, game_dt_proper, w)
                :ok
            end

          _ ->
            :ok
        end
    end
  rescue
    e ->
      Logger.warning("ForecastWeatherWorker venue=#{venue_id} error=#{inspect(e)}")
      :ok
  end

  defp coords_from_db(_venue_id), do: nil

  defp ensure_datetime(%DateTime{} = dt), do: dt

  defp ensure_datetime(%NaiveDateTime{} = ndt) do
    {:ok, dt} = DateTime.from_naive(ndt, "Etc/UTC")
    dt
  end

  defp ensure_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp upsert(venue_id, game_dt, w) do
    Repo.query!(
      """
      INSERT INTO mlb.game_weather_forecast (
        venue_id, game_datetime, temperature_2m, wind_speed_10m, wind_direction_10m,
        precipitation, weathercode, surface_pressure, inserted_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())
      ON CONFLICT (venue_id, game_datetime) DO UPDATE SET
        temperature_2m = EXCLUDED.temperature_2m,
        wind_speed_10m = EXCLUDED.wind_speed_10m,
        wind_direction_10m = EXCLUDED.wind_direction_10m,
        precipitation = EXCLUDED.precipitation,
        weathercode = EXCLUDED.weathercode,
        surface_pressure = EXCLUDED.surface_pressure,
        updated_at = NOW()
      """,
      [
        venue_id,
        game_dt,
        w["temperature_2m"],
        w["wind_speed_10m"],
        w["wind_direction_10m"],
        w["precipitation"],
        w["weathercode"],
        w["surface_pressure"]
      ]
    )
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
