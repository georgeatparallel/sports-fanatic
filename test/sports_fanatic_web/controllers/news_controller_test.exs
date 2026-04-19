defmodule SportsFanaticWeb.NewsControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Repo
  alias SportsFanatic.Content.NewsItem

  defp create_news_item(attrs \\ %{}) do
    n = System.unique_integer([:positive])
    today = Date.utc_today()

    defaults = %{
      source: "fantasynerds",
      external_id: "ext-#{n}",
      slug: "test-news-slug-#{n}",
      title: "Test News #{n}",
      body: "Test news body content for article #{n}.",
      published_date: today
    }

    Repo.insert!(struct(NewsItem, Map.merge(defaults, attrs)))
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

      conn = get(conn, "/mlb/news/#{today_str}")
      assert html_response(conn, 200) =~ item.title
    end
  end

  describe "GET /mlb/news/:date/:slug" do
    test "renders 200 for a valid news item", %{conn: conn} do
      today = Date.utc_today()
      today_str = Date.to_iso8601(today)
      item = create_news_item(%{published_date: today, slug: "valid-slug-#{System.unique_integer([:positive])}"})

      conn = get(conn, "/mlb/news/#{today_str}/#{item.slug}")
      assert html_response(conn, 200) =~ item.title
    end

    test "renders 404 for non-existent slug", %{conn: conn} do
      today_str = Date.to_iso8601(Date.utc_today())

      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/news/#{today_str}/nonexistent-news-slug")
      end
    end
  end
end
