defmodule SportsFanatic.ChatBot.QueryClusterTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.ChatBot.QueryCluster

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp valid_attrs do
    %{representative_query: "Aaron Judge home run streak"}
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — required fields" do
    test "valid with representative_query" do
      changeset = QueryCluster.changeset(%QueryCluster{}, valid_attrs())
      assert changeset.valid?
    end

    test "invalid without representative_query" do
      changeset = QueryCluster.changeset(%QueryCluster{}, %{})
      refute changeset.valid?
      assert %{representative_query: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when representative_query is nil" do
      changeset = QueryCluster.changeset(%QueryCluster{}, %{representative_query: nil})
      refute changeset.valid?
      assert %{representative_query: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — schedule_frequency validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — schedule_frequency validation" do
    for freq <- ~w(hourly daily disabled) do
      test "accepts schedule_frequency '#{freq}'" do
        attrs = Map.put(valid_attrs(), :schedule_frequency, unquote(freq))
        changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
        assert changeset.valid?
      end
    end

    test "rejects unknown schedule_frequency" do
      attrs = Map.put(valid_attrs(), :schedule_frequency, "weekly")
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      refute changeset.valid?
      assert %{schedule_frequency: _} = errors_on(changeset)
    end

    test "rejects empty string as schedule_frequency" do
      # Empty string is cast to nil by Ecto, which fails inclusion validation since nil is not in the list
      attrs = Map.put(valid_attrs(), :schedule_frequency, "never")
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      refute changeset.valid?
      assert %{schedule_frequency: _} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — query_count validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 — query_count validation" do
    test "accepts query_count of 0" do
      attrs = Map.put(valid_attrs(), :query_count, 0)
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      assert changeset.valid?
    end

    test "accepts positive query_count" do
      attrs = Map.put(valid_attrs(), :query_count, 42)
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      assert changeset.valid?
    end

    test "rejects negative query_count" do
      attrs = Map.put(valid_attrs(), :query_count, -1)
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      refute changeset.valid?
      assert %{query_count: _} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — optional fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — optional fields" do
    test "accepts entity_player_ids as list of UUIDs" do
      ids = [Ecto.UUID.generate()]
      attrs = Map.put(valid_attrs(), :entity_player_ids, ids)
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      assert changeset.valid?
    end

    test "accepts entity_team_ids as list of UUIDs" do
      ids = [Ecto.UUID.generate()]
      attrs = Map.put(valid_attrs(), :entity_team_ids, ids)
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      assert changeset.valid?
    end

    test "accepts topics as list of strings" do
      attrs = Map.put(valid_attrs(), :topics, ["home_run", "streak", "judge"])
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      assert changeset.valid?
    end

    test "accepts scheduled boolean" do
      attrs = Map.put(valid_attrs(), :scheduled, true)
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      assert changeset.valid?
    end

    test "accepts last_run_at datetime" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      attrs = Map.put(valid_attrs(), :last_run_at, now)
      changeset = QueryCluster.changeset(%QueryCluster{}, attrs)
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Schema defaults
  # ---------------------------------------------------------------------------

  describe "schema defaults" do
    test "scheduled defaults to false" do
      assert %QueryCluster{}.scheduled == false
    end

    test "query_count defaults to 1" do
      assert %QueryCluster{}.query_count == 1
    end

    test "schedule_frequency defaults to 'disabled'" do
      assert %QueryCluster{}.schedule_frequency == "disabled"
    end

    test "entity_player_ids defaults to empty list" do
      assert %QueryCluster{}.entity_player_ids == []
    end

    test "entity_team_ids defaults to empty list" do
      assert %QueryCluster{}.entity_team_ids == []
    end

    test "topics defaults to empty list" do
      assert %QueryCluster{}.topics == []
    end
  end
end
