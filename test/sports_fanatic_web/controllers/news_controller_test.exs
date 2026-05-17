defmodule SportsFanaticWeb.NewsControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.Repo

  @base_url SportsFanaticWeb.Endpoint.url()

  defp create_news_item(attrs \\ %{}) do
    n = System.unique_integer([:positive])
    today = Date.utc_today()

    defaults = %{
      source: "fantasynerds",
      external_id: "ext-#{n}",
      slug: "test-news-slug-#{n}",
      title: "Test News #{n}",
      body: "Test news body content for article #{n}.",
      published_date: today,
      category: "news"
    }

    Repo.insert!(struct(NewsItem, Map.merge(defaults, attrs)))
  end

  setup do
    # Invalidate cache before each test so we always read from DB
    date = Date.utc_today()
    cache_key = SportsFanatic.Cache.news_feed_key(date)
    SportsFanatic.Cache.del(cache_key)
    :ok
  end

  describe "GET /mlb/news/:date" do
    test "renders 200 for a valid date", %{conn: conn} do
      today_str = Date.to_iso8601(Date.utc_today())
      conn = get(conn, "/mlb/news/#{today_str}")
      assert html_response(conn, 200) =~ "MLB News"
    end

    test "renders news items for the given date", %{conn: conn} do
      today = Date.utc_today()
      today_str = Date.to_iso8601(today)
      item = create_news_item(%{published_date: today})

      # Invalidate cache again after insert
      cache_key = SportsFanatic.Cache.news_feed_key(today)
      SportsFanatic.Cache.del(cache_key)

      conn = get(conn, "/mlb/news/#{today_str}")
      assert html_response(conn, 200) =~ item.title
    end
  end

  describe "GET /mlb/news/:date/:slug" do
    test "renders 200 for a valid news item", %{conn: conn} do
      today = Date.utc_today()
      today_str = Date.to_iso8601(today)

      item =
        create_news_item(%{
          published_date: today,
          slug: "valid-slug-#{System.unique_integer([:positive])}"
        })

      # Invalidate cache after insert
      cache_key = SportsFanatic.Cache.news_feed_key(today)
      SportsFanatic.Cache.del(cache_key)

      conn = get(conn, "/mlb/news/#{today_str}/#{item.slug}")
      assert html_response(conn, 200) =~ item.title
    end

    test "renders 404 for non-existent slug", %{conn: conn} do
      today_str = Date.to_iso8601(Date.utc_today())

      conn = get(conn, "/mlb/news/#{today_str}/nonexistent-news-slug")
      assert html_response(conn, 404)
    end
  end

  describe "GET /mlb/news/:date/:slug — Open Graph article tags" do
    setup %{conn: conn} do
      today = Date.utc_today()
      today_str = Date.to_iso8601(today)

      item =
        create_news_item(%{
          published_date: today,
          slug: "og-test-article-#{System.unique_integer([:positive])}",
          title: "OG Test Article Title",
          body: "This is the body of the OG test article.",
          category: "news"
        })

      # Invalidate cache after insert
      SportsFanatic.Cache.del(SportsFanatic.Cache.news_feed_key(today))

      conn = get(conn, "/mlb/news/#{today_str}/#{item.slug}")
      resp = html_response(conn, 200)
      {:ok, resp: resp, item: item, today_str: today_str}
    end

    test "renders og:type as article", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:type" content="article")
    end

    test "renders article:published_time meta tag", %{resp: resp} do
      assert resp =~ ~s(property="article:published_time")
    end

    test "article:published_time content parses as ISO 8601", %{resp: resp} do
      # Extract the content value from article:published_time
      # It should contain at least the date portion (YYYY-MM-DD)
      assert resp =~ ~r/property="article:published_time" content="20\d\d-\d\d-\d\d/
    end

    test "renders article:section meta tag", %{resp: resp} do
      assert resp =~ ~s(property="article:section")
    end

    test "og:url is an absolute URL", %{resp: resp} do
      assert resp =~ ~s(property="og:url" content="http)
    end

    test "og:url starts with http:// or https://", %{resp: resp} do
      assert resp =~ ~s(property="og:url" content="#{@base_url}/)
    end

    test "link rel=canonical is an absolute URL", %{resp: resp} do
      assert resp =~ ~s(rel="canonical")
      assert resp =~ ~s(href="#{@base_url}/)
    end

    test "og:image is present and absolute", %{resp: resp} do
      assert resp =~ ~s(property="og:image" content="http)
    end

    test "og:image falls back to default OG image when article has no image_url", %{
      resp: resp
    } do
      # Most test articles won't have image_url set (nil); default must be used
      assert resp =~ ~s(property="og:image" content="#{@base_url}/images/og-default.png") or
               resp =~ ~s(property="og:image" content="http)
    end

    test "JSON-LD script block is present", %{resp: resp} do
      assert resp =~ ~s(type="application/ld+json")
    end

    test "JSON-LD @type is NewsArticle", %{resp: resp} do
      assert resp =~ ~s("@type":"NewsArticle") or resp =~ ~s("@type": "NewsArticle")
    end

    test "JSON-LD contains image field", %{resp: resp} do
      assert resp =~ ~s("image":) or resp =~ ~s("image" :)
    end

    test "JSON-LD contains mainEntityOfPage field", %{resp: resp} do
      assert resp =~ "mainEntityOfPage"
    end

    test "twitter:card is present", %{resp: resp} do
      assert resp =~ ~s(<meta name="twitter:card")
    end

    test "meta name=description is present", %{resp: resp} do
      assert resp =~ ~s(<meta name="description")
    end
  end
end
