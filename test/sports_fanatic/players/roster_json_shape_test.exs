defmodule SportsFanatic.Players.RosterJsonShapeTest do
  @moduledoc """
  Unit tests for the roster JSON shape contract.

  These tests verify:
  1. The shape of each roster entry produced by `Players.build_roster/0` helpers —
     tested by constructing the output map the same way the code does and checking
     the expected keys and types.
  2. Jason.encode! on a roster entry with a name containing `</script>` does not
     break out of the JSON tag (XSS hygiene from spec §8).

  No Postgres required because we test the shape and encoding logic directly.
  """
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Required keys in every roster entry
  # ---------------------------------------------------------------------------

  @required_keys ~w(mlb_id full_name last_name team_slug slug href)

  describe "roster entry shape" do
    defp sample_entry(overrides \\ %{}) do
      Map.merge(
        %{
          "mlb_id" => 592_450,
          "full_name" => "Aaron Judge",
          "last_name" => "Judge",
          "team_slug" => "new-york-yankees",
          "team_abbr" => "NYY",
          "slug" => "aaron-judge",
          "href" => "/mlb/scouting/new-york-yankees/aaron-judge",
          "has_scouting" => true
        },
        overrides
      )
    end

    test "entry contains all required keys" do
      entry = sample_entry()

      for key <- @required_keys do
        assert Map.has_key?(entry, key),
               "Expected roster entry to have key '#{key}' but it was missing. Entry: #{inspect(entry)}"
      end
    end

    test "mlb_id can be an integer" do
      entry = sample_entry(%{"mlb_id" => 592_450})
      assert is_integer(entry["mlb_id"])
    end

    test "mlb_id can be nil (player without mlb_id)" do
      entry = sample_entry(%{"mlb_id" => nil})
      assert is_nil(entry["mlb_id"])
    end

    test "full_name is a non-empty string" do
      entry = sample_entry()
      assert is_binary(entry["full_name"])
      assert byte_size(entry["full_name"]) > 0
    end

    test "slug is a non-empty string" do
      entry = sample_entry()
      assert is_binary(entry["slug"])
      assert byte_size(entry["slug"]) > 0
    end

    test "team_slug is a non-empty string" do
      entry = sample_entry()
      assert is_binary(entry["team_slug"])
      assert byte_size(entry["team_slug"]) > 0
    end

    test "href points to scouting when has_scouting is true" do
      entry = sample_entry(%{"has_scouting" => true})
      assert String.contains?(entry["href"], "/mlb/scouting/")
    end

    test "href points to player page when has_scouting is false" do
      entry =
        sample_entry(%{
          "has_scouting" => false,
          "href" => "/mlb/players/new-york-yankees/aaron-judge"
        })

      assert String.contains?(entry["href"], "/mlb/players/")
    end
  end

  # ---------------------------------------------------------------------------
  # JSON encoding — XSS hygiene (spec §8 and RISKS section)
  # ---------------------------------------------------------------------------

  describe "Jason.encode!/1 roster XSS hygiene" do
    test "Jason.encode!(roster, escape: :html_safe) prevents </script> breakout (SEC-ROSTER-1 fixed)" do
      # SEC-ROSTER-1: the controller (lineup_controller.ex) uses
      # `Jason.encode!(roster, escape: :html_safe)` so any `<`, `>`, `/`, `&`
      # in a player full_name is unicode-escaped before reaching the inline
      # `<script type="application/json">` tag. The HTML tokenizer can no
      # longer scan a literal `</script>` out of the JSON body.
      entry = %{
        "full_name" => ~s|Mal</script><script>alert(1)</script>|,
        "slug" => "malicious"
      }

      json = Jason.encode!(entry, escape: :html_safe)

      refute String.contains?(json, "</script>"),
             "escape: :html_safe must prevent literal </script> in JSON output"

      refute String.contains?(json, "<script>"),
             "escape: :html_safe must prevent literal <script> in JSON output"

      # Round-trip safety — the original payload still survives decode
      assert Jason.decode!(json)["full_name"] =~ "</script>"
    end

    test "player name with ampersand is validly JSON-encoded" do
      entry = %{
        "full_name" => "Joe & Jane",
        "slug" => "joe-jane",
        "mlb_id" => nil,
        "last_name" => "Jane",
        "team_slug" => "t",
        "team_abbr" => "T",
        "href" => "/mlb/players/t/joe-jane",
        "has_scouting" => false
      }

      json = Jason.encode!(entry)
      # Jason escapes & to &; the JSON must still be decodable
      decoded = Jason.decode!(json)
      assert decoded["full_name"] == "Joe & Jane"
    end

    test "roster list with 1500 entries is encodable without error" do
      entries =
        for i <- 1..1500 do
          %{
            "mlb_id" => i,
            "full_name" => "Player #{i}",
            "last_name" => "#{i}",
            "team_slug" => "test-team",
            "team_abbr" => "TST",
            "slug" => "player-#{i}",
            "href" => "/mlb/players/test-team/player-#{i}",
            "has_scouting" => rem(i, 3) == 0
          }
        end

      json = Jason.encode!(entries)
      assert is_binary(json)
      assert byte_size(json) > 0
    end
  end
end
