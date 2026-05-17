defmodule SportsFanaticWeb.PageController do
  use SportsFanaticWeb, :controller

  import Ecto.Query

  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.Mlb.{ScheduledGame, Team}
  alias SportsFanatic.Repo

  def health(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{status: "ok"})
  end

  def home(conn, _params) do
    today = SportsFanatic.DateHelper.today()

    games =
      ScheduledGame
      |> where([sg], sg.game_date == ^today)
      |> order_by([sg], sg.game_datetime)
      |> Repo.all()

    recent_news =
      NewsItem
      |> where([n], n.published_date == ^today)
      |> order_by([n], desc: n.inserted_at)
      |> limit(6)
      |> Repo.all()

    teams =
      Team
      |> order_by([t], [t.league, t.division, t.name])
      |> Repo.all()

    site_url = SportsFanaticWeb.SEO.site_url()

    # JSON-LD: identify the publishing Organization and the WebSite. We do NOT
    # emit a SearchAction (potentialAction) because /mlb/players does not yet
    # accept a `q=` search parameter — claiming sitelinks search support that
    # doesn't work would mislead Google.
    json_ld =
      Jason.encode!([
        %{
          "@context" => "https://schema.org",
          "@type" => "Organization",
          "name" => "Sports Fan Agent",
          "url" => site_url <> "/",
          "logo" => SportsFanaticWeb.SEO.absolute_image_url("/images/og-default.png"),
          "description" => SportsFanaticWeb.SEO.default_description()
        },
        %{
          "@context" => "https://schema.org",
          "@type" => "WebSite",
          "name" => "Sports Fan Agent",
          "url" => site_url <> "/"
        }
      ])

    conn
    |> assign(:page_title, SportsFanaticWeb.SEO.default_title())
    |> assign(:meta_description, SportsFanaticWeb.SEO.default_description())
    |> assign(:canonical_url, site_url <> "/")
    |> assign(:og_type, "website")
    |> assign(:json_ld, json_ld)
    |> render(:home, today: today, games: games, recent_news: recent_news, teams: teams)
  end
end
