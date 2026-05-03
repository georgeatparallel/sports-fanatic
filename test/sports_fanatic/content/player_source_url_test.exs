defmodule SportsFanatic.Content.PlayerSourceUrlTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Content.PlayerSourceUrl

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp valid_attrs do
    %{
      player_id: Ecto.UUID.generate(),
      url: "https://www.espn.com/mlb/story/12345",
      source_type: "news"
    }
  end

  # ---------------------------------------------------------------------------
  # Required fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 required fields" do
    test "valid changeset when all required fields present" do
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, valid_attrs())
      assert changeset.valid?
    end

    test "invalid without player_id" do
      attrs = Map.delete(valid_attrs(), :player_id)
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
      assert %{player_id: _} = errors_on(changeset)
    end

    test "invalid without url" do
      attrs = Map.delete(valid_attrs(), :url)
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
      assert %{url: _} = errors_on(changeset)
    end

    test "invalid without source_type" do
      attrs = Map.delete(valid_attrs(), :source_type)
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
      assert %{source_type: _} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # Source type validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 source_type validation" do
    test "accepts valid source types" do
      for type <- ~w(news analyst fantasy_betting) do
        attrs = Map.put(valid_attrs(), :source_type, type)
        changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
        assert changeset.valid?, "expected #{type} to be valid"
      end
    end

    test "rejects invalid source type" do
      attrs = Map.put(valid_attrs(), :source_type, "invalid_type")
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
      assert %{source_type: _} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # URL validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 URL validation" do
    test "accepts valid HTTP URL" do
      attrs = Map.put(valid_attrs(), :url, "http://example.com/article")
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      assert changeset.valid?
    end

    test "accepts valid HTTPS URL" do
      attrs = Map.put(valid_attrs(), :url, "https://example.com/article")
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      assert changeset.valid?
    end

    test "rejects non-HTTP URL" do
      attrs = Map.put(valid_attrs(), :url, "ftp://example.com/file")
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
      assert %{url: _} = errors_on(changeset)
    end

    test "rejects malformed URL" do
      attrs = Map.put(valid_attrs(), :url, "not a url at all")
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
      assert %{url: _} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # Classification validation
  # ---------------------------------------------------------------------------

  describe "changeset/2 classification validation" do
    test "accepts valid classifications" do
      for classification <- ~w(performance_analysis injury_report trade_rumor
                               prospect_evaluation fantasy_value betting_insight
                               general_news) do
        attrs = Map.put(valid_attrs(), :classification, classification)
        changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
        assert changeset.valid?, "expected #{classification} to be valid"
      end
    end

    test "rejects invalid classification" do
      attrs = Map.put(valid_attrs(), :classification, "bogus_classification")
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      refute changeset.valid?
      assert %{classification: _} = errors_on(changeset)
    end
  end

  # ---------------------------------------------------------------------------
  # Digest field
  # ---------------------------------------------------------------------------

  describe "changeset/2 digest field" do
    test "accepts a digest string" do
      digest_text = """
      Aaron Judge continues his dominant 2026 campaign with a three-homer game \
      against the Red Sox. He is now batting .312 with 18 home runs on the season.

      The performance extends his hitting streak to 15 games, the longest active \
      streak in the American League. Manager Aaron Boone noted that Judge's plate \
      discipline has been exceptional, with a walk rate exceeding 15%.
      """

      attrs = Map.put(valid_attrs(), :digest, digest_text)
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :digest) == digest_text
    end

    test "accepts nil digest" do
      attrs = Map.put(valid_attrs(), :digest, nil)
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      assert changeset.valid?
    end

    test "digest is optional (not required)" do
      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, valid_attrs())
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :digest) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Optional fields
  # ---------------------------------------------------------------------------

  describe "changeset/2 optional fields" do
    test "accepts all optional fields" do
      attrs =
        valid_attrs()
        |> Map.merge(%{
          classification: "performance_analysis",
          content_summary: "Judge hits three homers",
          key_facts: %{"facts" => ["3 HR game", ".312 batting average"]},
          content_text: "Full article text here...",
          digest: "A concise rewrite of the article content.",
          processed_at: ~U[2026-05-03 08:00:00Z]
        })

      changeset = PlayerSourceUrl.changeset(%PlayerSourceUrl{}, attrs)
      assert changeset.valid?
    end
  end
end
