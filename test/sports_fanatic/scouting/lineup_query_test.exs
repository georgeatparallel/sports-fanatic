defmodule SportsFanatic.Scouting.LineupQueryTest do
  use ExUnit.Case, async: true

  @moduletag :unit

  alias SportsFanatic.Scouting

  setup_all do
    Code.ensure_loaded!(Scouting)
    :ok
  end

  describe "Scouting lineup query functions" do
    test "exports players_in_todays_lineups/0" do
      assert function_exported?(Scouting, :players_in_todays_lineups, 0)
    end

    test "exports players_in_lineups_for_date/1" do
      assert function_exported?(Scouting, :players_in_lineups_for_date, 1)
    end

    test "exports todays_lineup_player_count/0" do
      assert function_exported?(Scouting, :todays_lineup_player_count, 0)
    end

    test "exports lineup_player_count_for_date/1" do
      assert function_exported?(Scouting, :lineup_player_count_for_date, 1)
    end
  end
end
