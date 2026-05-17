defmodule SportsFanatic.ExternalApis.MlbStats do
  @moduledoc """
  HTTP client for the public MLB Stats API (`statsapi.mlb.com`).

  Replaces the Python `statsapi` wrapper. Each function makes a single
  retried HTTPS call via `Req` with a small inter-call sleep to stay
  polite — concurrency is bounded by the calling `Task.async_stream`.

  ## Endpoints

  - `fetch_schedule/1` — `/api/v1/schedule?sportId=1&date=YYYY-MM-DD&hydrate=probablePitcher,linescore,venue,team`
  - `fetch_boxscore/1` — `/api/v1/game/:game_id/boxscore`
  - `fetch_pitcher_season_stats/2` — `/api/v1/people/:id/stats?stats=season&group=pitching&season=YYYY`
  - `fetch_player_statcast/2` — `https://baseballsavant.mlb.com/statcast_search/...` (CSV)
  - `fetch_batter_vs_pitcher/3` — `/api/v1/people/:id/stats?stats=vsPlayer&group=hitting&opposingPlayerId=...`
  - `lookup_player/1` — `/api/v1/people/search?names=...`
  """

  require Logger

  @base "https://statsapi.mlb.com/api/v1"
  @savant_base "https://baseballsavant.mlb.com"
  @throttle_ms 50
  @timeout 15_000

  ## --- Public API -----------------------------------------------------------

  @spec fetch_schedule(Date.t() | String.t()) :: {:ok, [map()]} | {:error, term()}
  def fetch_schedule(date) do
    date_str = to_iso8601(date)

    url =
      "#{@base}/schedule" <>
        "?sportId=1&date=#{date_str}" <>
        "&hydrate=probablePitcher,linescore,venue,team"

    case do_get(url) do
      {:ok, body} -> {:ok, parse_schedule(body)}
      err -> err
    end
  end

  @spec fetch_boxscore(integer()) :: {:ok, map()} | {:error, term()}
  def fetch_boxscore(game_id) when is_integer(game_id) do
    do_get("#{@base}/game/#{game_id}/boxscore")
  end

  @spec fetch_pitcher_season_stats(integer(), integer()) :: {:ok, map()} | {:error, term()}
  def fetch_pitcher_season_stats(player_mlb_id, season) when is_integer(player_mlb_id) do
    url =
      "#{@base}/people/#{player_mlb_id}/stats" <>
        "?stats=season&group=pitching&season=#{season}"

    case do_get(url) do
      {:ok, body} -> {:ok, parse_pitcher_stats(body)}
      err -> err
    end
  end

  @spec fetch_player_statcast(integer(), integer()) :: {:ok, map()} | {:error, term()}
  def fetch_player_statcast(player_mlb_id, season) when is_integer(player_mlb_id) do
    # Baseball Savant aggregates. We only need exit velocity / hard-hit pct.
    # Players sub-page returns JSON for the "expected stats" leaderboard;
    # the simpler endpoint is /statcast/leaderboard via /savant/statcast.
    # When unavailable, return an empty map so the caller treats it as missing.
    url =
      "#{@savant_base}/statcast-search/csv" <>
        "?all=true&hfPT=&hfAB=&hfBBT=&player_id=#{player_mlb_id}&year=#{season}"

    case do_get(url, decode: false) do
      {:ok, csv_body} when is_binary(csv_body) ->
        {:ok, summarize_statcast_csv(csv_body)}

      {:ok, _} ->
        {:ok, %{}}

      {:error, _} = err ->
        err
    end
  end

  @spec fetch_batter_vs_pitcher(integer(), integer(), integer()) ::
          {:ok, map()} | {:error, term()}
  def fetch_batter_vs_pitcher(batter_mlb_id, pitcher_mlb_id, season) do
    url =
      "#{@base}/people/#{batter_mlb_id}/stats" <>
        "?stats=vsPlayer&group=hitting&season=#{season}" <>
        "&opposingPlayerId=#{pitcher_mlb_id}"

    case do_get(url) do
      {:ok, body} -> {:ok, parse_bvp(body)}
      err -> err
    end
  end

  @spec lookup_player(String.t()) :: {:ok, [map()]} | {:error, term()}
  def lookup_player(name) when is_binary(name) do
    encoded = URI.encode_www_form(name)
    url = "#{@base}/people/search?names=#{encoded}"

    case do_get(url) do
      {:ok, %{"people" => people}} -> {:ok, people}
      {:ok, _} -> {:ok, []}
      err -> err
    end
  end

  ## --- Parsers --------------------------------------------------------------

  defp parse_schedule(%{"dates" => dates}) when is_list(dates) do
    dates
    |> Enum.flat_map(fn d -> Map.get(d, "games", []) end)
    |> Enum.map(&parse_game/1)
  end

  defp parse_schedule(_), do: []

  defp parse_game(g) do
    teams = Map.get(g, "teams", %{})
    away = Map.get(teams, "away", %{})
    home = Map.get(teams, "home", %{})
    venue = Map.get(g, "venue", %{})

    %{
      "game_id" => Map.get(g, "gamePk"),
      "game_date" => Map.get(g, "officialDate") || Map.get(g, "gameDate"),
      "game_datetime" => Map.get(g, "gameDate"),
      "status" => get_in(g, ["status", "abstractGameState"]),
      "away_mlb_id" => get_in(away, ["team", "id"]),
      "home_mlb_id" => get_in(home, ["team", "id"]),
      "away_name" => get_in(away, ["team", "name"]),
      "home_name" => get_in(home, ["team", "name"]),
      "away_probable_pitcher" => get_in(away, ["probablePitcher", "fullName"]),
      "home_probable_pitcher" => get_in(home, ["probablePitcher", "fullName"]),
      "away_starter_mlb_id" => get_in(away, ["probablePitcher", "id"]),
      "home_starter_mlb_id" => get_in(home, ["probablePitcher", "id"]),
      "venue_id" => Map.get(venue, "id"),
      "venue_name" => Map.get(venue, "name")
    }
  end

  defp parse_pitcher_stats(%{"stats" => stats}) when is_list(stats) do
    splits =
      stats
      |> Enum.flat_map(fn s -> Map.get(s, "splits", []) end)

    case splits do
      [first | _] ->
        stat = Map.get(first, "stat", %{})

        %{
          "batting_avg_against" => to_float(stat["avg"]),
          "k_per_9" => to_float(stat["strikeoutsPer9Inn"]),
          "whip" => to_float(stat["whip"]),
          "bb_per_9" => to_float(stat["walksPer9Inn"]),
          "hr_per_9" => to_float(stat["homeRunsPer9"]),
          "era" => to_float(stat["era"]),
          "games_played" => to_int(stat["gamesPlayed"]),
          "games_started" => to_int(stat["gamesStarted"]),
          "innings_pitched" => to_float(stat["inningsPitched"]),
          "hits_allowed" => to_int(stat["hits"]),
          "hr_allowed" => to_int(stat["homeRuns"]),
          "bb_allowed" => to_int(stat["baseOnBalls"]),
          "strikeouts" => to_int(stat["strikeOuts"])
        }

      _ ->
        %{}
    end
  end

  defp parse_pitcher_stats(_), do: %{}

  defp parse_bvp(%{"stats" => stats}) when is_list(stats) do
    splits = stats |> Enum.flat_map(fn s -> Map.get(s, "splits", []) end)

    case splits do
      [first | _] ->
        stat = Map.get(first, "stat", %{})

        %{
          "at_bats" => to_int(stat["atBats"]),
          "hits" => to_int(stat["hits"]),
          "home_runs" => to_int(stat["homeRuns"]),
          "batting_avg" => to_float(stat["avg"])
        }

      _ ->
        %{"at_bats" => 0, "hits" => 0, "home_runs" => 0, "batting_avg" => nil}
    end
  end

  defp parse_bvp(_), do: %{"at_bats" => 0, "hits" => 0, "home_runs" => 0, "batting_avg" => nil}

  defp summarize_statcast_csv(csv) when is_binary(csv) do
    # The Savant CSV is large; summarize columns we care about.
    # We do a best-effort lightweight parse: when it isn't CSV we just no-op.
    lines = String.split(csv, "\n", trim: true)

    case lines do
      [header | rows] when rows != [] ->
        cols = String.split(header, ",")
        ev_idx = Enum.find_index(cols, &(&1 == "launch_speed"))
        hh_idx = Enum.find_index(cols, &(&1 == "launch_speed"))
        # No hard-hit boolean in this CSV — fall back to deriving from EV >= 95
        ev_vals =
          if ev_idx do
            rows
            |> Enum.flat_map(fn row ->
              parts = String.split(row, ",")

              case Enum.at(parts, ev_idx) do
                nil -> []
                "" -> []
                v -> [to_float(v)]
              end
            end)
            |> Enum.reject(&is_nil/1)
          else
            []
          end

        if ev_vals == [] do
          %{}
        else
          avg = Enum.sum(ev_vals) / length(ev_vals)
          max_v = Enum.max(ev_vals)
          hard = ev_vals |> Enum.count(&(&1 >= 95.0)) |> Kernel./(length(ev_vals))

          %{
            "avg_exit_velocity" => Float.round(avg, 2),
            "max_exit_velocity" => Float.round(max_v, 2),
            "hard_hit_pct" => Float.round(hard, 4)
          }
          # Suppress unused variable warning by keeping hh_idx in scope
          |> tap(fn _ -> _ = hh_idx end)
        end

      _ ->
        %{}
    end
  end

  defp summarize_statcast_csv(_), do: %{}

  ## --- HTTP helpers ---------------------------------------------------------

  defp do_get(url, opts \\ []) do
    decode? = Keyword.get(opts, :decode, true)
    Process.sleep(@throttle_ms)

    case Req.get(url, receive_timeout: @timeout, connect_options: [timeout: @timeout]) do
      {:ok, %{status: 200, body: body}} ->
        if decode?, do: {:ok, decode(body)}, else: {:ok, body}

      {:ok, %{status: status}} when status in 500..599 ->
        # Single retry on 5xx
        Process.sleep(150)

        case Req.get(url, receive_timeout: @timeout) do
          {:ok, %{status: 200, body: body}} ->
            if decode?, do: {:ok, decode(body)}, else: {:ok, body}

          {:ok, %{status: s}} ->
            {:error, {:http_error, s}}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, parsed} -> parsed
      _ -> body
    end
  end

  defp decode(body), do: body

  defp to_iso8601(%Date{} = d), do: Date.to_iso8601(d)
  defp to_iso8601(s) when is_binary(s), do: s

  defp to_float(nil), do: nil
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp to_float(_), do: nil

  defp to_int(nil), do: nil
  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp to_int(_), do: nil
end
