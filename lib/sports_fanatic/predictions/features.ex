defmodule SportsFanatic.Predictions.Features do
  @moduledoc """
  Feature engineering for hit-prediction.

  Ports the 44-feature schema from `hit_features.py`. Pure transforms; all
  DB work is delegated to `FeatureLoader` so this module is easy to unit-test.
  """

  alias SportsFanatic.Predictions.{FeatureLoader, ParkFactors}

  @feature_cols ~w(
    avg_7d avg_14d avg_30d avg_season
    obp_7d obp_14d obp_30d obp_season
    slg_7d slg_14d slg_30d slg_season
    k_rate_7d k_rate_14d k_rate_30d
    bb_rate_30d
    games_7d games_14d games_30d games_season
    pitcher_baa pitcher_k_per_9 pitcher_whip pitcher_bb_per_9
    pitcher_hand_L pitcher_hand_R
    pitcher_recent_era_5g pitcher_recent_k9_5g pitcher_recent_whip_5g
    bvp_avg bvp_at_bats
    avg_exit_velocity hard_hit_pct
    park_hit_factor
    temperature wind_speed precipitation surface_pressure
    is_home batting_order month
    days_since_last_game games_last_7d
    k_rate_x_pitcher_k9
  )

  @doc "Feature columns, in canonical order. Both training and inference must use this order."
  def feature_cols, do: @feature_cols

  @doc """
  Build a feature row for one player on `target_date`.

  Opts:
    * `:venue_id` — integer
    * `:pitcher_mlb_id` — integer | nil
    * `:is_home` — boolean
    * `:batting_order` — integer | nil
    * `:weather` — map ("temperature_2m", "wind_speed_10m", ...) | nil
  """
  @spec build_inference_row(integer, Date.t(), keyword) :: map()
  def build_inference_row(player_mlb_id, %Date{} = target_date, opts) do
    venue_id = Keyword.get(opts, :venue_id)
    pitcher_mlb_id = Keyword.get(opts, :pitcher_mlb_id)
    is_home = Keyword.get(opts, :is_home)
    batting_order = Keyword.get(opts, :batting_order)
    weather = Keyword.get(opts, :weather)
    season = target_date.year

    r7 = FeatureLoader.rolling_stats(player_mlb_id, target_date, 7)
    r14 = FeatureLoader.rolling_stats(player_mlb_id, target_date, 14)
    r30 = FeatureLoader.rolling_stats(player_mlb_id, target_date, 30)
    rs = FeatureLoader.season_stats(player_mlb_id, target_date)

    pitcher = FeatureLoader.opposing_pitcher(pitcher_mlb_id, season)
    recent = FeatureLoader.pitcher_recent_form(pitcher_mlb_id, target_date, 5)
    bvp = FeatureLoader.bvp_features(player_mlb_id, pitcher_mlb_id, season)
    statcast = FeatureLoader.statcast(player_mlb_id, season)
    situational = FeatureLoader.situational(player_mlb_id, target_date)

    park = ParkFactors.hit_factor(venue_id, season)

    k_rate_30d = r30["k_rate"]
    pitcher_k9 = pitcher["pitcher_k_per_9"]

    k_rate_x_pitcher_k9 =
      if is_number(k_rate_30d) and is_number(pitcher_k9), do: k_rate_30d * pitcher_k9, else: nil

    %{
      "player_mlb_id" => player_mlb_id,
      "avg_7d" => r7["avg"],
      "avg_14d" => r14["avg"],
      "avg_30d" => r30["avg"],
      "avg_season" => rs["avg"],
      "obp_7d" => r7["obp"],
      "obp_14d" => r14["obp"],
      "obp_30d" => r30["obp"],
      "obp_season" => rs["obp"],
      "slg_7d" => r7["slg"],
      "slg_14d" => r14["slg"],
      "slg_30d" => r30["slg"],
      "slg_season" => rs["slg"],
      "k_rate_7d" => r7["k_rate"],
      "k_rate_14d" => r14["k_rate"],
      "k_rate_30d" => k_rate_30d,
      "bb_rate_30d" => r30["bb_rate"],
      "games_7d" => r7["games"] || 0,
      "games_14d" => r14["games"] || 0,
      "games_30d" => r30["games"] || 0,
      "games_season" => rs["games"] || 0,
      "pitcher_baa" => pitcher["pitcher_baa"],
      "pitcher_k_per_9" => pitcher_k9,
      "pitcher_whip" => pitcher["pitcher_whip"],
      "pitcher_bb_per_9" => pitcher["pitcher_bb_per_9"],
      "pitcher_hand_L" => pitcher["pitcher_hand_L"] || 0,
      "pitcher_hand_R" => pitcher["pitcher_hand_R"] || 0,
      "pitcher_recent_era_5g" => recent["pitcher_recent_era_5g"],
      "pitcher_recent_k9_5g" => recent["pitcher_recent_k9_5g"],
      "pitcher_recent_whip_5g" => recent["pitcher_recent_whip_5g"],
      "bvp_avg" => bvp["bvp_avg"],
      "bvp_at_bats" => bvp["bvp_at_bats"],
      "avg_exit_velocity" => statcast["avg_exit_velocity"],
      "hard_hit_pct" => statcast["hard_hit_pct"],
      "park_hit_factor" => park,
      "temperature" => get_weather(weather, "temperature_2m"),
      "wind_speed" => get_weather(weather, "wind_speed_10m"),
      "precipitation" => get_weather(weather, "precipitation"),
      "surface_pressure" => get_weather(weather, "surface_pressure"),
      "is_home" => if(is_home, do: 1, else: 0),
      "batting_order" => batting_order,
      "month" => target_date.month,
      "days_since_last_game" => situational["days_since_last_game"],
      "games_last_7d" => situational["games_last_7d"] || 0,
      "k_rate_x_pitcher_k9" => k_rate_x_pitcher_k9
    }
  end

  @doc """
  Build training rows for `start_date..end_date`. Joins boxscores with games,
  weather, pitcher_stats, and statcast. Rolling stats are computed via SQL
  per-row to keep the BEAM out of the data-shuffling loop.
  """
  @spec build_training_rows(Date.t(), Date.t()) :: [map()]
  def build_training_rows(%Date{} = start_date, %Date{} = end_date) do
    sql = """
    SELECT b.player_mlb_id,
           b.h,
           b.ab,
           b.batting_order,
           b.is_home,
           g.game_id,
           g.game_datetime,
           g.venue_id,
           g.away_starter_mlb_id,
           g.home_starter_mlb_id,
           w.temperature_2m,
           w.wind_speed_10m,
           w.precipitation,
           w.surface_pressure,
           ps.batting_avg_against,
           ps.k_per_9,
           ps.whip,
           ps.bb_per_9,
           pp.throw_hand AS opp_pitcher_hand,
           sc.avg_exit_velocity,
           sc.hard_hit_pct
      FROM mlb.player_boxscores b
      JOIN mlb.games g ON b.game_id = g.game_id
      LEFT JOIN mlb.game_weather w ON b.game_id = w.game_id
      LEFT JOIN public.players pp ON (pp.external_ids->>'mlb_id')::int =
              CASE WHEN b.is_home = true THEN g.away_starter_mlb_id
                   ELSE g.home_starter_mlb_id END
      LEFT JOIN mlb.pitcher_stats ps ON ps.player_id = pp.id
              AND ps.season = EXTRACT(YEAR FROM g.game_datetime)::int
      LEFT JOIN mlb.player_statcast sc ON sc.player_mlb_id = b.player_mlb_id
              AND sc.season = EXTRACT(YEAR FROM g.game_datetime)::int
     WHERE g.game_datetime::date >= $1
       AND g.game_datetime::date <= $2
       AND b.ab > 0
     ORDER BY g.game_datetime
    """

    result = SportsFanatic.Repo.query!(sql, [start_date, end_date])
    Enum.map(result.rows, &row_to_training_record/1)
  end

  defp row_to_training_record(row) do
    [
      player_mlb_id,
      h,
      _ab,
      batting_order,
      is_home,
      game_id,
      game_datetime,
      venue_id,
      _away_starter,
      _home_starter,
      temperature,
      wind_speed,
      precipitation,
      surface_pressure,
      baa,
      k9,
      whip,
      bb9,
      hand,
      ev,
      hh
    ] = row

    game_date =
      case game_datetime do
        %DateTime{} = dt -> DateTime.to_date(dt)
        %NaiveDateTime{} = ndt -> NaiveDateTime.to_date(ndt)
        _ -> nil
      end

    %{
      "player_mlb_id" => player_mlb_id,
      "game_id" => game_id,
      "game_date" => game_date && Date.to_iso8601(game_date),
      "target_hit" => if((h || 0) > 0, do: 1, else: 0),
      "pitcher_baa" => baa,
      "pitcher_k_per_9" => k9,
      "pitcher_whip" => whip,
      "pitcher_bb_per_9" => bb9,
      "pitcher_hand_L" => if(hand == "L", do: 1, else: 0),
      "pitcher_hand_R" => if(hand == "R", do: 1, else: 0),
      "park_hit_factor" => ParkFactors.hit_factor_static(venue_id),
      "temperature" => temperature,
      "wind_speed" => wind_speed,
      "precipitation" => precipitation,
      "surface_pressure" => surface_pressure,
      "batting_order" => batting_order,
      "month" => if(game_date, do: game_date.month, else: nil),
      "is_home" =>
        case is_home do
          true -> 1
          false -> 0
          nil -> nil
        end,
      "avg_exit_velocity" => ev,
      "hard_hit_pct" => hh
    }
  end

  defp get_weather(nil, _), do: nil
  defp get_weather(m, key) when is_map(m), do: Map.get(m, key)
end
