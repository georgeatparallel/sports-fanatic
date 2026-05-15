defmodule SportsFanatic.Agents.NewsAgentResultTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Agents.NewsAgentResult

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp valid_attrs do
    %{
      user_id: Ecto.UUID.generate(),
      setting_id: Ecto.UUID.generate(),
      run_date: ~D[2026-05-15]
    }
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 — required fields" do
    test "valid changeset with user_id, setting_id, and run_date" do
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, valid_attrs())
      assert changeset.valid?
    end

    test "invalid when user_id is missing" do
      attrs = Map.delete(valid_attrs(), :user_id)
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, attrs)
      refute changeset.valid?
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when setting_id is missing" do
      attrs = Map.delete(valid_attrs(), :setting_id)
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, attrs)
      refute changeset.valid?
      assert %{setting_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when run_date is missing" do
      attrs = Map.delete(valid_attrs(), :run_date)
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, attrs)
      refute changeset.valid?
      assert %{run_date: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # changeset/2 — optional fields with defaults
  # ---------------------------------------------------------------------------

  describe "changeset/2 — matched_news_item_ids" do
    test "defaults to empty list on struct" do
      assert %NewsAgentResult{}.matched_news_item_ids == []
    end

    test "accepts a list of UUIDs" do
      ids = [Ecto.UUID.generate(), Ecto.UUID.generate()]
      attrs = Map.put(valid_attrs(), :matched_news_item_ids, ids)
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :matched_news_item_ids) == ids
    end

    test "accepts an empty list" do
      attrs = Map.put(valid_attrs(), :matched_news_item_ids, [])
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, attrs)
      assert changeset.valid?
    end
  end

  describe "changeset/2 — exa_results" do
    test "accepts a map for exa_results" do
      exa = %{"articles" => [%{"title" => "Judge hits HR", "url" => "https://example.com"}]}
      attrs = Map.put(valid_attrs(), :exa_results, exa)
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :exa_results) == exa
    end

    test "accepts nil for exa_results" do
      attrs = Map.put(valid_attrs(), :exa_results, nil)
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, attrs)
      assert changeset.valid?
    end

    test "valid without exa_results provided" do
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, valid_attrs())
      assert changeset.valid?
      assert is_nil(Ecto.Changeset.get_change(changeset, :exa_results))
    end
  end

  describe "changeset/2 — explanation" do
    test "accepts an explanation string" do
      attrs = Map.put(valid_attrs(), :explanation, "Found 3 articles about Judge's HR streak")
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :explanation) =~ "Found 3"
    end

    test "valid without explanation" do
      changeset = NewsAgentResult.changeset(%NewsAgentResult{}, valid_attrs())
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Schema defaults
  # ---------------------------------------------------------------------------

  describe "schema defaults" do
    test "matched_news_item_ids defaults to empty list on schema struct" do
      result = %NewsAgentResult{}
      assert result.matched_news_item_ids == []
    end
  end
end
