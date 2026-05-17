defmodule SportsFanatic.Content.InjuryReportTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Content.InjuryReport

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        player_id: "aaaaaaaa-0000-0000-0000-000000000001",
        run_date: ~D[2026-06-15],
        tldr: "Aaron Judge is day-to-day with a hamstring strain.",
        current_status: "day-to-day"
      },
      overrides
    )
  end

  defp changeset(attrs), do: InjuryReport.changeset(%InjuryReport{}, attrs)

  # ---------------------------------------------------------------------------
  # Required fields
  # ---------------------------------------------------------------------------

  describe "required fields" do
    test "valid attrs produce a valid changeset" do
      assert changeset(valid_attrs()).valid?
    end

    test "missing player_id is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:player_id))
      refute cs.valid?
      assert {:player_id, _} = List.keyfind(cs.errors, :player_id, 0)
    end

    test "missing run_date is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:run_date))
      refute cs.valid?
      assert {:run_date, _} = List.keyfind(cs.errors, :run_date, 0)
    end

    test "missing tldr is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:tldr))
      refute cs.valid?
      assert {:tldr, _} = List.keyfind(cs.errors, :tldr, 0)
    end

    test "missing current_status is invalid" do
      cs = changeset(valid_attrs() |> Map.delete(:current_status))
      refute cs.valid?
      assert {:current_status, _} = List.keyfind(cs.errors, :current_status, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # current_status enum
  # ---------------------------------------------------------------------------

  describe "current_status enum validation" do
    for status <-
          ~w(active day-to-day injured-list-10 injured-list-15 injured-list-60 recovering cleared unknown) do
      test "accepts valid status: #{status}" do
        cs = changeset(valid_attrs(%{current_status: unquote(status)}))
        assert cs.valid?, "Expected status '#{unquote(status)}' to be valid"
      end
    end

    test "rejects invalid status" do
      cs = changeset(valid_attrs(%{current_status: "questionable"}))
      refute cs.valid?
      assert {:current_status, _} = List.keyfind(cs.errors, :current_status, 0)
    end

    test "rejects empty string status" do
      cs = changeset(valid_attrs(%{current_status: ""}))
      refute cs.valid?
    end

    test "rejects nil status" do
      cs = changeset(valid_attrs(%{current_status: nil}))
      refute cs.valid?
    end

    test "rejects status with leading space" do
      cs = changeset(valid_attrs(%{current_status: " active"}))
      refute cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # valid_statuses/0 class function
  # ---------------------------------------------------------------------------

  describe "InjuryReport.valid_statuses/0" do
    test "returns a non-empty list of strings" do
      statuses = InjuryReport.valid_statuses()
      assert is_list(statuses)
      assert length(statuses) > 0
      assert Enum.all?(statuses, &is_binary/1)
    end

    test "includes all 8 required status values" do
      statuses = MapSet.new(InjuryReport.valid_statuses())
      expected = MapSet.new(~w(
        active day-to-day injured-list-10 injured-list-15 injured-list-60
        recovering cleared unknown
      ))
      assert MapSet.subset?(expected, statuses)
    end
  end

  # ---------------------------------------------------------------------------
  # current_status max length
  # ---------------------------------------------------------------------------

  describe "current_status length constraint" do
    test "rejects current_status over 30 chars" do
      long_status = String.duplicate("x", 31)
      cs = changeset(valid_attrs(%{current_status: long_status}))
      refute cs.valid?
      assert {:current_status, _} = List.keyfind(cs.errors, :current_status, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Optional fields
  # ---------------------------------------------------------------------------

  describe "optional fields" do
    test "timeline defaults to empty list" do
      cs = changeset(valid_attrs())
      assert Ecto.Changeset.get_field(cs, :timeline) == []
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

    test "accepts all optional fields" do
      attrs =
        valid_attrs(%{
          timeline: [%{"date" => "2026-06-15", "event" => "IL placement"}],
          expected_return: "2-3 weeks",
          fantasy_impact: "Drop for 2 weeks",
          sources: [%{"title" => "ESPN", "url" => "https://espn.com"}],
          model: "claude-haiku-4",
          cost_mills: 150,
          ai_processed: true
        })

      cs = changeset(attrs)
      assert cs.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Unique constraint (changeset adds it)
  # ---------------------------------------------------------------------------

  describe "unique constraint" do
    test "changeset adds unique_constraint on [:player_id, :run_date]" do
      cs = changeset(valid_attrs())
      # Verify the constraint is declared by checking the changeset constraints list
      constraint_names = Enum.map(cs.constraints, & &1.field)
      # The unique constraint is on a composite key; the first field appears
      assert :player_id in constraint_names or :run_date in constraint_names or
               Enum.any?(cs.constraints, fn c -> c.type == :unique end)
    end
  end
end
