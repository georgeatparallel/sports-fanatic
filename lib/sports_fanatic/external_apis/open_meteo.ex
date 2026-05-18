defmodule SportsFanatic.ExternalApis.OpenMeteo do
  @moduledoc """
  Open-Meteo client for forecast and archive weather.

  Free tier requires no API key; when `OPENMETEO_API_KEY` is set we append
  `&apikey=…` for paid users.

  Only HTTPS URLs are used (SEC-PRED-001).

  ## Retry behaviour

  Transient failures (HTTP 429, 5xx, `:timeout`, `:closed`) trigger up to
  three attempts with exponential backoff (500ms, 1500ms, 4500ms). On 401
  or 403 with an API key set, the client logs a one-shot deprecation
  warning and retries unauthenticated (free tier still works).

  Timeout is configurable via
  `Application.get_env(:sports_fanatic, :predictions)[:open_meteo_timeout_ms]`
  (default 15000).
  """

  require Logger

  @forecast_url "https://api.open-meteo.com/v1/forecast"
  @archive_url "https://archive-api.open-meteo.com/v1/archive"
  @default_timeout_ms 15_000
  @backoff_ms [500, 1500, 4500]
  @auth_failure_marker {__MODULE__, :auth_failure_warned}

  @hourly_fields "temperature_2m,wind_speed_10m,wind_direction_10m,precipitation,weathercode,surface_pressure"

  @spec fetch_forecast(float, float, Date.t(), pos_integer) ::
          {:ok, map()} | {:error, term()}
  def fetch_forecast(lat, lon, %Date{} = start_date, days \\ 2)
      when is_number(lat) and is_number(lon) do
    end_date = Date.add(start_date, days)

    params = %{
      "latitude" => lat,
      "longitude" => lon,
      "start_date" => Date.to_iso8601(start_date),
      "end_date" => Date.to_iso8601(end_date),
      "hourly" => @hourly_fields,
      "timezone" => "UTC"
    }

    fetch(@forecast_url, params)
  end

  @doc """
  Single-day archive fetch. Delegates to the 4-arity variant.
  """
  @spec fetch_archive(float, float, Date.t()) :: {:ok, map()} | {:error, term()}
  def fetch_archive(lat, lon, %Date{} = target_date),
    do: fetch_archive(lat, lon, target_date, target_date)

  @doc """
  Date-range archive fetch. The 4-arity introduced for historical backfill
  by `InitialSeedWorker` — keeps the 3-arity above untouched for callers
  that only need a single day.
  """
  @spec fetch_archive(float, float, Date.t(), Date.t()) ::
          {:ok, map()} | {:error, term()}
  def fetch_archive(lat, lon, %Date{} = start_date, %Date{} = end_date)
      when is_number(lat) and is_number(lon) do
    params = %{
      "latitude" => lat,
      "longitude" => lon,
      "start_date" => Date.to_iso8601(start_date),
      "end_date" => Date.to_iso8601(end_date),
      "hourly" => @hourly_fields,
      "timezone" => "UTC"
    }

    fetch(@archive_url, params)
  end

  @doc """
  Picks the weather hour matching `game_dt` (truncated to the hour) from
  a hourly response map. Returns a flat map of values or nil.
  """
  @spec extract_at_game_time(map(), DateTime.t()) :: map() | nil
  def extract_at_game_time(%{"time" => times} = hourly, %DateTime{} = game_dt)
      when is_list(times) do
    target = game_dt |> DateTime.truncate(:second) |> format_hour()

    case Enum.find_index(times, &(&1 == target)) do
      nil ->
        nil

      idx ->
        %{
          "temperature_2m" => Enum.at(hourly["temperature_2m"] || [], idx),
          "wind_speed_10m" => Enum.at(hourly["wind_speed_10m"] || [], idx),
          "wind_direction_10m" => Enum.at(hourly["wind_direction_10m"] || [], idx),
          "precipitation" => Enum.at(hourly["precipitation"] || [], idx),
          "weathercode" => Enum.at(hourly["weathercode"] || [], idx),
          "surface_pressure" => Enum.at(hourly["surface_pressure"] || [], idx)
        }
    end
  end

  def extract_at_game_time(_, _), do: nil

  ## --- Internals ----------------------------------------------------------

  defp fetch(base, params) do
    do_fetch(base, params, true, @backoff_ms)
  end

  # The `auth?` flag lets us re-issue the request without the apikey if
  # auth fails. The `delays` list is the remaining backoff schedule.
  defp do_fetch(base, params, auth?, delays) do
    params_with_auth =
      if auth?, do: maybe_with_api_key(params), else: Map.delete(params, "apikey")

    url = base <> "?" <> URI.encode_query(params_with_auth)

    if String.starts_with?(url, "https://") do
      case Req.get(url, receive_timeout: timeout_ms()) do
        {:ok, %{status: 200, body: %{"hourly" => hourly}}} ->
          {:ok, hourly}

        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, %{"hourly" => hourly}} -> {:ok, hourly}
            _ -> {:error, :invalid_response}
          end

        {:ok, %{status: status}} when status in [401, 403] ->
          if auth? and api_key_set?() do
            warn_auth_failure_once()
            do_fetch(base, params, false, delays)
          else
            {:error, {:http_error, status}}
          end

        {:ok, %{status: status}} when status == 429 or (status >= 500 and status < 600) ->
          maybe_retry({:http_error, status}, base, params, auth?, delays)

        {:ok, %{status: status}} ->
          {:error, {:http_error, status}}

        {:error, %{reason: reason}} when reason in [:timeout, :closed] ->
          maybe_retry({:transport_error, reason}, base, params, auth?, delays)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :insecure_url}
    end
  end

  defp maybe_retry(err, _base, _params, _auth?, []), do: {:error, err}

  defp maybe_retry(err, base, params, auth?, [delay | rest]) do
    Logger.warning(
      "OpenMeteo: transient error #{inspect(err)} — retrying in #{delay}ms (#{length(rest)} retries left)"
    )

    Process.sleep(delay)
    do_fetch(base, params, auth?, rest)
  end

  defp maybe_with_api_key(params) do
    case Application.get_env(:sports_fanatic, :predictions, [])[:open_meteo_api_key] do
      key when is_binary(key) and key != "" -> Map.put(params, "apikey", key)
      _ -> params
    end
  end

  defp api_key_set? do
    case Application.get_env(:sports_fanatic, :predictions, [])[:open_meteo_api_key] do
      key when is_binary(key) and key != "" -> true
      _ -> false
    end
  end

  defp timeout_ms do
    Application.get_env(:sports_fanatic, :predictions, [])[:open_meteo_timeout_ms] ||
      @default_timeout_ms
  end

  defp warn_auth_failure_once do
    case :persistent_term.get(@auth_failure_marker, :unset) do
      :unset ->
        :persistent_term.put(@auth_failure_marker, true)

        Logger.warning(
          "OpenMeteo: API key rejected (401/403). Check the OPENMETEO_API_KEY plan. " <>
            "Falling back to unauthenticated requests (free tier)."
        )

      _ ->
        :ok
    end
  end

  defp format_hour(%DateTime{} = dt) do
    # Open-Meteo hourly values are keyed like "2026-05-17T19:00"
    Calendar.strftime(dt, "%Y-%m-%dT%H:00")
  end
end
