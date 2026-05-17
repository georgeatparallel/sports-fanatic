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
      canonical = SportsFanaticWeb.SEO.absolute_url("/mlb/news/#{date_str}/#{slug}")

      # Article image: fall back to site default when missing. Helper rejects
      # http:// URLs (mixed-content) and passes https:// through unchanged.
      og_image = SportsFanaticWeb.SEO.absolute_image_url(news_item["image_url"])

      description =
        (news_item["ai_summary"] || news_item["summary"] || news_item["body"] || "")
        |> String.slice(0, 160)

      article_section =
        case news_item["category"] do
          nil ->
            "MLB News"

          cat ->
            cat |> to_string() |> String.replace("_", " ") |> String.capitalize()
        end

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
          "url" => canonical,
          "image" => og_image,
          "mainEntityOfPage" => canonical
        })

      conn
      |> assign(:page_title, "#{news_item["title"]} | Sports Fan Agent")
      |> assign(:meta_description, description)
      |> assign(:canonical_url, canonical)
      |> assign(:og_type, "article")
      |> assign(:og_image, og_image)
      |> assign(:article_published_time, news_item["published_date"])
      |> assign(:article_section, article_section)
      |> assign(:json_ld, json_ld)
      |> render(:show,
        news_item: news_item,
        date: date,
        date_str: date_str
      )
    end
  end
end
