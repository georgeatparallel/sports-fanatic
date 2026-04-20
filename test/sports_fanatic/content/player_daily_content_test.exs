defmodule SportsFanatic.Content.PlayerDailyContentTest do
  @moduledoc """
  Unit tests for `PlayerDailyContent.changeset/2`.
  No database required — tests validate changeset logic only.
  """
  use ExUnit.Case, async: true

  alias SportsFanatic.Content.PlayerDailyContent

  @valid_uuid "00000000-0000-0000-0000-000000000001"
  @valid_uuid2 "00000000-0000-0000-0000-000000000002"

  @valid_attrs %{
    player_id: @valid_uuid,
    team_id: @valid_uuid2,
    content_date: ~D[2026-04-20],
    headline: "Aaron Judge Faces Left-Handed Challenge at Fenway",
    lead_paragraph: "Aaron Judge enters today's matchup on a hot streak.",
    tldr: "Judge is 3-for-5 vs LHP this month. Moderate upside today.",
    faq_items: [
      %{
        "question" => "Is Aaron Judge in today's lineup?",
        "answer" => "Yes, Aaron Judge is batting 2nd today."
      }
    ],
    meta_description: "Aaron Judge today: matchup analysis, stats, and projections for April 20.",
    keywords: ["aaron judge", "yankees", "mlb lineup"],
    json_ld: %{
      "@context" => "https://schema.org",
      "@type" => "Person",
      "name" => "Aaron Judge"
    }
  }

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, @valid_attrs)
      assert changeset.valid?
    end

    test "invalid without player_id" do
      attrs = Map.delete(@valid_attrs, :player_id)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{player_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without team_id" do
      attrs = Map.delete(@valid_attrs, :team_id)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{team_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without content_date" do
      attrs = Map.delete(@valid_attrs, :content_date)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{content_date: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without headline" do
      attrs = Map.delete(@valid_attrs, :headline)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{headline: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without lead_paragraph" do
      attrs = Map.delete(@valid_attrs, :lead_paragraph)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{lead_paragraph: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without tldr" do
      attrs = Map.delete(@valid_attrs, :tldr)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{tldr: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without faq_items" do
      attrs = Map.delete(@valid_attrs, :faq_items)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{faq_items: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without meta_description" do
      attrs = Map.delete(@valid_attrs, :meta_description)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{meta_description: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without keywords" do
      attrs = Map.delete(@valid_attrs, :keywords)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{keywords: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without json_ld" do
      attrs = Map.delete(@valid_attrs, :json_ld)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{json_ld: ["can't be blank"]} = errors_on(changeset)
    end

    test "meta_description validates max 160 characters" do
      long_desc = String.duplicate("x", 161)
      attrs = Map.put(@valid_attrs, :meta_description, long_desc)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      refute changeset.valid?
      assert %{meta_description: [msg]} = errors_on(changeset)
      assert msg =~ "160"
    end

    test "meta_description at exactly 160 characters is valid" do
      exact_desc = String.duplicate("x", 160)
      attrs = Map.put(@valid_attrs, :meta_description, exact_desc)
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      assert changeset.valid?
    end

    test "default status is published" do
      content = %PlayerDailyContent{}
      assert content.status == "published"
    end

    test "status defaults to published when not provided" do
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, @valid_attrs)
      assert Ecto.Changeset.get_field(changeset, :status) == "published"
    end

    test "status can be overridden" do
      attrs = Map.put(@valid_attrs, :status, "draft")
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :status) == "draft"
    end

    test "optional fields are not required" do
      # matchup_analysis, opposing_pitcher, park_factors, recent_form,
      # trends, projections, model_version, generation_ms, source_data
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, @valid_attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :matchup_analysis) == nil
      assert Ecto.Changeset.get_change(changeset, :opposing_pitcher) == nil
      assert Ecto.Changeset.get_change(changeset, :park_factors) == nil
      assert Ecto.Changeset.get_change(changeset, :recent_form) == nil
    end

    test "casts optional map fields when provided" do
      attrs =
        Map.merge(@valid_attrs, %{
          opposing_pitcher: %{"name" => "Chris Sale", "hand" => "L", "era" => 3.14},
          park_factors: %{"venue" => "Fenway Park", "hr_factor" => 1.1},
          projections: %{"hit_probability" => 0.35, "hr_probability" => 0.08}
        })

      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :opposing_pitcher) == %{
               "name" => "Chris Sale",
               "hand" => "L",
               "era" => 3.14
             }
    end

    test "casts trends as array of maps" do
      attrs =
        Map.put(@valid_attrs, :trends, [
          %{"period" => "7d", "avg" => ".340", "ops" => ".950", "note" => "Hot streak"}
        ])

      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      assert changeset.valid?
      assert [%{"period" => "7d"}] = Ecto.Changeset.get_change(changeset, :trends)
    end

    test "casts keywords as array of strings" do
      attrs = Map.put(@valid_attrs, :keywords, ["aaron judge", "yankees", "slugger"])
      changeset = PlayerDailyContent.changeset(%PlayerDailyContent{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :keywords) == [
               "aaron judge",
               "yankees",
               "slugger"
             ]
    end
  end
end
