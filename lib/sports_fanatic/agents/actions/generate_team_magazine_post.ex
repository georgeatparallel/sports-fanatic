defmodule SportsFanatic.Agents.Actions.GenerateTeamMagazinePost do
  @moduledoc """
  Generates the daily team magazine tweet pair for the rotated team. Picks
  today's team via `SportsFanatic.X.TeamMagazine.rotation_team_for/1`, then
  ensures the magazine is generated (idempotent on team_id + run_date).
  """

  use SportsFanatic.Agents.Action,
    name: "generate_team_magazine_post",
    description: "Compose the daily team magazine X post (main + self-reply)"

  require Logger

  alias SportsFanatic.DateHelper
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.X.TeamMagazine

  @impl true
  def run(_params, _context) do
    today_et = DateHelper.today()

    with {:ok, %{slug: slug, team: team}} <- TeamMagazine.rotation_team_for(today_et),
         {:ok, %{magazine: magazine}} <- TeamMagazine.generate_or_fetch(slug) do
      link_url = "https://sportsfanatic.com/mlb/teams/#{slug}#magazine"

      context = %{
        team_magazine: %{
          team_name: team.name,
          team_slug: slug,
          state_of_team_excerpt: String.slice(magazine.state_of_the_team || "", 0, 240),
          todays_at_a_glance: magazine.today_at_a_glance || []
        }
      }

      case PythonBridge.draft_x_post("team_magazine", context, link_url) do
        {:ok, %{} = body} ->
          {:ok,
           %{
             main_body: Map.get(body, "main_body", ""),
             reply_body: Map.get(body, "reply_body", link_url),
             link_url: link_url,
             context: context,
             model: Map.get(body, "model"),
             input_tokens: Map.get(body, "input_tokens", 0),
             output_tokens: Map.get(body, "output_tokens", 0)
           }}

        {:error, reason} = err ->
          Logger.warning("GenerateTeamMagazinePost draft failed: #{inspect(reason)}")
          err
      end
    else
      {:error, reason} = err ->
        Logger.warning("GenerateTeamMagazinePost rotation/fetch failed: #{inspect(reason)}")
        err
    end
  end
end
