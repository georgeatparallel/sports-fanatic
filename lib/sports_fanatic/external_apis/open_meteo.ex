defmodule SportsFanatic.ExternalApis.OpenMeteo do
  @moduledoc """
  Open-Meteo client for forecast and archive weather.

  Free tier requires no API key; when `OPENMETEO_API_KEY` is set we append
  `&apikey=…` for paid users.

  Only HTTPS URLs are used (SEC-PRED-001).
  """

  require Logger

  @forecast_url "https://api.open-meteo.com/v1/forecast"
  @archive_url "https://archive-api.open-meteo.com/v1/archive"
  @timeout 15_000

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

  @spec fetch_archive(float, float, Date.t()) :: {:ok, map()} | {:error, term()}
  def fetch_archive(lat, lon, %Date{} = target_date)
      when is_number(lat) and is_number(lon) do
    params = %{
      "latitude" => lat,
      "longitude" => lon,
      "start_date" => Date.to_iso8601(target_date),
      "end_date" => Date.to_iso8601(target_date),
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

  defp fetch(base, params) do
    params = maybe_with_api_key(params)
    url = base <> "?" <> URI.encode_query(params)

    if not String.starts_with?(url, "https://") do
      {:error, :insecure_url}
    else
      case Req.get(url, receive_timeout: @timeout) do
        {:ok, %{status: 200, body: %{"hourly" => hourly}}} ->
          {:ok, hourly}

        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, %{"hourly" => hourly}} -> {:ok, hourly}
            _ -> {:error, :invalid_response}
          end

        {:ok, %{status: status}} ->
          {:error, {:http_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp maybe_with_api_key(params) do
    case Application.get_env(:sports_fanatic, :predictions, [])[:open_meteo_api_key] do
      key when is_binary(key) and key != "" -> Map.put(params, "apikey", key)
      _ -> params
    end
  end

  defp format_hour(%DateTime{} = dt) do
    # Open-Meteo hourly values are keyed like "2026-05-17T19:00"
    Calendar.strftime(dt, "%Y-%m-%dT%H:00")
  end
end
