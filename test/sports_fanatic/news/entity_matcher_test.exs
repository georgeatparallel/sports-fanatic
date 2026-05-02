defmodule SportsFanatic.News.EntityMatcherTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.News.EntityMatcher

  # ---------------------------------------------------------------------------
  # Helpers to build lightweight player/team structs without a database.
  # ---------------------------------------------------------------------------

  defp player(id, full_name) do
    %{
      __struct__: SportsFanatic.Mlb.Player,
      id: id,
      full_name: full_name
    }
  end

  defp team(id, name, city, abbreviation) do
    %{
      __struct__: SportsFanatic.Mlb.Team,
      id: id,
      name: name,
      city: city,
      abbreviation: abbreviation
    }
  end

  # ---------------------------------------------------------------------------
  # match_players/2
  # ---------------------------------------------------------------------------

  describe "match_players/2 with empty player name list" do
    test "returns empty list without inspecting all_players" do
      all_players = [player("1", "Aaron Judge")]
      assert EntityMatcher.match_players([], all_players) == []
    end

    test "returns empty list even when all_players is empty" do
      assert EntityMatcher.match_players([], []) == []
    end
  end

  describe "match_players/2 exact match" do
    test "returns matching player on exact case-insensitive name match" do
      p = player("uuid-1", "Aaron Judge")
      result = EntityMatcher.match_players(["Aaron Judge"], [p])
      assert result == [p]
    end

    test "matches regardless of input casing" do
      p = player("uuid-1", "Aaron Judge")
      result = EntityMatcher.match_players(["aaron judge"], [p])
      assert result == [p]
    end

    test "matches regardless of stored name casing" do
      p = player("uuid-1", "AARON JUDGE")
      result = EntityMatcher.match_players(["Aaron Judge"], [p])
      assert result == [p]
    end
  end

  describe "match_players/2 fuzzy match" do
    test "matches a shortened name above the 0.85 jaro threshold" do
      p = player("uuid-1", "Aaron Judge")
      # "A. Judge" has a Jaro distance > 0.85 with "Aaron Judge"? Let's use
      # "Aron Judge" (one char off) which definitely exceeds the threshold.
      result = EntityMatcher.match_players(["Aron Judge"], [p])
      assert result == [p]
    end

    test "does not match a completely different name" do
      p = player("uuid-1", "Aaron Judge")
      result = EntityMatcher.match_players(["Shohei Ohtani"], [p])
      assert result == []
    end

    test "does not match an empty string against a valid player" do
      p = player("uuid-1", "Aaron Judge")
      result = EntityMatcher.match_players([""], [p])
      assert result == []
    end
  end

  describe "match_players/2 deduplication" do
    test "deduplicates when the same player is matched by multiple name variants" do
      p = player("uuid-1", "Aaron Judge")
      result = EntityMatcher.match_players(["Aaron Judge", "aaron judge"], [p])
      assert length(result) == 1
      assert hd(result).id == "uuid-1"
    end
  end

  describe "match_players/2 multiple players" do
    test "returns all players that match from the input list" do
      p1 = player("uuid-1", "Aaron Judge")
      p2 = player("uuid-2", "Shohei Ohtani")
      all_players = [p1, p2]
      result = EntityMatcher.match_players(["Aaron Judge", "Shohei Ohtani"], all_players)
      assert length(result) == 2
      ids = Enum.map(result, & &1.id)
      assert "uuid-1" in ids
      assert "uuid-2" in ids
    end

    test "returns only matched players when one name has no match" do
      p1 = player("uuid-1", "Aaron Judge")
      all_players = [p1]
      result = EntityMatcher.match_players(["Aaron Judge", "Nobody Lastname"], all_players)
      assert result == [p1]
    end

    test "returns empty list when no names match any player" do
      p1 = player("uuid-1", "Aaron Judge")
      result = EntityMatcher.match_players(["Shohei Ohtani", "Mike Trout"], [p1])
      assert result == []
    end
  end

  describe "match_players/2 with empty all_players list" do
    test "returns empty list when no players exist" do
      result = EntityMatcher.match_players(["Aaron Judge"], [])
      assert result == []
    end
  end

  describe "match_players/2 with nil full_name in player" do
    test "does not crash when player full_name is nil" do
      p = player("uuid-1", nil)
      result = EntityMatcher.match_players(["Aaron Judge"], [p])
      assert result == []
    end
  end

  # ---------------------------------------------------------------------------
  # match_teams/2
  # ---------------------------------------------------------------------------

  describe "match_teams/2 with empty team name list" do
    test "returns empty list without inspecting all_teams" do
      all_teams = [team("t1", "Yankees", "New York", "NYY")]
      assert EntityMatcher.match_teams([], all_teams) == []
    end
  end

  describe "match_teams/2 abbreviation match" do
    test "matches team by exact abbreviation (case-insensitive)" do
      t = team("t1", "Yankees", "New York", "NYY")
      result = EntityMatcher.match_teams(["NYY"], [t])
      assert result == [t]
    end

    test "matches team by lowercase abbreviation input" do
      t = team("t1", "Yankees", "New York", "NYY")
      result = EntityMatcher.match_teams(["nyy"], [t])
      assert result == [t]
    end

    test "abbreviation match takes priority over fuzzy name match" do
      # Two teams with similar names; pick by abbreviation
      t1 = team("t1", "Yankees", "New York", "NYY")
      t2 = team("t2", "Yankers", "Old York", "OYY")
      result = EntityMatcher.match_teams(["NYY"], [t1, t2])
      assert result == [t1]
    end
  end

  describe "match_teams/2 exact name match" do
    test "matches team by exact name when abbreviation does not match" do
      t = team("t1", "Yankees", "New York", "NYY")
      result = EntityMatcher.match_teams(["Yankees"], [t])
      assert result == [t]
    end

    test "matches team name case-insensitively" do
      t = team("t1", "Yankees", "New York", "NYY")
      result = EntityMatcher.match_teams(["yankees"], [t])
      assert result == [t]
    end
  end

  describe "match_teams/2 fuzzy name match" do
    test "matches team by fuzzy city+name string above threshold" do
      t = team("t1", "Yankees", "New York", "NYY")
      # "New York Yankee" — one char short — should be close enough
      result = EntityMatcher.match_teams(["New York Yankee"], [t])
      assert result == [t]
    end

    test "does not match an unrelated team name" do
      t = team("t1", "Yankees", "New York", "NYY")
      result = EntityMatcher.match_teams(["Los Angeles Dodgers"], [t])
      assert result == []
    end
  end

  describe "match_teams/2 deduplication" do
    test "deduplicates when abbreviation and name both match the same team" do
      t = team("t1", "Yankees", "New York", "NYY")
      result = EntityMatcher.match_teams(["NYY", "Yankees"], [t])
      assert length(result) == 1
      assert hd(result).id == "t1"
    end
  end

  describe "match_teams/2 with nil fields in team" do
    test "does not crash when team abbreviation is nil" do
      t = team("t1", "Yankees", "New York", nil)
      result = EntityMatcher.match_teams(["NYY"], [t])
      # No abbreviation to match, falls through to name match
      assert result == []
    end

    test "does not crash when team name is nil" do
      t = team("t1", nil, "New York", "NYY")
      result = EntityMatcher.match_teams(["NYY"], [t])
      # Abbreviation still matches
      assert result == [t]
    end

    test "does not crash when team city is nil" do
      t = team("t1", "Yankees", nil, "NYY")
      result = EntityMatcher.match_teams(["NYY"], [t])
      assert result == [t]
    end
  end

  describe "match_teams/2 with empty all_teams list" do
    test "returns empty list when no teams exist" do
      result = EntityMatcher.match_teams(["NYY"], [])
      assert result == []
    end
  end
end
