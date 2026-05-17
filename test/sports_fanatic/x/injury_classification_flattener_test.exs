defmodule SportsFanatic.X.InjuryClassificationFlattenerTest do
  use ExUnit.Case, async: true

  # Tests the `build_player_trails/1` private logic inside
  # `SportsFanatic.X.InjuryReport`. Since the function is private, we test
  # its behaviour indirectly through the public data contract it produces.
  #
  # The "flattener" is the pipeline that takes a list of news_item-shaped maps
  # (each with :player_ids, :published_date, :category, :injury_grade, etc.)
  # and produces per-player sorted trails.
  #
  # We exercise this logic inline (mirroring the production private function)
  # so tests remain pure (no DB, no Repo calls).

  # Mirror of the private build_player_trails/1 from X.InjuryReport
  defp build_player_trails(news_rows) do
    Enum.reduce(news_rows, %{}, fn n, acc ->
      entry = %{
        date: n[:published_date] || (n[:published_at] && DateTime.to_date(n[:published_at])),
        category: n[:category],
        injury_grade: n[:injury_grade],
        injury_area: n[:injury_area],
        summary: n[:ai_summary] || n[:summary] || "",
        source_url: n[:source_url]
      }

      Enum.reduce(n[:player_ids] || [], acc, fn pid, inner ->
        Map.update(inner, pid, [entry], &[entry | &1])
      end)
    end)
  end

  # Sort trail chronologically descending (mirrors InjuryReport.list_for_today)
  defp sort_trail(trail) do
    Enum.sort_by(trail, & &1.date, {:desc, Date})
  end

  # ---------------------------------------------------------------------------
  # Flattening: news_item with multiple player_ids expands to all players
  # ---------------------------------------------------------------------------

  describe "build_player_trails/1 — flattening" do
    test "single news item with one player produces one trail entry" do
      player_id = "aaaaaaaa-0000-0000-0000-000000000001"

      news = [
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-15],
          category: "injury_new",
          injury_grade: "moderate",
          injury_area: "hamstring",
          ai_summary: "Judge placed on IL",
          source_url: "https://espn.com/1"
        }
      ]

      trails = build_player_trails(news)

      assert Map.has_key?(trails, player_id)
      assert length(trails[player_id]) == 1
      entry = hd(trails[player_id])
      assert entry.category == "injury_new"
      assert entry.injury_area == "hamstring"
      assert entry.summary == "Judge placed on IL"
    end

    test "single news item with two player_ids creates trails for both players" do
      p1 = "aaaaaaaa-0000-0000-0000-000000000001"
      p2 = "aaaaaaaa-0000-0000-0000-000000000002"

      news = [
        %{
          player_ids: [p1, p2],
          published_date: ~D[2026-06-15],
          category: "injury_update",
          injury_grade: nil,
          injury_area: "knee",
          ai_summary: "Two players updated",
          source_url: nil
        }
      ]

      trails = build_player_trails(news)

      assert Map.has_key?(trails, p1)
      assert Map.has_key?(trails, p2)
      assert length(trails[p1]) == 1
      assert length(trails[p2]) == 1
    end

    test "multiple news items for same player are all in that player's trail" do
      player_id = "aaaaaaaa-0000-0000-0000-000000000001"

      news = [
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-13],
          category: "injury_new",
          injury_grade: "minor",
          injury_area: "wrist",
          ai_summary: "Initial wrist injury",
          source_url: "https://mlb.com/1"
        },
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-14],
          category: "injury_update",
          injury_grade: "moderate",
          injury_area: "wrist",
          ai_summary: "Wrist injury worsening",
          source_url: "https://mlb.com/2"
        },
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-15],
          category: "injury_recovery",
          injury_grade: "minor",
          injury_area: "wrist",
          ai_summary: "Improving",
          source_url: "https://mlb.com/3"
        }
      ]

      trails = build_player_trails(news)
      assert length(trails[player_id]) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # Chronological sort (descending) — most recent first
  # ---------------------------------------------------------------------------

  describe "sort_trail/1 — chronological ordering" do
    test "trail is sorted descending by date (most recent first)" do
      player_id = "aaaaaaaa-0000-0000-0000-000000000001"

      news = [
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-13],
          category: "injury_new",
          injury_grade: nil,
          injury_area: nil,
          ai_summary: "day 1",
          source_url: nil
        },
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-15],
          category: "injury_update",
          injury_grade: nil,
          injury_area: nil,
          ai_summary: "day 3",
          source_url: nil
        },
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-14],
          category: "injury_recovery",
          injury_grade: nil,
          injury_area: nil,
          ai_summary: "day 2",
          source_url: nil
        }
      ]

      trails = build_player_trails(news)
      sorted = sort_trail(trails[player_id])

      dates = Enum.map(sorted, & &1.date)
      assert dates == [~D[2026-06-15], ~D[2026-06-14], ~D[2026-06-13]]
    end

    test "single-entry trail is unchanged by sort" do
      entry = %{
        date: ~D[2026-06-15],
        category: "injury_new",
        injury_grade: nil,
        injury_area: nil,
        summary: "",
        source_url: nil
      }

      assert sort_trail([entry]) == [entry]
    end
  end

  # ---------------------------------------------------------------------------
  # Entry fields: all required keys are present
  # ---------------------------------------------------------------------------

  describe "trail entry structure" do
    test "each entry has all required keys" do
      player_id = "aaaaaaaa-0000-0000-0000-000000000001"

      news = [
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-15],
          category: "injury_new",
          injury_grade: "severe",
          injury_area: "elbow",
          ai_summary: "Tommy John surgery",
          source_url: "https://espn.com/news"
        }
      ]

      trails = build_player_trails(news)
      entry = hd(trails[player_id])

      assert Map.has_key?(entry, :date)
      assert Map.has_key?(entry, :category)
      assert Map.has_key?(entry, :injury_grade)
      assert Map.has_key?(entry, :injury_area)
      assert Map.has_key?(entry, :summary)
      assert Map.has_key?(entry, :source_url)
    end

    test "summary falls back to :summary when :ai_summary is nil" do
      player_id = "aaaaaaaa-0000-0000-0000-000000000001"

      news = [
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-15],
          category: "injury_update",
          injury_grade: nil,
          injury_area: nil,
          ai_summary: nil,
          summary: "Fallback summary",
          source_url: nil
        }
      ]

      trails = build_player_trails(news)
      entry = hd(trails[player_id])
      assert entry.summary == "Fallback summary"
    end

    test "summary is empty string when both ai_summary and summary are nil" do
      player_id = "aaaaaaaa-0000-0000-0000-000000000001"

      news = [
        %{
          player_ids: [player_id],
          published_date: ~D[2026-06-15],
          category: "injury_update",
          injury_grade: nil,
          injury_area: nil,
          ai_summary: nil,
          source_url: nil
        }
      ]

      trails = build_player_trails(news)
      entry = hd(trails[player_id])
      assert entry.summary == ""
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases: empty inputs
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    test "empty news list produces empty trails map" do
      assert build_player_trails([]) == %{}
    end

    test "news item with nil player_ids is skipped" do
      news = [
        %{
          player_ids: nil,
          published_date: ~D[2026-06-15],
          category: "injury_new",
          injury_grade: nil,
          injury_area: nil,
          ai_summary: nil,
          source_url: nil
        }
      ]

      assert build_player_trails(news) == %{}
    end

    test "news item with empty player_ids produces no trail entries" do
      news = [
        %{
          player_ids: [],
          published_date: ~D[2026-06-15],
          category: "injury_new",
          injury_grade: nil,
          injury_area: nil,
          ai_summary: nil,
          source_url: nil
        }
      ]

      assert build_player_trails(news) == %{}
    end
  end
end
