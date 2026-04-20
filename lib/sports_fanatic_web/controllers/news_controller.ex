defmodule SportsFanaticWeb.NewsController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Content.NewsItem

  def index(conn, %{"date" => date_str}) do
    date = Date.from_iso8601!(date_str)

    news =
      from(n in NewsItem,
        where: n.published_date == ^date,
        order_by: [desc: n.inserted_at]
      )
      |> Repo.all()

    canonical = "https://sportsfanatic.com/mlb/news/#{date_str}"

    conn
    |> assign(:page_title, "MLB News for #{format_date(date)} | Sports Fan Agent")
    |> assign(:meta_description, "Latest MLB news and player updates for #{format_date(date)}.")
    |> assign(:canonical, canonical)
    |> render(:index,
      date: date,
      date_str: date_str,
      news: news
    )
  end

  def show(conn, %{"date" => date_str, "slug" => slug}) do
    date = Date.from_iso8601!(date_str)

    news_item =
      from(n in NewsItem,
        where: n.published_date == ^date and n.slug == ^slug
      )
      |> Repo.one!()

    canonical = "https://sportsfanatic.com/mlb/news/#{date_str}/#{slug}"

    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "NewsArticle",
      "headline" => news_item.title,
      "datePublished" => Date.to_iso8601(news_item.published_date),
      "publisher" => %{
        "@type" => "Organization",
        "name" => "Sports Fan Agent"
      },
      "url" => canonical
    }

    conn
    |> assign(:page_title, "#{news_item.title} | Sports Fan Agent")
    |> assign(:meta_description, String.slice(news_item.summary || news_item.body, 0, 160))
    |> assign(:canonical, canonical)
    |> assign(:json_ld, json_ld)
    |> render(:show,
      news_item: news_item,
      date: date,
      date_str: date_str
    )
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end
