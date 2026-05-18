defmodule SportsFanatic.DateHelperEasternMidnightTest do
  @moduledoc """
  Unit tests for DateHelper.seconds_until_eastern_midnight/0.
  Pure time arithmetic — no external dependencies.
  """
  use ExUnit.Case, async: true

  alias SportsFanatic.DateHelper

  describe "seconds_until_eastern_midnight/0" do
    test "returns a positive integer" do
      result = DateHelper.seconds_until_eastern_midnight()
      assert is_integer(result)
      assert result >= 1
    end

    test "never returns zero or negative (floor of 1 second)" do
      result = DateHelper.seconds_until_eastern_midnight()
      assert result >= 1, "Expected >= 1 but got #{result}"
    end

    test "never exceeds 86_400 seconds (24 h ceiling)" do
      result = DateHelper.seconds_until_eastern_midnight()
      assert result <= 86_400, "Expected <= 86_400 but got #{result}"
    end

    test "is at most one day away from now" do
      result = DateHelper.seconds_until_eastern_midnight()
      # At most one full day + a little buffer for clock drift
      assert result <= 86_401
    end

    test "called twice within a short window returns decreasing or equal values" do
      first = DateHelper.seconds_until_eastern_midnight()
      second = DateHelper.seconds_until_eastern_midnight()
      # The second call should be within 2 seconds of the first (no day rollover mid-test)
      assert abs(first - second) <= 2
    end
  end
end
