defmodule SportsFanaticWeb.SEOComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @endpoint SportsFanaticWeb.Endpoint

  # ---------------------------------------------------------------------------
  # date_nav/1 — both prev and next dates present
  # ---------------------------------------------------------------------------

  describe "date_nav/1 with both prev_date and next_date" do
    test "renders a prev link with ISO date in the href" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      assert html =~ ~s(href="/mlb/news/2026-05-09")
    end

    test "renders a next link with ISO date in the href" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      assert html =~ ~s(href="/mlb/news/2026-05-11")
    end

    test "renders formatted prev date text using abbreviated month" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      assert html =~ "May 09"
    end

    test "renders formatted next date text using abbreviated month" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      assert html =~ "May 11"
    end

    test "renders left arrow entity before prev date" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      # Phoenix renders &larr; as the literal HTML entity string
      assert html =~ "&larr;"
    end

    test "renders right arrow entity after next date" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      # Phoenix renders &rarr; as the literal HTML entity string
      assert html =~ "&rarr;"
    end

    test "renders two anchor tags when both dates are present" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      # Count anchor tags by checking both hrefs exist
      assert html =~ ~s(href="/mlb/news/2026-05-09")
      assert html =~ ~s(href="/mlb/news/2026-05-11")
    end

    test "uses the base_path for both links" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/lineups"
        )

      assert html =~ ~s(href="/mlb/lineups/2026-05-09")
      assert html =~ ~s(href="/mlb/lineups/2026-05-11")
    end

    test "has the date navigation aria-label" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      assert html =~ ~s(aria-label="Date navigation")
    end
  end

  # ---------------------------------------------------------------------------
  # date_nav/1 — prev_date only (no next)
  # ---------------------------------------------------------------------------

  describe "date_nav/1 with only prev_date" do
    test "renders prev link" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: nil,
          base_path: "/mlb/news"
        )

      assert html =~ ~s(href="/mlb/news/2026-05-09")
    end

    test "does not render a next anchor tag" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: nil,
          base_path: "/mlb/news"
        )

      refute html =~ "&rarr;"
    end

    test "renders a placeholder span on the right side instead of a link" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: nil,
          base_path: "/mlb/news"
        )

      # The template renders an empty <span></span> when next_date is nil
      assert html =~ "<span></span>"
    end
  end

  # ---------------------------------------------------------------------------
  # date_nav/1 — next_date only (no prev)
  # ---------------------------------------------------------------------------

  describe "date_nav/1 with only next_date" do
    test "renders next link" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      assert html =~ ~s(href="/mlb/news/2026-05-11")
    end

    test "does not render a prev anchor tag" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      refute html =~ "&larr;"
    end

    test "renders a placeholder span on the left side instead of a link" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      assert html =~ "<span></span>"
    end
  end

  # ---------------------------------------------------------------------------
  # date_nav/1 — no dates at all
  # ---------------------------------------------------------------------------

  describe "date_nav/1 with neither prev nor next date" do
    test "renders no anchor tags" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: nil,
          base_path: "/mlb/news"
        )

      refute html =~ "<a "
    end

    test "renders two placeholder spans" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: nil,
          base_path: "/mlb/news"
        )

      # Both left and right placeholders are empty spans
      occurrences = html |> String.split("<span></span>") |> length()
      assert occurrences >= 3
    end

    test "still renders the nav element" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: nil,
          base_path: "/mlb/news"
        )

      assert html =~ "<nav"
    end
  end

  # ---------------------------------------------------------------------------
  # date_nav/1 — link_type attribute (:href vs :patch)
  # ---------------------------------------------------------------------------

  describe "date_nav/1 with link_type={:patch}" do
    test "prev link renders as a LiveView patch anchor (data-phx-link attribute)" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: nil,
          base_path: "/mlb/news",
          link_type: :patch
        )

      assert html =~ ~s(data-phx-link="patch")
    end

    test "next link renders as a LiveView patch anchor (data-phx-link attribute)" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news",
          link_type: :patch
        )

      assert html =~ ~s(data-phx-link="patch")
    end

    test "both prev and next links render as patch anchors when both dates present" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news",
          link_type: :patch
        )

      occurrences = html |> String.split(~s(data-phx-link="patch")) |> length()
      assert occurrences == 3
    end

    test "patch link still contains the correct ISO date path" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: nil,
          base_path: "/mlb/news",
          link_type: :patch
        )

      assert html =~ "/mlb/news/2026-05-09"
    end

    test "patch link still renders an href attribute alongside data-phx-link" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: nil,
          base_path: "/mlb/news",
          link_type: :patch
        )

      # Phoenix LiveView .link patch renders both href and data-phx-link on the anchor
      assert html =~ ~s(href="/mlb/news/2026-05-09")
      assert html =~ ~s(data-phx-link="patch")
    end
  end

  describe "date_nav/1 with link_type={:href} (explicit)" do
    test "prev link renders a plain anchor with href" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: nil,
          base_path: "/mlb/news",
          link_type: :href
        )

      assert html =~ ~s(href="/mlb/news/2026-05-09")
    end

    test "next link renders a plain anchor with href" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news",
          link_type: :href
        )

      assert html =~ ~s(href="/mlb/news/2026-05-11")
    end

    test "href link does not render data-phx-link attribute" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news",
          link_type: :href
        )

      refute html =~ "data-phx-link"
    end
  end

  describe "date_nav/1 default link_type is :href" do
    test "omitting link_type renders plain anchor with href (backward compat)" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-05-09],
          next_date: ~D[2026-05-11],
          base_path: "/mlb/news"
        )

      # Default must produce plain anchors, no LiveView-specific attributes
      assert html =~ ~s(href="/mlb/news/2026-05-09")
      assert html =~ ~s(href="/mlb/news/2026-05-11")
      refute html =~ "data-phx-link"
    end
  end

  # ---------------------------------------------------------------------------
  # date_nav/1 — base_path variations
  # ---------------------------------------------------------------------------

  describe "date_nav/1 base_path is used correctly" do
    test "lineups base path produces correct prev URL" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-04-30],
          next_date: nil,
          base_path: "/mlb/lineups"
        )

      assert html =~ ~s(href="/mlb/lineups/2026-04-30")
    end

    test "news base path produces correct next URL" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: nil,
          next_date: ~D[2026-05-02],
          base_path: "/mlb/news"
        )

      assert html =~ ~s(href="/mlb/news/2026-05-02")
    end

    test "dates from different months format correctly" do
      html =
        render_component(&SportsFanaticWeb.SEOComponents.date_nav/1,
          prev_date: ~D[2026-12-31],
          next_date: ~D[2027-01-02],
          base_path: "/mlb/news"
        )

      assert html =~ "Dec 31"
      assert html =~ "Jan 02"
    end
  end
end
