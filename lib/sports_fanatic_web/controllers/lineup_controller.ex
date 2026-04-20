defmodule SportsFanaticWeb.LineupController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{ScheduledGame, Lineup}

  def show(conn, %{"date" => date_str}) do
    date = Date.from_iso8601!(date_str)

    games =
      from(sg in ScheduledGame,
        where: sg.game_date == ^date,
        order_by: sg.game_datetime
      )
      |> Repo.all()

    lineups =
      from(l in Lineup,
        where: l.game_date == ^date,
        order_by: [asc: l.team_code, asc: l.batting_order]
      )
      |> Repo.all()

    canonical = "https://sportsfanatic.com/mlb/lineups/#{date_str}"

    conn
    |> assign(:page_title, "MLB Lineups for #{format_date(date)} | Sports Fan Agent")
    |> assign(:meta_description, "Confirmed MLB lineups for #{format_date(date)}. Starting lineups, batting orders, and probable pitchers for all games.")
    |> assign(:canonical, canonical)
    |> render(:show,
      date: date,
      date_str: date_str,
      games: games,
      lineups: lineups
    )
  end

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end
