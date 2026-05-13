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

    json_ld =
      Jason.encode!(%{
        "@context" => "https://schema.org",
        "@type" => "WebSite",
        "name" => "Sports Fan Agent",
        "url" => "https://sportsfanatic.com/"
      })

    conn
    |> assign(:page_title, "Sports Fan Agent - AI-Powered MLB Intelligence")
    |> assign(
      :meta_description,
      "AI-powered MLB scouting reports, Game Day Magazines, and predictions for every player and matchup."
    )
    |> assign(:canonical_url, "https://sportsfanatic.com/")
    |> assign(:json_ld, json_ld)
    |> render(:home, today: today, games: games, recent_news: recent_news, teams: teams)
  end
end
