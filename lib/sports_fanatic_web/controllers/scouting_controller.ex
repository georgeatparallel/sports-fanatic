defmodule SportsFanaticWeb.ScoutingController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.Content.ScoutingReport

  def show(conn, %{"team_slug" => team_slug, "player_slug" => player_slug}) do
    team = Repo.get_by!(Team, slug: team_slug)

    player =
      from(p in Player,
        where: p.team_id == ^team.id and p.slug == ^player_slug
      )
      |> Repo.one!()

    report =
      from(sr in ScoutingReport,
        where: sr.player_id == ^player.id,
        order_by: [desc: sr.report_date],
        limit: 1
      )
      |> Repo.one()

    canonical = "https://sportsfanatic.com/mlb/scouting/#{team_slug}/#{player_slug}"

    conn
    |> assign(:page_title, "#{player.full_name} Scouting Report | Sports Fan Agent")
    |> assign(
      :meta_description,
      "AI-powered scouting report for #{player.full_name} of the #{team.name}. Grade, strengths, weaknesses, and prediction analysis."
    )
    |> assign(:canonical, canonical)
    |> render(:show,
      player: player,
      team: team,
      report: report
    )
  end
end
