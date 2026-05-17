defmodule SportsFanatic.Content.TeamMagazineTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Content.TeamMagazine

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        team_id: "bbbbbbbb-0000-0000-0000-000000000001",
        run_date: ~D[2026-06-15],
        state_of_the_team: "The Yankees are in a hot streak, winning 7 of their last 10."
      },
      overrides
    )
  end

  defp changeset(attrs), do: TeamMagazine.changeset(%TeamMagazine{}, attrs)

  # ---------------------------------------------------------------------------
  # Required fields
  # ---------------------------------------------------------------------------

  describe "required fields" do
    test "valid attrs produce a valid changeset" do
      assert changeset(valid_attrs()).valid?
    end

    test "missing team_id is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:team_id))
      refute cs.valid?
      assert {:team_id, _} = List.keyfind(cs.errors, :team_id, 0)
    end

    test "missing run_date is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:run_date))
      refute cs.valid?
      assert {:run_date, _} = List.keyfind(cs.errors, :run_date, 0)
    end

    test "missing state_of_the_team is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:state_of_the_team))
      refute cs.valid?
      assert {:state_of_the_team, _} = List.keyfind(cs.errors, :state_of_the_team, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Optional fields and defaults
  # ---------------------------------------------------------------------------

  describe "optional fields and defaults" do
    test "today_at_a_glance defaults to empty list" do
      cs = changeset(valid_attrs())
      assert Ecto.Changeset.get_field(cs, :today_at_a_glance) == []
    end

    test "sources defaults to empty list" do
      cs = changeset(valid_attrs())
      assert Ecto.Changeset.get_field(cs, :sources) == []
    end

    test "ai_processed defaults to true" do
      cs = changeset(valid_attrs())
      assert Ecto.Changeset.get_field(cs, :ai_processed) == true
    end

    test "cost_mills defaults to 0" do
      cs = changeset(valid_attrs())
      assert Ecto.Changeset.get_field(cs, :cost_mills) == 0
    end

    test "accepts today_at_a_glance as list of strings" do
      attrs =
        valid_attrs(%{
          today_at_a_glance: [
            "Judge is 3-for-3 with 2 HRs this week",
            "Rotation looks solid with Cole starting"
          ]
        })

      cs = changeset(attrs)
      assert cs.valid?
      glance = Ecto.Changeset.get_field(cs, :today_at_a_glance)
      assert is_list(glance)
      assert length(glance) == 2
    end

    test "accepts game_summary_prose as string" do
      attrs =
        valid_attrs(%{game_summary_prose: "The Yankees take on the Red Sox tonight at 7pm."})

      cs = changeset(attrs)
      assert cs.valid?
    end

    test "accepts sources as list of maps" do
      attrs =
        valid_attrs(%{
          sources: [
            %{"title" => "ESPN Gamecenter", "url" => "https://espn.com/mlb/game"},
            %{"title" => "MLB.com", "url" => "https://mlb.com/standings"}
          ]
        })

      cs = changeset(attrs)
      assert cs.valid?
    end

    test "accepts model field" do
      cs = changeset(valid_attrs(%{model: "claude-haiku-4-20251001"}))
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :model) == "claude-haiku-4-20251001"
    end

    test "accepts cost_mills as positive integer" do
      cs = changeset(valid_attrs(%{cost_mills: 42}))
      assert cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Unique constraint on (team_id, run_date)
  # ---------------------------------------------------------------------------

  describe "unique constraint" do
    test "changeset declares unique constraint on team_id + run_date" do
      cs = changeset(valid_attrs())

      assert Enum.any?(cs.constraints, fn c -> c.type == :unique end),
             "Expected a unique constraint to be declared in the changeset"
    end
  end

  # ---------------------------------------------------------------------------
  # Boundary: nil required field handling
  # ---------------------------------------------------------------------------

  describe "nil required fields" do
    test "nil team_id is invalid" do
      cs = changeset(valid_attrs(%{team_id: nil}))
      refute cs.valid?
      assert {:team_id, _} = List.keyfind(cs.errors, :team_id, 0)
    end

    test "nil run_date is invalid" do
      cs = changeset(valid_attrs(%{run_date: nil}))
      refute cs.valid?
      assert {:run_date, _} = List.keyfind(cs.errors, :run_date, 0)
    end

    test "nil state_of_the_team is invalid" do
      cs = changeset(valid_attrs(%{state_of_the_team: nil}))
      refute cs.valid?
      assert {:state_of_the_team, _} = List.keyfind(cs.errors, :state_of_the_team, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Full attrs round-trip
  # ---------------------------------------------------------------------------

  describe "full attrs changeset" do
    test "all fields accepted" do
      attrs =
        valid_attrs(%{
          today_at_a_glance: ["Bullpen is rested", "Lineup has 3 sluggers"],
          game_summary_prose: "Tonight the Yankees face Cole-era Boston.",
          sources: [%{"url" => "https://mlb.com"}],
          model: "claude-haiku-4",
          cost_mills: 200,
          ai_processed: true
        })

      cs = changeset(attrs)
      assert cs.valid?
    end
  end
end
