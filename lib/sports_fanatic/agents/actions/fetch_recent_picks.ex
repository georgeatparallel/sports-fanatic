defmodule SportsFanatic.Agents.Actions.FetchRecentPicks do
  @moduledoc """
  Tool action: last 7 days of hit picks ordered by confidence. Used by
  `XReplyAgent` for "who's hot" inbound questions.
  """

  use SportsFanatic.Agents.Action,
    name: "fetch_recent_picks",
    description: "Return the last 7 days of hit picks, top-confidence first"

  import Ecto.Query

  alias SportsFanatic.Mlb.Pick
  alias SportsFanatic.Repo

  @impl true
  def run(_params, _ctx) do
    cutoff = Date.add(Date.utc_today(), -7)

    picks =
      Repo.all(
        from p in Pick,
          where: p.prediction_date >= ^cutoff,
          where: p.prediction == "hit",
          order_by: [desc: p.confidence],
          limit: 20,
          select: %{
            date: p.prediction_date,
            player_name: p.player_name,
            team: p.player_team,
            confidence: p.confidence,
            actual_result: p.actual_result
          }
      )

    {:ok, %{count: length(picks), picks: picks}}
  end
end
