defmodule SportsFanatic.Predictions.HitPredictionTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Predictions.HitPrediction

  # ---------------------------------------------------------------------------
  # changeset/2 — required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 required fields" do
    @valid_attrs %{
      prediction_date: ~D[2026-05-17],
      player_mlb_id: 592_450,
      hit_prob: 0.65,
      prediction: "Hit"
    }

    test "valid with all required fields" do
      cs = HitPrediction.changeset(%HitPrediction{}, @valid_attrs)
      assert cs.valid?
    end

    test "invalid without prediction_date" do
      cs = HitPrediction.changeset(%HitPrediction{}, Map.delete(@valid_attrs, :prediction_date))
      refute cs.valid?
      assert cs.errors[:prediction_date] != nil
    end

    test "invalid without player_mlb_id" do
      cs = HitPrediction.changeset(%HitPrediction{}, Map.delete(@valid_attrs, :player_mlb_id))
      refute cs.valid?
      assert cs.errors[:player_mlb_id] != nil
    end

    test "invalid without hit_prob" do
      cs = HitPrediction.changeset(%HitPrediction{}, Map.delete(@valid_attrs, :hit_prob))
      refute cs.valid?
      assert cs.errors[:hit_prob] != nil
    end

    test "invalid without prediction" do
      cs = HitPrediction.changeset(%HitPrediction{}, Map.delete(@valid_attrs, :prediction))
      refute cs.valid?
      assert cs.errors[:prediction] != nil
    end
  end

  # ---------------------------------------------------------------------------
  # hit_prob bounds validation (0.0 .. 1.0)
  # ---------------------------------------------------------------------------

  describe "changeset/2 hit_prob bounds" do
    defp base(extra) do
      Map.merge(
        %{
          prediction_date: ~D[2026-05-17],
          player_mlb_id: 592_450,
          prediction: "Hit"
        },
        extra
      )
    end

    test "0.0 is valid lower bound" do
      cs = HitPrediction.changeset(%HitPrediction{}, base(%{hit_prob: 0.0}))
      assert cs.valid?
    end

    test "1.0 is valid upper bound" do
      cs = HitPrediction.changeset(%HitPrediction{}, base(%{hit_prob: 1.0}))
      assert cs.valid?
    end

    test "0.5 is valid midpoint" do
      cs = HitPrediction.changeset(%HitPrediction{}, base(%{hit_prob: 0.5}))
      assert cs.valid?
    end

    test "negative probability is invalid" do
      cs = HitPrediction.changeset(%HitPrediction{}, base(%{hit_prob: -0.01}))
      refute cs.valid?
      assert cs.errors[:hit_prob] != nil
    end

    test "probability greater than 1.0 is invalid" do
      cs = HitPrediction.changeset(%HitPrediction{}, base(%{hit_prob: 1.01}))
      refute cs.valid?
      assert cs.errors[:hit_prob] != nil
    end
  end

  # ---------------------------------------------------------------------------
  # prediction enum validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 prediction enum" do
    defp base_with(prediction) do
      %{
        prediction_date: ~D[2026-05-17],
        player_mlb_id: 592_450,
        hit_prob: 0.55,
        prediction: prediction
      }
    end

    test "Hit is valid" do
      cs = HitPrediction.changeset(%HitPrediction{}, base_with("Hit"))
      assert cs.valid?
    end

    test "No Hit is valid" do
      cs = HitPrediction.changeset(%HitPrediction{}, base_with("No Hit"))
      assert cs.valid?
    end

    test "arbitrary string is invalid" do
      cs = HitPrediction.changeset(%HitPrediction{}, base_with("Maybe"))
      refute cs.valid?
      assert cs.errors[:prediction] != nil
    end

    test "empty string is invalid" do
      cs = HitPrediction.changeset(%HitPrediction{}, base_with(""))
      refute cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # confidence_tier validation (optional, but must be S/A/B/C/D if present)
  # ---------------------------------------------------------------------------

  describe "changeset/2 confidence_tier" do
    defp base_tier(tier) do
      %{
        prediction_date: ~D[2026-05-17],
        player_mlb_id: 592_450,
        hit_prob: 0.7,
        prediction: "Hit",
        confidence_tier: tier
      }
    end

    for tier <- ~w(S A B C D) do
      test "confidence_tier #{tier} is valid" do
        cs = HitPrediction.changeset(%HitPrediction{}, base_tier(unquote(tier)))
        assert cs.valid?
      end
    end

    test "invalid confidence_tier is rejected" do
      cs = HitPrediction.changeset(%HitPrediction{}, base_tier("F"))
      refute cs.valid?
      assert cs.errors[:confidence_tier] != nil
    end

    test "missing confidence_tier is allowed" do
      attrs = %{
        prediction_date: ~D[2026-05-17],
        player_mlb_id: 592_450,
        hit_prob: 0.7,
        prediction: "Hit"
      }

      cs = HitPrediction.changeset(%HitPrediction{}, attrs)
      assert cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # tier_for_prob/1 — derived confidence tier from probability
  # ---------------------------------------------------------------------------

  describe "tier_for_prob/1" do
    test "probability >= 0.85 gives S tier" do
      assert HitPrediction.tier_for_prob(0.85) == "S"
    end

    test "probability <= 0.15 gives S tier (distance from 0.5 is 0.35)" do
      assert HitPrediction.tier_for_prob(0.15) == "S"
    end

    test "probability of 0.75 gives A tier" do
      assert HitPrediction.tier_for_prob(0.75) == "A"
    end

    test "probability of 0.65 gives B tier" do
      assert HitPrediction.tier_for_prob(0.65) == "B"
    end

    test "probability of 0.55 gives C tier" do
      assert HitPrediction.tier_for_prob(0.55) == "C"
    end

    test "probability of exactly 0.5 gives D tier (zero distance)" do
      assert HitPrediction.tier_for_prob(0.5) == "D"
    end

    test "nil returns nil" do
      assert HitPrediction.tier_for_prob(nil) == nil
    end

    test "non-float atom returns nil" do
      assert HitPrediction.tier_for_prob(:bad) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Optional narrative fields are cast without error
  # ---------------------------------------------------------------------------

  describe "changeset/2 optional narrative fields" do
    test "accepts full narrative metadata" do
      attrs = %{
        prediction_date: ~D[2026-05-17],
        player_mlb_id: 592_450,
        hit_prob: 0.72,
        prediction: "Hit",
        player_name: "Aaron Judge",
        player_team: "New York Yankees",
        vs_team: "Boston Red Sox",
        game_datetime: ~U[2026-05-17 23:10:00Z],
        is_home: false,
        batting_order: 3,
        probable_pitcher_name: "Garrett Whitlock",
        probable_pitcher_mlb_id: 680_776,
        venue_id: 3313,
        venue_name: "Fenway Park",
        temperature: 68.0,
        wind_speed: 8.0,
        wind_direction: 270,
        precipitation: 0.0,
        weathercode: 3,
        surface_pressure: 1013.0,
        bvp_avg: 0.333,
        bvp_at_bats: 9,
        bvp_home_runs: 2,
        features: %{"avg_7d" => 0.280},
        model_version: "gbt-2026-05-17",
        confidence_tier: "A"
      }

      cs = HitPrediction.changeset(%HitPrediction{}, attrs)
      assert cs.valid?
    end
  end
end
