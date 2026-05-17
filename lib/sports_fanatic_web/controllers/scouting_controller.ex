defmodule SportsFanaticWeb.ScoutingController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.Predictions
  alias SportsFanatic.Repo

  def show(conn, %{"team_slug" => team_slug, "player_slug" => player_slug}) do
    team = Repo.get_by!(Team, slug: team_slug)

    player =
      Player
      |> where([p], p.team_id == ^team.id and p.slug == ^player_slug)
      |> Repo.one!()

    report =
      ScoutingReport
      |> where([sr], sr.player_id == ^player.id)
      |> order_by([sr], desc: sr.report_date)
      |> limit(1)
      |> Repo.one()

    today = SportsFanatic.DateHelper.today()
    mlb_id = get_in(player.external_ids, ["mlb_id"])

    today_hit_prediction =
      if mlb_id do
        parsed_id = String.to_integer(to_string(mlb_id))
        Predictions.get_for_player(parsed_id, today)
      end

    canonical = SportsFanaticWeb.SEO.absolute_url("/mlb/scouting/#{team_slug}/#{player_slug}")

    conn
    |> assign(:page_title, "#{player.full_name} Scouting Report | Sports Fan Agent")
    |> assign(
      :meta_description,
      "AI-powered scouting report for #{player.full_name} of the #{team.name}. Grade, strengths, weaknesses, and prediction analysis."
    )
    |> assign(:canonical_url, canonical)
    |> assign(:og_type, "article")
    |> render(:show,
      player: player,
      team: team,
      report: report,
      today_hit_prediction: today_hit_prediction
    )
  end
end
