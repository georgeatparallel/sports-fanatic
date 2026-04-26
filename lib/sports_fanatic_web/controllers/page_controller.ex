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
    today = Date.utc_today()

    games =
      ScheduledGame
      |> where([sg], sg.game_date == ^today)
      |> order_by([sg], sg.game_datetime)
      |> Repo.all()

    recent_news =
      NewsItem
      |> where([n], n.published_date >= ^Date.add(today, -3))
      |> order_by([n], desc: n.published_date)
      |> limit(10)
      |> Repo.all()

    teams = Repo.all(from t in Team, where: not is_nil(t.slug), order_by: t.name)

    conn
    |> assign(:page_title, "Sports Fan Agent - MLB Stats, Scouting Reports & Game Day Analysis")
    |> assign(
      :meta_description,
      "Your source for MLB player stats, AI-powered scouting reports, Game Day Magazines, and daily lineup analysis."
    )
    |> render(:home,
      games: games,
      recent_news: recent_news,
      teams: teams,
      today: today
    )
  end
end
