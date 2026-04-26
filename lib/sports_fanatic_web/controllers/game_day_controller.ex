defmodule SportsFanaticWeb.GameDayController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Content.GameDayMagazine
  alias SportsFanatic.Repo

  def show(conn, %{"date" => date_str, "slug" => slug}) do
    date = Date.from_iso8601!(date_str)

    magazine =
      GameDayMagazine
      |> where([m], m.game_date == ^date and m.slug == ^slug)
      |> preload([:away_team, :home_team])
      |> Repo.one!()

    canonical = "https://sportsfanatic.com/mlb/game-day/#{date_str}/#{slug}"

    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "SportsEvent",
      "name" => magazine.headline,
      "startDate" => Date.to_iso8601(date),
      "homeTeam" => %{"@type" => "SportsTeam", "name" => magazine.home_team.name},
      "awayTeam" => %{"@type" => "SportsTeam", "name" => magazine.away_team.name},
      "url" => canonical
    }

    conn
    |> assign(:page_title, "#{magazine.headline} | Game Day Magazine | Sports Fan Agent")
    |> assign(
      :meta_description,
      String.slice(
        "#{magazine.away_team.name} vs #{magazine.home_team.name} - Game preview, lineups, pitchers, and matchup analysis.",
        0,
        160
      )
    )
    |> assign(:canonical, canonical)
    |> assign(:json_ld, json_ld)
    |> render(:show,
      magazine: magazine,
      date: date,
      date_str: date_str
    )
  end
end
