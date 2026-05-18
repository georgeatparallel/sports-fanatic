defmodule SportsFanatic.Workers.ForecastWeatherWorker do
  @moduledoc """
  Per-venue Open-Meteo weather lookup for `date`'s scheduled games.
  Upserts into `mlb.game_weather_forecast`. Concurrency:
  `weather_concurrency` (default 8).

  Two modes:
  - `:forecast` (default) — calls `OpenMeteo.fetch_forecast/4`. Used for
    today's pipeline.
  - `:archive` — calls `OpenMeteo.fetch_archive/4`. Used by
    `InitialSeedWorker` for past dates.
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 3,
    unique: [period: 3600, fields: [:worker, :args]]

  alias SportsFanatic.ExternalApis.OpenMeteo
  alias SportsFanatic.Predictions.{Progress, Stadiums}
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    date = parse_date(args["date"]) || SportsFanatic.DateHelper.today()
    run_id = parse_run_id(args["pipeline_run_id"])
    mode = parse_mode(args["mode"])
    run_for_date(date, run_id: run_id, mode: mode)
  end

  @spec run_for_date(Date.t(), keyword()) :: {:ok, integer} | {:error, term}
  def run_for_date(%Date{} = date, opts \\ []) do
    run_id = Keyword.get(opts, :run_id)
    mode = Keyword.get(opts, :mode, :forecast)

    concurrency =
      Application.get_env(:sports_fanatic, :predictions, [])[:weather_concurrency] || 8

    venues = candidates(date)
    total = length(venues)
    Logger.info("ForecastWeatherWorker: #{total} venues for #{date} mode=#{mode}")

    Progress.step_started(run_id, :forecast_weather, total: total)

    started = System.monotonic_time(:millisecond)

    {count, errors} =
      venues
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {entry, idx} -> forecast_one(entry, date, mode, run_id, idx, total) end,
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
        Progress.step_completed(run_id, :forecast_weather,
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
    SELECT DISTINCT venue_id, game_datetime
      FROM mlb.scheduled_games
     WHERE game_date = $1 AND venue_id IS NOT NULL
    """

    Repo.query!(sql, [date]).rows
    |> Enum.map(fn [vid, dt] -> %{venue_id: vid, game_datetime: dt} end)
  end

  defp forecast_one(%{venue_id: venue_id, game_datetime: game_dt}, date, mode, run_id, idx, total) do
    coords = Stadiums.coordinates(venue_id) || coords_from_db(venue_id)

    cond do
      is_nil(coords) ->
        Progress.item_progress(run_id, :forecast_weather, idx,
          total: total,
          current_item: "venue=#{venue_id} — no coords",
          item_id: venue_id
        )

        :ok

      is_nil(game_dt) ->
        Progress.item_progress(run_id, :forecast_weather, idx,
          total: total,
          current_item: "venue=#{venue_id} — no datetime",
          item_id: venue_id
        )

        :ok

      true ->
        do_forecast(coords, venue_id, game_dt, date, mode, run_id, idx, total)
    end
  rescue
    e ->
      Progress.step_failed(run_id, :forecast_weather, e,
        current_item: "venue=#{venue_id}",
        item_id: venue_id,
        endpoint: open_meteo_endpoint(mode),
        processed: idx,
        total: total
      )

      {:error, e}
  end

  defp do_forecast(coords, venue_id, game_dt, date, mode, run_id, idx, total) do
    fetch_fn =
      case mode do
        :archive -> fn -> OpenMeteo.fetch_archive(coords.lat, coords.lon, date, date) end
        _ -> fn -> OpenMeteo.fetch_forecast(coords.lat, coords.lon, date, 2) end
      end

    case fetch_fn.() do
      {:ok, hourly} ->
        game_dt_proper = ensure_datetime(game_dt)

        case OpenMeteo.extract_at_game_time(hourly, game_dt_proper) do
          nil ->
            Progress.item_progress(run_id, :forecast_weather, idx,
              total: total,
              current_item: "venue=#{venue_id} — no hour match",
              item_id: venue_id
            )

            :ok

          w ->
            upsert(venue_id, game_dt_proper, w)

            Progress.item_progress(run_id, :forecast_weather, idx,
              total: total,
              current_item: "venue=#{venue_id}",
              item_id: venue_id
            )

            :ok
        end

      {:error, reason} ->
        Progress.step_failed(run_id, :forecast_weather, reason,
          current_item: "venue=#{venue_id}",
          item_id: venue_id,
          endpoint: open_meteo_endpoint(mode),
          http_status: extract_http_status(reason),
          processed: idx,
          total: total
        )

        {:error, reason}
    end
  end

  defp open_meteo_endpoint(:archive), do: "https://archive-api.open-meteo.com/v1/archive"
  defp open_meteo_endpoint(_), do: "https://api.open-meteo.com/v1/forecast"

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

  defp parse_mode("archive"), do: :archive
  defp parse_mode(:archive), do: :archive
  defp parse_mode(_), do: :forecast
end
