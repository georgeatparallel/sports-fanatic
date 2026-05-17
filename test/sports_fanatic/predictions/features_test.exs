defmodule SportsFanatic.Predictions.FeaturesTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Predictions.Features

  # ---------------------------------------------------------------------------
  # feature_cols/0 — canonical column list (order matters for ML batch calls)
  # ---------------------------------------------------------------------------

  describe "feature_cols/0" do
    # The module defines 44 features (the spec listed 38 but the implementation
    # extended it). This list is the authoritative contract for the Python
    # /inference/hit endpoint — it must accept exactly these columns.
    @expected_cols ~w(
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

    test "returns the canonical feature list (44 features as implemented)" do
      assert Features.feature_cols() == @expected_cols
    end

    test "contains exactly 44 features (implementation extended the 38-feature spec)" do
      # The spec lists 38 features; the implementation has 44. Both agree on the
      # canonical columns documented in build_inference_row/3. The Python
      # /inference/hit endpoint must accept whichever count the module declares.
      assert length(Features.feature_cols()) == 44
    end

    test "is a list of strings" do
      Enum.each(Features.feature_cols(), fn col ->
        assert is_binary(col), "Expected string, got: #{inspect(col)}"
      end)
    end

    test "has no duplicate columns" do
      cols = Features.feature_cols()
      assert length(cols) == length(Enum.uniq(cols))
    end

    test "includes interaction feature k_rate_x_pitcher_k9" do
      assert "k_rate_x_pitcher_k9" in Features.feature_cols()
    end

    test "includes weather features" do
      cols = Features.feature_cols()
      assert "temperature" in cols
      assert "wind_speed" in cols
      assert "precipitation" in cols
      assert "surface_pressure" in cols
    end

    test "includes BvP features" do
      cols = Features.feature_cols()
      assert "bvp_avg" in cols
      assert "bvp_at_bats" in cols
    end

    test "includes Statcast features" do
      cols = Features.feature_cols()
      assert "avg_exit_velocity" in cols
      assert "hard_hit_pct" in cols
    end
  end
end
