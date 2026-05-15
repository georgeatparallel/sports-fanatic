defmodule SportsFanatic.Content.NewsItemDomainTagsTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Content.NewsItem

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp base_attrs do
    %{
      source: "fantasy_nerds",
      slug: "judge-walks-off-yankees",
      title: "Judge Walks Off Yankees",
      body: "Aaron Judge hit a walk-off home run to win the game.",
      published_date: ~D[2026-05-15]
    }
  end

  # ---------------------------------------------------------------------------
  # domain_tags field
  # ---------------------------------------------------------------------------

  describe "domain_tags field" do
    test "defaults to empty list on schema struct" do
      assert %NewsItem{}.domain_tags == []
    end

    test "accepts a list of domain tag strings" do
      attrs = Map.put(base_attrs(), :domain_tags, ["walk-off", "home-run", "streak"])
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :domain_tags) == [
               "walk-off",
               "home-run",
               "streak"
             ]
    end

    test "accepts an empty list" do
      attrs = Map.put(base_attrs(), :domain_tags, [])
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "valid when domain_tags is not provided" do
      changeset = NewsItem.changeset(%NewsItem{}, base_attrs())
      assert changeset.valid?
    end

    test "accepts known baseball domain tag values" do
      tags =
        ~w(streak home-run trade-deadline walk-off no-hitter save closer bullpen rotation prospect call-up slump)

      attrs = Map.put(base_attrs(), :domain_tags, tags)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :domain_tags) == tags
    end

    test "changeset is valid with domain_tags alongside other fields" do
      attrs =
        base_attrs()
        |> Map.put(:domain_tags, ["home-run", "streak"])
        |> Map.put(:category, "performance")
        |> Map.put(:sentiment, "positive")

      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Regression: domain_tags field does not break existing validations
  # ---------------------------------------------------------------------------

  describe "domain_tags does not affect other validations" do
    test "still requires source field" do
      attrs = base_attrs() |> Map.delete(:source) |> Map.put(:domain_tags, ["streak"])
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{source: _} = errors_on(changeset)
    end

    test "still rejects invalid category even when domain_tags present" do
      attrs =
        base_attrs() |> Map.put(:domain_tags, ["streak"]) |> Map.put(:category, "not_a_category")

      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{category: _} = errors_on(changeset)
    end
  end
end
