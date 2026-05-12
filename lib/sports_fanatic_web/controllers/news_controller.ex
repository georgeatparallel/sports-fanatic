defmodule SportsFanaticWeb.NewsController do
  use SportsFanaticWeb, :controller

  alias SportsFanatic.News

  def today(conn, _params) do
    date = News.latest_news_date()
    date_str = Date.to_iso8601(date)

    {:ok, feed} = News.get_cached_feed(date)

    today = SportsFanatic.DateHelper.today()
    prev_date = News.nearest_news_date_before(date)
    next_date = News.nearest_news_date_after(date)
    next_date = if next_date && Date.compare(next_date, today) == :gt, do: nil, else: next_date

    canonical = "https://sportsfanatic.com/mlb/news/#{date_str}"
    formatted_date = Calendar.strftime(date, "%B %d, %Y")

    json_ld =
      Jason.encode!(%{
        "@context" => "https://schema.org",
        "@type" => "CollectionPage",
        "name" => "MLB News for #{formatted_date}",
        "url" => canonical,
        "publisher" => %{
          "@type" => "Organization",
          "name" => "Sports Fan Agent"
        }
      })

    conn
    |> assign(:page_title, "MLB News for #{formatted_date} | Sports Fan Agent")
    |> assign(
      :meta_description,
      "Latest MLB news, injuries, trades, and player updates for #{formatted_date}."
    )
    |> assign(:canonical_url, canonical)
    |> assign(:json_ld, json_ld)
    |> render(:index,
      date: date,
      date_str: date_str,
      feed: feed,
      prev_date: prev_date,
      next_date: next_date
    )
  end

  def index(conn, %{"date" => date_str}) do
    date = Date.from_iso8601!(date_str)

    {:ok, feed} = News.get_cached_feed(date)

    today = SportsFanatic.DateHelper.today()
    prev_date = News.nearest_news_date_before(date)
    next_date = News.nearest_news_date_after(date)
    next_date = if next_date && Date.compare(next_date, today) == :gt, do: nil, else: next_date

    canonical = "https://sportsfanatic.com/mlb/news/#{date_str}"
    formatted_date = Calendar.strftime(date, "%B %d, %Y")

    json_ld =
      Jason.encode!(%{
        "@context" => "https://schema.org",
        "@type" => "CollectionPage",
        "name" => "MLB News for #{formatted_date}",
        "url" => canonical,
        "publisher" => %{
          "@type" => "Organization",
          "name" => "Sports Fan Agent"
        }
      })

    conn
    |> assign(:page_title, "MLB News for #{formatted_date} | Sports Fan Agent")
    |> assign(
      :meta_description,
      "Latest MLB news, injuries, trades, and player updates for #{formatted_date}."
    )
    |> assign(:canonical_url, canonical)
    |> assign(:json_ld, json_ld)
    |> render(:index,
      date: date,
      date_str: date_str,
      feed: feed,
      prev_date: prev_date,
      next_date: next_date
    )
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
