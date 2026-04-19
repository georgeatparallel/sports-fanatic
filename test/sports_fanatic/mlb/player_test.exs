defmodule SportsFanatic.Mlb.PlayerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Mlb.Player

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "changeset/2" do
    test "valid changeset with required full_name" do
      changeset = Player.changeset(%Player{}, %{full_name: "Aaron Judge"})
      assert changeset.valid?
    end

    test "invalid without full_name" do
      changeset = Player.changeset(%Player{}, %{first_name: "Aaron"})
      refute changeset.valid?
      assert %{full_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "auto-generates slug from full_name when slug is nil" do
      changeset = Player.changeset(%Player{}, %{full_name: "Aaron Judge"})
      assert Ecto.Changeset.get_change(changeset, :slug) == "aaron-judge"
    end

    test "generates slug for player with special chars in name" do
      changeset = Player.changeset(%Player{}, %{full_name: "Shohei Ohtani"})
      assert Ecto.Changeset.get_change(changeset, :slug) == "shohei-ohtani"
    end

    test "does not overwrite existing slug" do
      player = %Player{slug: "custom-slug"}
      changeset = Player.changeset(player, %{full_name: "Aaron Judge"})
      assert Ecto.Changeset.get_field(changeset, :slug) == "custom-slug"
    end

    test "casts optional fields" do
      attrs = %{
        full_name: "Aaron Judge",
        first_name: "Aaron",
        last_name: "Judge",
        position: "OF",
        bats: "R",
        throws: "R",
        height: "6-7",
        weight: 282,
        status: "active",
        jersey_number: 99
      }

      changeset = Player.changeset(%Player{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :position) == "OF"
      assert Ecto.Changeset.get_change(changeset, :jersey_number) == 99
    end

    test "defaults status to active" do
      player = %Player{}
      assert player.status == "active"
    end
  end
end
