defmodule SportsFanatic.Workers.WarmCacheWorker do
  @moduledoc "Pre-renders and caches top pages after content generation."

  use Oban.Worker,
    queue: :cache,
    max_attempts: 2,
    unique: [period: 120]

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Team, Player}
  alias SportsFanatic.Cache

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    # Warm team pages
    teams = Repo.all(from t in Team, where: not is_nil(t.slug))

    Enum.each(teams, fn team ->
      Cache.del(Cache.team_page_key(team.slug))
    end)

    # Warm top player pages
    players =
      from(p in Player,
        where: p.status == "active" and not is_nil(p.slug),
        join: t in Team,
        on: p.team_id == t.id,
        select: {p, t},
        limit: 200
      )
      |> Repo.all()

    Enum.each(players, fn {player, team} ->
      if team.slug do
        Cache.del(Cache.player_page_key(team.slug, player.slug))
      end
    end)

    # Warm today's lineup page
    today = Date.utc_today() |> Date.to_iso8601()
    Cache.del(Cache.lineup_page_key(today))

    Logger.info("Cache warmed for #{length(teams)} teams, #{length(players)} players")
    :ok
  end
end
