defmodule SportsFanatic.Agents.ActionTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Agents.Action

  # ---------------------------------------------------------------------------
  # Behaviour callbacks
  # ---------------------------------------------------------------------------

  describe "Action behaviour" do
    test "defines a name/0 callback" do
      assert {:name, 0} in Action.behaviour_info(:callbacks)
    end

    test "defines a description/0 callback" do
      assert {:description, 0} in Action.behaviour_info(:callbacks)
    end

    test "defines a run/2 callback" do
      assert {:run, 2} in Action.behaviour_info(:callbacks)
    end
  end

  # ---------------------------------------------------------------------------
  # Macro __using__ — verify concrete action modules satisfy the behaviour
  # ---------------------------------------------------------------------------

  describe "concrete action modules implement all callbacks" do
    for mod <- [
          SportsFanatic.Agents.Actions.SearchLocalNews,
          SportsFanatic.Agents.Actions.SearchExa,
          SportsFanatic.Agents.Actions.ClassifyArticle,
          SportsFanatic.Agents.Actions.ResolveEntities
        ] do
      test "#{mod} exports name/0" do
        Code.ensure_loaded!(unquote(mod))
        assert function_exported?(unquote(mod), :name, 0)
      end

      test "#{mod} exports description/0" do
        Code.ensure_loaded!(unquote(mod))
        assert function_exported?(unquote(mod), :description, 0)
      end

      test "#{mod} exports run/2" do
        Code.ensure_loaded!(unquote(mod))
        assert function_exported?(unquote(mod), :run, 2)
      end

      test "#{mod}.name/0 returns a non-empty string" do
        Code.ensure_loaded!(unquote(mod))
        name = unquote(mod).name()
        assert is_binary(name) and name != ""
      end

      test "#{mod}.description/0 returns a non-empty string" do
        Code.ensure_loaded!(unquote(mod))
        desc = unquote(mod).description()
        assert is_binary(desc) and desc != ""
      end
    end
  end

  # ---------------------------------------------------------------------------
  # SearchLocalNews — pure logic: empty ts_query path (no DB required)
  # ---------------------------------------------------------------------------

  describe "SearchLocalNews.run/2 — empty query short-circuit" do
    test "returns {:ok, %{articles: [], count: 0}} for blank query" do
      # An all-whitespace query produces an empty ts_query string and returns
      # early without hitting the database.
      assert {:ok, %{articles: [], count: 0}} =
               SportsFanatic.Agents.Actions.SearchLocalNews.run(%{query: "   "}, %{})
    end

    test "returns {:ok, %{articles: [], count: 0}} for empty string query" do
      assert {:ok, %{articles: [], count: 0}} =
               SportsFanatic.Agents.Actions.SearchLocalNews.run(%{query: ""}, %{})
    end
  end

  # ---------------------------------------------------------------------------
  # ResolveEntities — pure logic: empty text produces empty results (no DB)
  # ---------------------------------------------------------------------------

  describe "ResolveEntities.run/2 — graceful DB error handling" do
    test "returns {:ok, empty result} when Repo is unavailable (rescue path)" do
      # The module rescues exceptions and returns empty results; with no DB in
      # unit tests, calling it with text that would normally query the DB will
      # either succeed (if sandbox is seeded elsewhere) or hit the rescue branch.
      # We assert the return shape is always {:ok, map} — never {:error, _}.
      result = SportsFanatic.Agents.Actions.ResolveEntities.run(%{text: "Aaron Judge"}, %{})
      assert match?({:ok, %{player_ids: _, team_ids: _, players: _, teams: _}}, result)
    end
  end
end
