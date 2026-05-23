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

  alias SportsFanatic.ExternalApis.{MlbStats, OpenMeteo}
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

    Progress.step_started(run_id, :forecast_weather, total: total, for_date: date)

    started = System.monotonic_time(:millisecond)

    # Per-venue failures are recorded as item events but DO NOT halt the step.
    # An archive backfill of 1909 dates can't be killed by a single transient
    # Open-Meteo error; matches the original Python step which logged + continued.
    {count, skipped} =
      venues
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {entry, idx} -> forecast_one(entry, date, mode, run_id, idx, total) end,
        max_concurrency: concurrency,
        timeout: 15_000,
        on_timeout: :kill_task
      )
      |> Enum.reduce({0, 0}, fn
        {:ok, :ok}, {n, s} -> {n + 1, s}
        {:ok, :skipped}, {n, s} -> {n, s + 1}
        _, {n, s} -> {n, s + 1}
      end)

    elapsed = System.monotonic_time(:millisecond) - started

    invalidate_game_card_cache(date)

    Progress.step_completed(run_id, :forecast_weather,
      processed: count,
      total: total,
      elapsed_ms: elapsed,
      for_date: date,
      note: skipped > 0 && "skipped=#{skipped}"
    )

    {:ok, count}
  end

  defp invalidate_game_card_cache(%Date{} = date) do
    pattern = "sf:data:game_card:player:*:#{Date.to_iso8601(date)}"
    SportsFanatic.Cache.del_pattern(pattern)
  rescue
    _ -> :ok
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
          item_id: venue_id,
          for_date: date
        )

        :skipped

      is_nil(game_dt) ->
        Progress.item_progress(run_id, :forecast_weather, idx,
          total: total,
          current_item: "venue=#{venue_id} — no datetime",
          item_id: venue_id,
          for_date: date
        )

        :skipped

      true ->
        do_forecast(coords, venue_id, game_dt, date, mode, run_id, idx, total)
    end
  rescue
    e ->
      # Record but DON'T halt — the next venue can still try.
      Progress.item_progress(run_id, :forecast_weather, idx,
        total: total,
        current_item: "venue=#{venue_id} — exception: #{Exception.message(e)}",
        item_id: venue_id,
        for_date: date
      )

      :skipped
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
              item_id: venue_id,
              for_date: date
            )

            :skipped

          w ->
            upsert(venue_id, game_dt_proper, w)

            Progress.item_progress(run_id, :forecast_weather, idx,
              total: total,
              current_item: "venue=#{venue_id}",
              item_id: venue_id,
              for_date: date
            )

            :ok
        end

      {:error, reason} ->
        # Per-venue Open-Meteo failures are skipped, not fatal. Original
        # Python (steps/forecast_weather.py:46-50) logged + continued.
        Progress.item_progress(run_id, :forecast_weather, idx,
          total: total,
          current_item: "venue=#{venue_id} — fetch error: #{inspect(reason)}",
          item_id: venue_id,
          for_date: date
        )

        :skipped
    end
  end

  # Fallback when a venue isn't in `Stadiums.coordinates/1`. Tries the
  # `public.venues` cache first; on a miss, hits MLB Stats
  # `/v1/venues/{id}?hydrate=location`, upserts the result, and returns it.
  # Net effect: every MLB venue resolves to coords after at most one lookup
  # per process, and the answer is permanently cached in `public.venues`.
  defp coords_from_db(nil), do: nil

  defp coords_from_db(external_id) when is_integer(external_id) do
    case query_cached_coords(external_id) do
      %{} = coords -> coords
      nil -> fetch_and_cache_coords(external_id)
    end
  end

  defp query_cached_coords(external_id) do
    case Repo.query!(
           """
           SELECT latitude, longitude FROM venues
            WHERE external_id = $1 AND latitude IS NOT NULL AND longitude IS NOT NULL
            LIMIT 1
           """,
           [external_id]
         ) do
      %{rows: [[lat, lon] | _]} when is_number(lat) and is_number(lon) ->
        %{lat: lat, lon: lon}

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp fetch_and_cache_coords(external_id) do
    case MlbStats.fetch_venue(external_id) do
      {:ok,
       %{
         "venue_id" => ^external_id,
         "venue_name" => name,
         "venue_latitude" => lat,
         "venue_longitude" => lon
       } = venue}
      when is_binary(name) and is_number(lat) and is_number(lon) ->
        upsert_venue(venue)
        %{lat: lat, lon: lon}

      {:ok, %{"venue_name" => name}} when is_binary(name) ->
        # MLB Stats returned the venue but with no coordinates — extremely rare
        # for sportId=1 venues. Log so we can investigate which one.
        Logger.warning(
          "ForecastWeatherWorker: MLB Stats returned no coords for venue_id=#{external_id} name=#{name}"
        )

        nil

      {:error, reason} ->
        Logger.warning(
          "ForecastWeatherWorker: MLB Stats venue lookup failed for venue_id=#{external_id}: #{inspect(reason)}"
        )

        nil

      _ ->
        nil
    end
  rescue
    e ->
      Logger.warning(
        "ForecastWeatherWorker.fetch_and_cache_coords/1 crashed for venue_id=#{external_id}: #{inspect(e)}"
      )

      nil
  end

  defp upsert_venue(%{"venue_id" => ext_id, "venue_name" => name} = v) do
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
      [name, v["venue_city"], v["venue_state"], v["venue_latitude"], v["venue_longitude"], ext_id]
    )
  rescue
    e ->
      Logger.warning("ForecastWeatherWorker.upsert_venue failed: #{inspect(e)}")
      :ok
  end

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

  defp parse_run_id(nil), do: nil
  defp parse_run_id(s) when is_binary(s), do: s

  defp parse_mode("archive"), do: :archive
  defp parse_mode(:archive), do: :archive
  defp parse_mode(_), do: :forecast
end
