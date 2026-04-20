defmodule SportsFanaticWeb.TeamController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Team, Player, ScheduledGame}

  def index(conn, _params) do
    teams =
      from(t in Team,
        where: not is_nil(t.slug),
        order_by: [asc: t.division, asc: t.name]
      )
      |> Repo.all()

    conn
    |> assign(:page_title, "MLB Teams | Sports Fan Agent")
    |> assign(:meta_description, "All 30 MLB teams with rosters, schedules, and team statistics.")
    |> render(:index, teams: teams)
  end

  def show(conn, %{"team_slug" => team_slug}) do
    team = Repo.get_by!(Team, slug: team_slug)

    players =
      from(p in Player,
        where: p.team_id == ^team.id and p.status == "active",
        order_by: [asc: p.position, asc: p.last_name]
      )
      |> Repo.all()

    upcoming_games =
      from(sg in ScheduledGame,
        where:
          (sg.away_mlb_id == ^get_mlb_id(team) or sg.home_mlb_id == ^get_mlb_id(team)) and
            sg.game_date >= ^Date.utc_today(),
        order_by: sg.game_date,
        limit: 10
      )
      |> Repo.all()

    canonical = "https://sportsfanatic.com/mlb/teams/#{team_slug}"

    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "SportsTeam",
      "name" => team.name,
      "sport" => "Baseball",
      "memberOf" => %{
        "@type" => "SportsOrganization",
        "name" => "Major League Baseball"
      },
      "url" => canonical
    }

    conn
    |> assign(:page_title, "#{team.name} - Roster, Schedule & Stats | Sports Fan Agent")
    |> assign(:meta_description, "#{team.name} roster, upcoming schedule, team stats, and player analysis.")
    |> assign(:canonical, canonical)
    |> assign(:json_ld, json_ld)
    |> render(:show,
      team: team,
      players: players,
      upcoming_games: upcoming_games
    )
  end

  defp get_mlb_id(team) do
    case get_in(team.external_ids, ["mlb_id"]) do
      nil -> 0
      id -> if is_integer(id), do: id, else: String.to_integer(to_string(id))
    end
  end
end
