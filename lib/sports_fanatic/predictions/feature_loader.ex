defmodule SportsFanatic.Predictions.FeatureLoader do
  @moduledoc """
  Database query helpers for hit-prediction feature engineering.

  Functions return maps shaped for downstream consumption by
  `SportsFanatic.Predictions.Features`. SQL aggregations are used wherever
  possible to avoid loading per-row data into the BEAM.
  """

  alias SportsFanatic.Repo

  @spec rolling_stats(integer, Date.t(), pos_integer) :: map()
  def rolling_stats(player_mlb_id, %Date{} = as_of_date, window_days) do
    start_date = Date.add(as_of_date, -window_days)

    sql = """
    SELECT
      COALESCE(SUM(b.ab), 0)::int      AS ab,
      COALESCE(SUM(b.h), 0)::int       AS h,
      COALESCE(SUM(b.hr), 0)::int      AS hr,
      COALESCE(SUM(b.doubles), 0)::int AS doubles,
      COALESCE(SUM(b.triples), 0)::int AS triples,
      COALESCE(SUM(b.bb), 0)::int      AS bb,
      COALESCE(SUM(b.k), 0)::int       AS k,
      COUNT(DISTINCT g.game_id)::int   AS games
    FROM mlb.player_boxscores b
    JOIN mlb.games g ON b.game_id = g.game_id
    WHERE b.player_mlb_id = $1
      AND g.game_datetime::date >= $2
      AND g.game_datetime::date <  $3
    """

    result = Repo.query!(sql, [player_mlb_id, start_date, as_of_date])
    [[ab, h, hr, d, t, bb, k, games] | _] = result.rows
    compose_split(ab, h, hr, d, t, bb, k, games)
  end

  @spec season_stats(integer, Date.t()) :: map()
  def season_stats(player_mlb_id, %Date{} = as_of_date) do
    season_start = Date.new!(as_of_date.year, 1, 1)
    rolling_stats(player_mlb_id, as_of_date, Date.diff(as_of_date, season_start))
  end

  @spec opposing_pitcher(integer | nil, integer) :: map()
  def opposing_pitcher(nil, _season),
    do: %{
      "pitcher_baa" => nil,
      "pitcher_k_per_9" => nil,
      "pitcher_whip" => nil,
      "pitcher_bb_per_9" => nil,
      "pitcher_hand_L" => 0,
      "pitcher_hand_R" => 0
    }

  def opposing_pitcher(pitcher_mlb_id, season) do
    sql = """
    SELECT ps.batting_avg_against, ps.k_per_9, ps.whip, ps.bb_per_9, p.throw_hand
      FROM mlb.pitcher_stats ps
      LEFT JOIN public.players p ON ps.player_id = p.id
     WHERE COALESCE(ps.pitcher_mlb_id, (p.external_ids->>'mlb_id')::int) = $1
       AND ps.season = $2
     LIMIT 1
    """

    case Repo.query!(sql, [pitcher_mlb_id, season]).rows do
      [[baa, k9, whip, bb9, hand] | _] ->
        %{
          "pitcher_baa" => baa,
          "pitcher_k_per_9" => k9,
          "pitcher_whip" => whip,
          "pitcher_bb_per_9" => bb9,
          "pitcher_hand_L" => if(hand == "L", do: 1, else: 0),
          "pitcher_hand_R" => if(hand == "R", do: 1, else: 0)
        }

      _ ->
        opposing_pitcher(nil, season)
    end
  end

  @spec pitcher_recent_form(integer | nil, Date.t(), pos_integer) :: map()
  def pitcher_recent_form(pitcher_mlb_id, as_of_date, num_games \\ 5)

  def pitcher_recent_form(nil, _date, _n),
    do: %{
      "pitcher_recent_era_5g" => nil,
      "pitcher_recent_k9_5g" => nil,
      "pitcher_recent_whip_5g" => nil
    }

  def pitcher_recent_form(pitcher_mlb_id, %Date{} = as_of_date, num_games) do
    sql = """
    SELECT innings_pitched, hits_allowed, bb_allowed, strikeouts, earned_runs
      FROM mlb.pitcher_game_logs
     WHERE pitcher_mlb_id = $1
       AND game_date < $2
     ORDER BY game_date DESC
     LIMIT $3
    """

    rows = Repo.query!(sql, [pitcher_mlb_id, as_of_date, num_games]).rows

    if rows == [] do
      pitcher_recent_form(nil, as_of_date, num_games)
    else
      total_ip = sum_col(rows, 0) || 0.0
      total_h = sum_col(rows, 1) || 0
      total_bb = sum_col(rows, 2) || 0
      total_k = sum_col(rows, 3) || 0
      total_er = sum_col(rows, 4) || 0

      era = if total_ip > 0, do: total_er * 9 / total_ip, else: nil
      k9 = if total_ip > 0, do: total_k * 9 / total_ip, else: nil
      whip = if total_ip > 0, do: (total_h + total_bb) / total_ip, else: nil

      %{
        "pitcher_recent_era_5g" => round_or_nil(era, 3),
        "pitcher_recent_k9_5g" => round_or_nil(k9, 2),
        "pitcher_recent_whip_5g" => round_or_nil(whip, 3)
      }
    end
  end

  @spec bvp_features(integer, integer | nil, integer) :: map()
  def bvp_features(_batter_mlb_id, nil, _season),
    do: %{"bvp_avg" => nil, "bvp_at_bats" => nil, "bvp_home_runs" => nil}

  def bvp_features(batter_mlb_id, pitcher_mlb_id, season) do
    sql = """
    SELECT bvp.batting_avg, bvp.at_bats, bvp.home_runs
      FROM mlb.batter_vs_pitcher bvp
      JOIN public.players bp ON bvp.batter_id = bp.id
      JOIN public.players pp ON bvp.pitcher_id = pp.id
     WHERE (bp.external_ids->>'mlb_id')::int = $1
       AND (pp.external_ids->>'mlb_id')::int = $2
       AND bvp.season = $3
     LIMIT 1
    """

    case Repo.query!(sql, [batter_mlb_id, pitcher_mlb_id, season]).rows do
      [[avg, ab, hr] | _] -> %{"bvp_avg" => avg, "bvp_at_bats" => ab, "bvp_home_runs" => hr}
      _ -> %{"bvp_avg" => nil, "bvp_at_bats" => nil, "bvp_home_runs" => nil}
    end
  end

  @spec statcast(integer, integer) :: map()
  def statcast(player_mlb_id, season) do
    sql = """
    SELECT avg_exit_velocity, hard_hit_pct
      FROM mlb.player_statcast
     WHERE player_mlb_id = $1 AND season = $2
     LIMIT 1
    """

    case Repo.query!(sql, [player_mlb_id, season]).rows do
      [[ev, hh] | _] -> %{"avg_exit_velocity" => ev, "hard_hit_pct" => hh}
      _ -> %{"avg_exit_velocity" => nil, "hard_hit_pct" => nil}
    end
  end

  @spec situational(integer, Date.t()) :: map()
  def situational(player_mlb_id, %Date{} = target_date) do
    last_sql = """
    SELECT MAX(g.game_datetime::date)
      FROM mlb.player_boxscores b
      JOIN mlb.games g ON b.game_id = g.game_id
     WHERE b.player_mlb_id = $1 AND g.game_datetime::date < $2
    """

    week_ago = Date.add(target_date, -7)

    games_7d_sql = """
    SELECT COUNT(DISTINCT g.game_id)
      FROM mlb.player_boxscores b
      JOIN mlb.games g ON b.game_id = g.game_id
     WHERE b.player_mlb_id = $1
       AND g.game_datetime::date >= $2
       AND g.game_datetime::date <  $3
    """

    [[last_date] | _] = Repo.query!(last_sql, [player_mlb_id, target_date]).rows
    [[games_7d] | _] = Repo.query!(games_7d_sql, [player_mlb_id, week_ago, target_date]).rows

    days_since = if last_date, do: Date.diff(target_date, last_date), else: nil

    %{
      "days_since_last_game" => days_since,
      "games_last_7d" => games_7d || 0
    }
  end

  ## --- Helpers --------------------------------------------------------------

  defp compose_split(ab, h, hr, doubles, triples, bb, k, games) do
    pa = ab + bb
    singles = h - doubles - triples - hr
    tb = singles + 2 * doubles + 3 * triples + 4 * hr

    %{
      "games" => games,
      "ab" => ab,
      "h" => h,
      "bb" => bb,
      "k" => k,
      "avg" => if(ab > 0, do: Float.round(h / ab, 4), else: nil),
      "obp" => if(pa > 0, do: Float.round((h + bb) / pa, 4), else: nil),
      "slg" => if(ab > 0, do: Float.round(tb / ab, 4), else: nil),
      "k_rate" => if(pa > 0, do: Float.round(k / pa, 4), else: nil),
      "bb_rate" => if(pa > 0, do: Float.round(bb / pa, 4), else: nil)
    }
  end

  defp sum_col(rows, col_idx) do
    rows
    |> Enum.map(fn r -> Enum.at(r, col_idx) end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      vals -> Enum.sum(vals)
    end
  end

  defp round_or_nil(nil, _), do: nil
  defp round_or_nil(n, p) when is_float(n), do: Float.round(n, p)
  defp round_or_nil(n, p) when is_integer(n), do: Float.round(n * 1.0, p)
end
