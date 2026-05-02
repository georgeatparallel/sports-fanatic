defmodule SportsFanatic.Content.NewsItemTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Content.NewsItem

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp valid_attrs do
    %{
      source: "fantasy_nerds",
      slug: "judge-hits-home-run",
      title: "Judge Hits Home Run",
      body: "Aaron Judge launched his 50th home run of the season.",
      published_date: ~D[2026-05-01]
    }
  end

  # ---------------------------------------------------------------------------
  # Required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 required fields" do
    test "valid changeset when all required fields present" do
      changeset = NewsItem.changeset(%NewsItem{}, valid_attrs())
      assert changeset.valid?
    end

    test "invalid when source is missing" do
      attrs = Map.delete(valid_attrs(), :source)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{source: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when slug is missing" do
      attrs = Map.delete(valid_attrs(), :slug)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{slug: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when title is missing" do
      attrs = Map.delete(valid_attrs(), :title)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when body is missing" do
      attrs = Map.delete(valid_attrs(), :body)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when published_date is missing" do
      attrs = Map.delete(valid_attrs(), :published_date)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{published_date: ["can't be blank"]} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # Sentiment validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 sentiment validation" do
    test "accepts positive sentiment" do
      attrs = Map.put(valid_attrs(), :sentiment, "positive")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :sentiment) == "positive"
    end

    test "accepts neutral sentiment" do
      attrs = Map.put(valid_attrs(), :sentiment, "neutral")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "accepts negative sentiment" do
      attrs = Map.put(valid_attrs(), :sentiment, "negative")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "rejects unknown sentiment value" do
      attrs = Map.put(valid_attrs(), :sentiment, "angry")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{sentiment: [_]} = errors_on(changeset)
    end

    test "empty string sentiment is treated as nil and is valid (field is optional)" do
      # Ecto casts empty string to nil for string fields, so validate_inclusion
      # is not triggered and the changeset remains valid.
      attrs = Map.put(valid_attrs(), :sentiment, "")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "is valid when sentiment is nil (field is optional)" do
      attrs = Map.put(valid_attrs(), :sentiment, nil)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Category validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 category validation" do
    test "accepts all injury sub-categories" do
      injury_categories = ~w(
        injury_elbow injury_shoulder injury_oblique injury_back
        injury_knee injury_hamstring injury_other
      )

      for cat <- injury_categories do
        attrs = Map.put(valid_attrs(), :category, cat)
        changeset = NewsItem.changeset(%NewsItem{}, attrs)

        assert changeset.valid?,
               "Expected #{cat} to be valid but got errors: #{inspect(errors_on(changeset))}"
      end
    end

    test "accepts trade category" do
      attrs = Map.put(valid_attrs(), :category, "trade")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "accepts hit_by_pitch category" do
      attrs = Map.put(valid_attrs(), :category, "hit_by_pitch")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "accepts news category" do
      attrs = Map.put(valid_attrs(), :category, "news")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "accepts general category" do
      attrs = Map.put(valid_attrs(), :category, "general")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "rejects unknown category value" do
      attrs = Map.put(valid_attrs(), :category, "weather")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{category: [_]} = errors_on(changeset)
    end

    test "empty string category is treated as nil and is valid (field is optional)" do
      # Ecto casts empty string to nil for string fields, so validate_inclusion
      # is not triggered and the changeset remains valid.
      attrs = Map.put(valid_attrs(), :category, "")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "is valid when category is nil (field is optional)" do
      attrs = Map.put(valid_attrs(), :category, nil)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # AI enrichment fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 AI enrichment fields" do
    test "casts ai_summary" do
      attrs = Map.put(valid_attrs(), :ai_summary, "Judge continues his historic season.")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :ai_summary) ==
               "Judge continues his historic season."
    end

    test "casts s3_key" do
      key = "news/raw/2026/05/01/fn-12345.json"
      attrs = Map.put(valid_attrs(), :s3_key, key)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :s3_key) == key
    end

    test "rejects s3_key longer than 500 characters" do
      attrs = Map.put(valid_attrs(), :s3_key, String.duplicate("a", 501))
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{s3_key: [_]} = errors_on(changeset)
    end

    test "accepts s3_key at exactly 500 characters" do
      attrs = Map.put(valid_attrs(), :s3_key, String.duplicate("a", 500))
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "casts source_url" do
      attrs = Map.put(valid_attrs(), :source_url, "https://example.com/article")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :source_url) == "https://example.com/article"
    end

    test "rejects source_url longer than 1000 characters" do
      attrs = Map.put(valid_attrs(), :source_url, "https://" <> String.duplicate("a", 993))
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{source_url: [_]} = errors_on(changeset)
    end

    test "casts author" do
      attrs = Map.put(valid_attrs(), :author, "Jane Doe")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :author) == "Jane Doe"
    end

    test "rejects author longer than 200 characters" do
      attrs = Map.put(valid_attrs(), :author, String.duplicate("a", 201))
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      refute changeset.valid?
      assert %{author: [_]} = errors_on(changeset)
    end

    test "ai_processed defaults to false on new struct" do
      news_item = %NewsItem{}
      assert news_item.ai_processed == false
    end

    test "casts ai_processed to true" do
      attrs = Map.put(valid_attrs(), :ai_processed, true)
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :ai_processed) == true
    end

    test "valid changeset with all AI fields populated" do
      attrs =
        valid_attrs()
        |> Map.put(:sentiment, "positive")
        |> Map.put(:category, "trade")
        |> Map.put(:ai_summary, "Player traded to Yankees.")
        |> Map.put(:s3_key, "news/raw/2026/05/01/fn-99.json")
        |> Map.put(:source_url, "https://example.com/trade-news")
        |> Map.put(:author, "John Smith")
        |> Map.put(:ai_processed, true)

      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Standard optional fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 optional fields" do
    test "casts external_id" do
      attrs = Map.put(valid_attrs(), :external_id, "fn-abc-123")
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :external_id) == "fn-abc-123"
    end

    test "casts is_premium with default false" do
      news_item = %NewsItem{}
      assert news_item.is_premium == false
    end

    test "casts player_ids as array" do
      attrs = Map.put(valid_attrs(), :player_ids, ["00000000-0000-0000-0000-000000000001"])
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "casts team_ids as array" do
      attrs = Map.put(valid_attrs(), :team_ids, ["00000000-0000-0000-0000-000000000002"])
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end
  end
end
