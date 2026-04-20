defmodule SportsFanaticWeb.PageController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{ScheduledGame, Team}
  alias SportsFanatic.Content.NewsItem

  def home(conn, _params) do
    today = Date.utc_today()

    games =
      from(sg in ScheduledGame,
        where: sg.game_date == ^today,
        order_by: sg.game_datetime
      )
      |> Repo.all()

    recent_news =
      from(n in NewsItem,
        where: n.published_date >= ^Date.add(today, -3),
        order_by: [desc: n.published_date],
        limit: 10
      )
      |> Repo.all()

    teams = Repo.all(from t in Team, where: not is_nil(t.slug), order_by: t.name)

    conn
    |> assign(:page_title, "Sports Fanatic - MLB Stats, Scouting Reports & Game Day Analysis")
    |> assign(:meta_description, "Your source for MLB player stats, AI-powered scouting reports, Game Day Magazines, and daily lineup analysis.")
    |> render(:home,
      games: games,
      recent_news: recent_news,
      teams: teams,
      today: today
    )
  end
end
