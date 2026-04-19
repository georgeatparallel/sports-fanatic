defmodule SportsFanatic.Mlb.TeamTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Mlb.Team

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "changeset/2" do
    test "valid changeset with required name" do
      attrs = %{name: "Yankees", city: "New York"}
      changeset = Team.changeset(%Team{}, attrs)
      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = Team.changeset(%Team{}, %{city: "New York"})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "auto-generates slug from city and name when slug is nil" do
      attrs = %{name: "Yankees", city: "New York"}
      changeset = Team.changeset(%Team{}, attrs)
      assert Ecto.Changeset.get_change(changeset, :slug) == "new-york-yankees"
    end

    test "does not overwrite existing slug" do
      team = %Team{slug: "custom-slug"}
      changeset = Team.changeset(team, %{name: "Yankees", city: "New York"})
      assert Ecto.Changeset.get_field(changeset, :slug) == "custom-slug"
    end

    test "casts optional fields" do
      attrs = %{
        name: "Dodgers",
        city: "Los Angeles",
        abbreviation: "LAD",
        division: "NL West",
        league: "NL"
      }

      changeset = Team.changeset(%Team{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :abbreviation) == "LAD"
      assert Ecto.Changeset.get_change(changeset, :division) == "NL West"
      assert Ecto.Changeset.get_change(changeset, :league) == "NL"
    end
  end

  describe "Slug.slugify/1" do
    test "lowercases and hyphenates" do
      assert Slug.slugify("New York Yankees") == "new-york-yankees"
    end

    test "removes special characters" do
      assert Slug.slugify("St. Louis Cardinals") == "st-louis-cardinals"
    end

    test "collapses multiple spaces" do
      assert Slug.slugify("Los  Angeles  Dodgers") == "los-angeles-dodgers"
    end

    test "collapses multiple hyphens" do
      assert Slug.slugify("San--Francisco Giants") == "san-francisco-giants"
    end

    test "trims leading and trailing hyphens" do
      assert Slug.slugify(" -Yankees- ") == "yankees"
    end

    test "handles empty string" do
      assert Slug.slugify("") == ""
    end

    test "handles non-binary input" do
      assert Slug.slugify(nil) == ""
      assert Slug.slugify(123) == ""
    end
  end
end
