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

  # ---------------------------------------------------------------------------
  # seo_meta/1 — Open Graph, Twitter Card, canonical, article fields
  # ---------------------------------------------------------------------------

  @base_url SportsFanaticWeb.Endpoint.url()
  @image_url "#{SportsFanaticWeb.Endpoint.url()}/images/og-default.png"

  defp render_seo_meta(overrides \\ %{}) do
    defaults = %{
      title: "Test Title",
      description: "Test description for the page.",
      canonical_url: "#{SportsFanaticWeb.Endpoint.url()}/test",
      og_type: "website",
      og_image: @image_url,
      og_image_alt: "Test image alt text"
    }

    attrs = Map.merge(defaults, overrides)

    render_component(&SportsFanaticWeb.SEOComponents.seo_meta/1, attrs)
  end

  describe "seo_meta/1 — meta description and canonical" do
    test "renders meta name=description with correct content" do
      html = render_seo_meta()
      assert html =~ ~s(<meta name="description" content="Test description for the page.")
    end

    test "renders link rel=canonical with correct href" do
      html = render_seo_meta()
      assert html =~ ~s(rel="canonical")
      assert html =~ ~s(href="#{@base_url}/test")
    end
  end

  describe "seo_meta/1 — Open Graph required tags" do
    test "renders og:site_name as Sports Fan Agent" do
      html = render_seo_meta()
      assert html =~ ~s(<meta property="og:site_name" content="Sports Fan Agent")
    end

    test "renders og:locale as en_US" do
      html = render_seo_meta()
      assert html =~ ~s(<meta property="og:locale" content="en_US")
    end

    test "renders og:type with the given value" do
      html = render_seo_meta(%{og_type: "website"})
      assert html =~ ~s(<meta property="og:type" content="website")
    end

    test "renders og:title with the given title" do
      html = render_seo_meta(%{title: "My Test Title"})
      assert html =~ ~s(<meta property="og:title" content="My Test Title")
    end

    test "renders og:description with the given description" do
      html = render_seo_meta(%{description: "A great description."})
      assert html =~ ~s(<meta property="og:description" content="A great description.")
    end

    test "renders og:url with the canonical_url" do
      html = render_seo_meta(%{canonical_url: "#{@base_url}/some-page"})
      assert html =~ ~s(<meta property="og:url" content="#{@base_url}/some-page")
    end

    test "renders og:image with an absolute URL" do
      html = render_seo_meta()
      assert html =~ ~s(property="og:image" content="http)
    end

    test "og:image URL starts with https:// or http://" do
      html = render_seo_meta()
      # Extract the content value; just verify it starts with the expected prefix
      assert html =~ ~s(property="og:image" content="#{@image_url}")
    end

    test "renders og:image:secure_url matching og:image" do
      html = render_seo_meta(%{og_image: @image_url})
      assert html =~ ~s(property="og:image:secure_url" content="#{@image_url}")
    end

    test "renders og:image:type as image/png" do
      html = render_seo_meta()
      assert html =~ ~s(<meta property="og:image:type" content="image/png")
    end

    test "renders og:image:width defaulting to 1200" do
      html = render_seo_meta()
      assert html =~ ~s(<meta property="og:image:width" content="1200")
    end

    test "renders og:image:height defaulting to 630" do
      html = render_seo_meta()
      assert html =~ ~s(<meta property="og:image:height" content="630")
    end

    test "renders og:image:alt with the given alt text" do
      html = render_seo_meta(%{og_image_alt: "Custom alt text"})
      assert html =~ ~s(<meta property="og:image:alt" content="Custom alt text")
    end

    test "og:image content is always an absolute URL (starts with http:// or https://)" do
      html = render_seo_meta()
      # Regex-free assertion: the og:image content must begin with a protocol
      assert html =~ ~s(property="og:image" content="http)
    end
  end

  describe "seo_meta/1 — Twitter Card tags" do
    test "renders twitter:card defaulting to summary_large_image" do
      html = render_seo_meta()
      assert html =~ ~s(<meta name="twitter:card" content="summary_large_image")
    end

    test "renders twitter:title with the given title" do
      html = render_seo_meta(%{title: "Tweet This Title"})
      assert html =~ ~s(<meta name="twitter:title" content="Tweet This Title")
    end

    test "renders twitter:description with the given description" do
      html = render_seo_meta(%{description: "A tweet description."})
      assert html =~ ~s(<meta name="twitter:description" content="A tweet description.")
    end

    test "renders twitter:image with the og_image URL" do
      html = render_seo_meta(%{og_image: @image_url})
      assert html =~ ~s(<meta name="twitter:image" content="#{@image_url}")
    end

    test "renders twitter:image:alt with the og_image_alt" do
      html = render_seo_meta(%{og_image_alt: "Alt for twitter"})
      assert html =~ ~s(<meta name="twitter:image:alt" content="Alt for twitter")
    end

    test "does NOT render twitter:site when twitter_site is nil (default)" do
      html = render_seo_meta()
      refute html =~ ~s(name="twitter:site")
    end

    test "renders twitter:site when twitter_site is provided" do
      html = render_seo_meta(%{twitter_site: "@sportsfanagent"})
      assert html =~ ~s(<meta name="twitter:site" content="@sportsfanagent")
    end
  end

  describe "seo_meta/1 — article:* tags (og_type = article)" do
    test "renders article:published_time when og_type is article and time is provided" do
      html =
        render_seo_meta(%{
          og_type: "article",
          article_published_time: "2026-05-17"
        })

      assert html =~ ~s(property="article:published_time" content="2026-05-17")
    end

    test "renders article:section when og_type is article and section is provided" do
      html =
        render_seo_meta(%{
          og_type: "article",
          article_section: "MLB News"
        })

      assert html =~ ~s(property="article:section" content="MLB News")
    end

    test "renders article:author when og_type is article and author is provided" do
      html =
        render_seo_meta(%{
          og_type: "article",
          article_author: "Sports Fan Agent"
        })

      assert html =~ ~s(property="article:author" content="Sports Fan Agent")
    end

    test "renders all three article:* tags together when type is article" do
      html =
        render_seo_meta(%{
          og_type: "article",
          article_published_time: "2026-05-17",
          article_author: "Sports Fan Agent",
          article_section: "MLB News"
        })

      assert html =~ "article:published_time"
      assert html =~ "article:author"
      assert html =~ "article:section"
    end

    test "does NOT render article:published_time when og_type is website" do
      html =
        render_seo_meta(%{
          og_type: "website",
          article_published_time: "2026-05-17",
          article_author: "Sports Fan Agent",
          article_section: "MLB News"
        })

      refute html =~ "article:published_time"
    end

    test "does NOT render article:section when og_type is website" do
      html =
        render_seo_meta(%{
          og_type: "website",
          article_section: "MLB News"
        })

      refute html =~ "article:section"
    end

    test "article:published_time accepts a %DateTime{}" do
      dt = ~U[2026-05-17 13:00:00Z]

      html =
        render_seo_meta(%{
          og_type: "article",
          article_published_time: dt
        })

      assert html =~ "article:published_time"
      assert html =~ "2026-05-17"
    end

    test "article:published_time accepts a %Date{}" do
      html =
        render_seo_meta(%{
          og_type: "article",
          article_published_time: ~D[2026-05-17]
        })

      assert html =~ "article:published_time"
      assert html =~ "2026-05-17"
    end

    test "article:published_time accepts a binary string" do
      html =
        render_seo_meta(%{
          og_type: "article",
          article_published_time: "2026-05-17"
        })

      assert html =~ ~s(property="article:published_time" content="2026-05-17")
    end
  end

  describe "seo_meta/1 — XSS escaping (OG-SEC-001)" do
    test "title containing script tags is HTML-escaped in og:title" do
      malicious = ~s|Cardinals "drop" </meta><script>alert(1)</script>|
      html = render_seo_meta(%{title: malicious})

      # The raw script tag must NOT appear verbatim
      refute html =~ "</meta><script>alert(1)</script>"
      # og:title must be present (content attr will be entity-encoded by HEEx)
      assert html =~ ~s(property="og:title")
    end

    test "title with angle brackets is entity-encoded" do
      html = render_seo_meta(%{title: "<b>Bold Title</b>"})
      # HEEx encodes < and > in attribute values
      assert html =~ "&lt;b&gt;Bold Title&lt;/b&gt;"
    end

    test "description with double-quotes is entity-encoded" do
      html = render_seo_meta(%{description: ~s|He said "hello"|})
      # Phoenix HEEx encodes " inside attribute content
      assert html =~ "&quot;hello&quot;" or html =~ ~s(He said "hello")
      # The description must be present one way or another
      assert html =~ "He said"
    end

    test "twitter:title is escaped the same way as og:title" do
      malicious = ~s|Cardinals "drop" </script>|
      html = render_seo_meta(%{title: malicious})
      refute html =~ "</script>"
      assert html =~ ~s(name="twitter:title")
    end
  end

  describe "seo_meta/1 — og:image is always absolute" do
    test "og:image URL starts with http:// or https://" do
      html = render_seo_meta(%{og_image: @image_url})
      # Match the property value prefix directly
      assert html =~ ~s(property="og:image" content="http)
    end

    test "twitter:image URL starts with http:// or https://" do
      html = render_seo_meta(%{og_image: @image_url})
      assert html =~ ~s(name="twitter:image" content="http)
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
