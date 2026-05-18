defmodule SportsFanatic.Players.InjuryBadgeTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Players.InjuryBadge

  # ---------------------------------------------------------------------------
  # Scouting risk values → badge atom
  # ---------------------------------------------------------------------------

  describe "for_scouting_or_injury/2 — scouting values win (step 1 precedence)" do
    test "scouting 'healthy' returns :green" do
      assert InjuryBadge.for_scouting_or_injury("healthy", nil) == :green
    end

    test "scouting 'low' returns :green" do
      assert InjuryBadge.for_scouting_or_injury("low", nil) == :green
    end

    test "scouting 'day-to-day' returns :yellow" do
      assert InjuryBadge.for_scouting_or_injury("day-to-day", nil) == :yellow
    end

    test "scouting 'day_to_day' (underscore form) returns :yellow" do
      assert InjuryBadge.for_scouting_or_injury("day_to_day", nil) == :yellow
    end

    test "scouting 'questionable' returns :yellow" do
      assert InjuryBadge.for_scouting_or_injury("questionable", nil) == :yellow
    end

    test "scouting 'moderate' returns :yellow" do
      assert InjuryBadge.for_scouting_or_injury("moderate", nil) == :yellow
    end

    test "scouting 'injured' returns :red" do
      assert InjuryBadge.for_scouting_or_injury("injured", nil) == :red
    end

    test "scouting 'il' returns :red" do
      assert InjuryBadge.for_scouting_or_injury("il", nil) == :red
    end

    test "scouting 'out' returns :red" do
      assert InjuryBadge.for_scouting_or_injury("out", nil) == :red
    end

    test "scouting 'high' returns :red" do
      assert InjuryBadge.for_scouting_or_injury("high", nil) == :red
    end

    test "scouting 'severe' returns :red" do
      assert InjuryBadge.for_scouting_or_injury("severe", nil) == :red
    end

    test "scouting values are case-insensitive: 'HEALTHY' returns :green" do
      assert InjuryBadge.for_scouting_or_injury("HEALTHY", nil) == :green
    end

    test "scouting values are case-insensitive: 'INJURED' returns :red" do
      assert InjuryBadge.for_scouting_or_injury("INJURED", nil) == :red
    end

    test "scouting values are case-insensitive: 'Day-To-Day' returns :yellow" do
      assert InjuryBadge.for_scouting_or_injury("Day-To-Day", nil) == :yellow
    end
  end

  # ---------------------------------------------------------------------------
  # Scouting unknown/nil falls through to injury report (step 2 precedence)
  # ---------------------------------------------------------------------------

  describe "for_scouting_or_injury/2 — scouting 'unknown'/nil falls through to injury" do
    test "scouting nil + injury 'active' returns :green" do
      assert InjuryBadge.for_scouting_or_injury(nil, "active") == :green
    end

    test "scouting nil + injury 'cleared' returns :green" do
      assert InjuryBadge.for_scouting_or_injury(nil, "cleared") == :green
    end

    test "scouting nil + injury 'day-to-day' returns :yellow" do
      assert InjuryBadge.for_scouting_or_injury(nil, "day-to-day") == :yellow
    end

    test "scouting nil + injury 'recovering' returns :yellow" do
      assert InjuryBadge.for_scouting_or_injury(nil, "recovering") == :yellow
    end

    test "scouting nil + injury 'injured-list-10' returns :red" do
      assert InjuryBadge.for_scouting_or_injury(nil, "injured-list-10") == :red
    end

    test "scouting nil + injury 'injured-list-15' returns :red" do
      assert InjuryBadge.for_scouting_or_injury(nil, "injured-list-15") == :red
    end

    test "scouting nil + injury 'injured-list-60' returns :red" do
      assert InjuryBadge.for_scouting_or_injury(nil, "injured-list-60") == :red
    end

    test "scouting 'unknown' string + injury 'active' returns :green" do
      assert InjuryBadge.for_scouting_or_injury("unknown", "active") == :green
    end

    test "scouting empty string + injury 'cleared' returns :green" do
      assert InjuryBadge.for_scouting_or_injury("", "cleared") == :green
    end

    test "scouting nil + injury 'unknown' returns :grey" do
      assert InjuryBadge.for_scouting_or_injury(nil, "unknown") == :grey
    end
  end

  # ---------------------------------------------------------------------------
  # Precedence: scouting wins over injury when scouting is non-nil/non-unknown
  # ---------------------------------------------------------------------------

  describe "for_scouting_or_injury/2 — scouting overrides injury when both are set" do
    test "scouting 'healthy' wins over injury 'injured-list-10'" do
      assert InjuryBadge.for_scouting_or_injury("healthy", "injured-list-10") == :green
    end

    test "scouting 'injured' wins over injury 'active'" do
      assert InjuryBadge.for_scouting_or_injury("injured", "active") == :red
    end

    test "scouting 'day-to-day' wins over injury 'cleared'" do
      assert InjuryBadge.for_scouting_or_injury("day-to-day", "cleared") == :yellow
    end

    test "scouting 'moderate' wins over injury 'injured-list-60'" do
      assert InjuryBadge.for_scouting_or_injury("moderate", "injured-list-60") == :yellow
    end
  end

  # ---------------------------------------------------------------------------
  # Both nil/unknown → :grey
  # ---------------------------------------------------------------------------

  describe "for_scouting_or_injury/2 — nil on both returns :grey" do
    test "nil scouting + nil injury returns :grey" do
      assert InjuryBadge.for_scouting_or_injury(nil, nil) == :grey
    end

    test "'unknown' scouting + nil injury returns :grey" do
      assert InjuryBadge.for_scouting_or_injury("unknown", nil) == :grey
    end

    test "nil scouting + 'unknown' injury returns :grey" do
      assert InjuryBadge.for_scouting_or_injury(nil, "unknown") == :grey
    end

    test "both empty strings return :grey" do
      assert InjuryBadge.for_scouting_or_injury("", "") == :grey
    end
  end

  # ---------------------------------------------------------------------------
  # Return type contract — always returns a badge atom
  # ---------------------------------------------------------------------------

  describe "for_scouting_or_injury/2 — return type" do
    test "always returns one of the four badge atoms" do
      valid = [:green, :yellow, :red, :grey]

      for scouting <- ["healthy", "low", "day-to-day", "injured", "unknown", nil, ""],
          injury <- [
            "active",
            "cleared",
            "day-to-day",
            "recovering",
            "injured-list-10",
            "unknown",
            nil
          ] do
        result = InjuryBadge.for_scouting_or_injury(scouting, injury)

        assert result in valid,
               "Expected one of #{inspect(valid)} but got #{inspect(result)} " <>
                 "for scouting=#{inspect(scouting)}, injury=#{inspect(injury)}"
      end
    end
  end
end
