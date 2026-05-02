defmodule SportsFanaticWeb.NewsControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.Repo

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
    SportsFanatic.Cache.delete(cache_key)
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
      SportsFanatic.Cache.delete(cache_key)

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
      SportsFanatic.Cache.delete(cache_key)

      conn = get(conn, "/mlb/news/#{today_str}/#{item.slug}")
      assert html_response(conn, 200) =~ item.title
    end

    test "renders 404 for non-existent slug", %{conn: conn} do
      today_str = Date.to_iso8601(Date.utc_today())

      conn = get(conn, "/mlb/news/#{today_str}/nonexistent-news-slug")
      assert html_response(conn, 404)
    end
  end
end
