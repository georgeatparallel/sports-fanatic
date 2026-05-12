defmodule SportsFanaticWeb.NewsController do
  use SportsFanaticWeb, :controller

  alias SportsFanatic.News

  def redirect_today(conn, _params) do
    today = SportsFanatic.DateHelper.today()
    redirect(conn, to: "/mlb/news/#{Date.to_iso8601(today)}")
  end

  def show(conn, %{"date" => date_str, "slug" => slug}) do
    date = Date.from_iso8601!(date_str)

    {:ok, feed} = News.get_cached_feed(date)

    news_item = Enum.find(feed, fn item -> item["slug"] == slug end)

    if is_nil(news_item) do
      conn
      |> put_status(:not_found)
      |> put_view(SportsFanaticWeb.ErrorHTML)
      |> render(:"404")
    else
      canonical = "https://sportsfanatic.com/mlb/news/#{date_str}/#{slug}"

      json_ld =
        Jason.encode!(%{
          "@context" => "https://schema.org",
          "@type" => "NewsArticle",
          "headline" => news_item["title"],
          "datePublished" => news_item["published_date"],
          "publisher" => %{
            "@type" => "Organization",
            "name" => "Sports Fan Agent"
          },
          "url" => canonical
        })

      description =
        (news_item["ai_summary"] || news_item["summary"] || news_item["body"] || "")
        |> String.slice(0, 160)

      conn
      |> assign(:page_title, "#{news_item["title"]} | Sports Fan Agent")
      |> assign(:meta_description, description)
      |> assign(:canonical_url, canonical)
      |> assign(:json_ld, json_ld)
      |> render(:show,
        news_item: news_item,
        date: date,
        date_str: date_str
      )
    end
  end
end
