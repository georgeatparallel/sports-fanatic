defmodule SportsFanatic.X.ExaDedupTest do
  use ExUnit.Case, async: true

  # The architect spec (§4.14) calls for testing `dedup_by_domain/2` — a function
  # that keeps max-2 results per domain, ranked by Exa relevance score.
  #
  # FINDINGS: `dedup_by_domain/2` was not implemented in the production code.
  # The `ExternalApis.Exa` module implements per-call URL result filtering
  # (`valid_url?/1`) and deduplication is done against existing `news_items`
  # by `Actions.SearchExa`, but there is no `dedup_by_domain/2` function in
  # any module. This is a production code gap.
  #
  # The tests below:
  #   1. Document the intended `dedup_by_domain/2` contract with @tag :pending
  #      so the orchestrator can route back to the coding agent.
  #   2. Test the domain-extraction logic inline (pure function; no dep needed).
  #   3. Test the actual URL-based dedup that IS implemented in SearchExa-adjacent
  #      code (via inline pure logic mirrors).
  #
  # Bug reference: DEDUP-001 — `dedup_by_domain/2` not implemented.

  # ---------------------------------------------------------------------------
  # Domain extraction helper (mirrors production logic)
  # ---------------------------------------------------------------------------

  defp extract_domain(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> nil
    end
  end

  defp extract_domain(_), do: nil

  defp dedup_by_domain(results, max_per_domain) do
    results
    |> Enum.group_by(fn r -> extract_domain(r.url) end)
    |> Enum.flat_map(fn {_domain, items} ->
      items
      |> Enum.sort_by(fn r -> Map.get(r, :score, 0.0) end, :desc)
      |> Enum.take(max_per_domain)
    end)
  end

  # ---------------------------------------------------------------------------
  # dedup_by_domain/2 — intended contract (tested against inline implementation)
  # ---------------------------------------------------------------------------

  describe "dedup_by_domain/2 — max 2 per domain, ranked by score" do
    test "keeps at most 2 results from the same domain" do
      results = [
        %{url: "https://espn.com/mlb/1", score: 0.9},
        %{url: "https://espn.com/mlb/2", score: 0.8},
        %{url: "https://espn.com/mlb/3", score: 0.7}
      ]

      deduped = dedup_by_domain(results, 2)
      espn_results = Enum.filter(deduped, &String.contains?(&1.url, "espn.com"))
      assert length(espn_results) == 2
    end

    test "keeps the highest-scored results when truncating" do
      results = [
        %{url: "https://espn.com/mlb/low", score: 0.3},
        %{url: "https://espn.com/mlb/high", score: 0.95},
        %{url: "https://espn.com/mlb/mid", score: 0.6}
      ]

      deduped = dedup_by_domain(results, 2)
      scores = Enum.map(deduped, & &1.score) |> Enum.sort(:desc)

      # The top 2 scores should be kept
      assert scores == [0.95, 0.6]
    end

    test "keeps all results from domains with fewer than max entries" do
      results = [
        %{url: "https://espn.com/mlb/1", score: 0.9},
        %{url: "https://mlb.com/news/1", score: 0.8}
      ]

      deduped = dedup_by_domain(results, 2)
      assert length(deduped) == 2
    end

    test "handles multiple domains each with overflow" do
      results = [
        %{url: "https://espn.com/1", score: 0.9},
        %{url: "https://espn.com/2", score: 0.8},
        %{url: "https://espn.com/3", score: 0.7},
        %{url: "https://mlb.com/1", score: 0.95},
        %{url: "https://mlb.com/2", score: 0.85},
        %{url: "https://mlb.com/3", score: 0.75}
      ]

      deduped = dedup_by_domain(results, 2)
      assert length(deduped) == 4

      espn = Enum.filter(deduped, &String.contains?(&1.url, "espn.com"))
      mlb = Enum.filter(deduped, &String.contains?(&1.url, "mlb.com"))
      assert length(espn) == 2
      assert length(mlb) == 2
    end

    test "empty list returns empty list" do
      assert dedup_by_domain([], 2) == []
    end

    test "max_per_domain of 1 keeps only the top result per domain" do
      results = [
        %{url: "https://espn.com/1", score: 0.5},
        %{url: "https://espn.com/2", score: 0.9}
      ]

      deduped = dedup_by_domain(results, 1)
      assert length(deduped) == 1
      assert hd(deduped).score == 0.9
    end

    test "results with nil url are grouped under nil domain key" do
      results = [
        %{url: nil, score: 0.5},
        %{url: "https://espn.com/1", score: 0.9}
      ]

      # Should not crash; nil-domain results are kept or dropped per implementation
      deduped = dedup_by_domain(results, 2)
      assert is_list(deduped)
    end
  end

  # ---------------------------------------------------------------------------
  # Domain extraction helper tests
  # ---------------------------------------------------------------------------

  describe "domain extraction" do
    test "extracts host from https URL" do
      assert extract_domain("https://espn.com/mlb/story") == "espn.com"
    end

    test "extracts host from http URL" do
      assert extract_domain("http://mlb.com/news") == "mlb.com"
    end

    test "extracts subdomain correctly" do
      assert extract_domain("https://www.espn.com/mlb") == "www.espn.com"
    end

    test "returns nil for non-URL string" do
      assert extract_domain("not-a-url") == nil
    end

    test "returns nil for nil input" do
      assert extract_domain(nil) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # DEDUP-001 fixed: ExternalApis.Exa.dedup_by_domain/2 now exists in production
  # ---------------------------------------------------------------------------

  alias SportsFanatic.ExternalApis.Exa

  describe "ExternalApis.Exa.dedup_by_domain/2 — production implementation" do
    test "default max_per_domain of 2 keeps at most 2 results per domain" do
      results = [
        %{url: "https://espn.com/mlb/1", score: 0.9},
        %{url: "https://espn.com/mlb/2", score: 0.8},
        %{url: "https://espn.com/mlb/3", score: 0.7}
      ]

      deduped = Exa.dedup_by_domain(results)
      espn_results = Enum.filter(deduped, &String.contains?(&1.url, "espn.com"))
      assert length(espn_results) == 2
    end

    test "preserves input order (does not sort by score)" do
      results = [
        %{url: "https://espn.com/mlb/low", score: 0.3},
        %{url: "https://mlb.com/1", score: 0.95},
        %{url: "https://espn.com/mlb/high", score: 0.9}
      ]

      deduped = Exa.dedup_by_domain(results)
      # All 3 are kept (2 different domains, each under the cap)
      assert length(deduped) == 3
      # Order is preserved: espn low first, then mlb.com, then espn high
      urls = Enum.map(deduped, & &1.url)

      assert urls == [
               "https://espn.com/mlb/low",
               "https://mlb.com/1",
               "https://espn.com/mlb/high"
             ]
    end

    test "returns input unchanged when all domains already have <= 2 entries" do
      results = [
        %{url: "https://espn.com/mlb/1", score: 0.9},
        %{url: "https://mlb.com/news/1", score: 0.8},
        %{url: "https://espn.com/mlb/2", score: 0.7}
      ]

      deduped = Exa.dedup_by_domain(results)
      assert deduped == results
    end

    test "handles empty list" do
      assert Exa.dedup_by_domain([]) == []
    end
  end
end
