defmodule SportsFanatic.Predictions.ParkFactorsTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Predictions.ParkFactors

  # ---------------------------------------------------------------------------
  # hit_factor_static/1 — pure in-memory lookup, no DB
  # ---------------------------------------------------------------------------

  describe "hit_factor_static/1" do
    test "nil venue returns 1.0 fallback" do
      assert ParkFactors.hit_factor_static(nil) == 1.0
    end

    test "unknown venue returns 1.0 fallback" do
      assert ParkFactors.hit_factor_static(99_999) == 1.0
    end

    test "Coors Field (venue_id 19) returns 1.10 — highest in the table" do
      assert ParkFactors.hit_factor_static(19) == 1.10
    end

    test "Great American Ball Park (venue_id 2602) returns 1.06" do
      assert ParkFactors.hit_factor_static(2602) == 1.06
    end

    test "Fenway Park (venue_id 3) returns 1.05" do
      assert ParkFactors.hit_factor_static(3) == 1.05
    end

    test "Citizens Bank Park (venue_id 2681) returns 1.02" do
      assert ParkFactors.hit_factor_static(2681) == 1.02
    end

    test "Yankee Stadium (venue_id 3313) returns 1.02" do
      assert ParkFactors.hit_factor_static(3313) == 1.02
    end

    test "Angel Stadium (venue_id 1) returns 0.98" do
      assert ParkFactors.hit_factor_static(1) == 0.98
    end

    test "Oracle Park (venue_id 2395) returns 0.94" do
      assert ParkFactors.hit_factor_static(2395) == 0.94
    end

    test "Kauffman Stadium (venue_id 7) returns 0.96" do
      assert ParkFactors.hit_factor_static(7) == 0.96
    end
  end

  # ---------------------------------------------------------------------------
  # defaults/0 — exposes the map for inspection
  # ---------------------------------------------------------------------------

  describe "defaults/0" do
    test "returns a non-empty map" do
      d = ParkFactors.defaults()
      assert is_map(d)
      assert map_size(d) > 0
    end

    test "all factors are positive floats" do
      ParkFactors.defaults()
      |> Map.values()
      |> Enum.each(fn v ->
        assert is_float(v) and v > 0.0
      end)
    end

    test "all keys are positive integers (venue_ids)" do
      ParkFactors.defaults()
      |> Map.keys()
      |> Enum.each(fn k ->
        assert is_integer(k) and k > 0
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # hit_factor/2 — nil guards (DB path skipped; no DB in unit tests)
  # ---------------------------------------------------------------------------

  describe "hit_factor/2 nil guards" do
    test "nil venue_id returns 1.0 regardless of season" do
      assert ParkFactors.hit_factor(nil, 2026) == 1.0
    end

    test "nil season falls through to static venue lookup" do
      assert ParkFactors.hit_factor(19, nil) == 1.10
    end

    test "nil season with unknown venue returns default 1.0" do
      assert ParkFactors.hit_factor(99_999, nil) == 1.0
    end
  end
end
