defmodule SportsFanatic.Workers.GeneratePlayerSeoWorker do
  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 2,
    unique: [period: 3600]

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.Player
  alias SportsFanatic.Cache
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    players_without_bio =
      from(p in Player,
        where: p.status == "active" and (is_nil(p.bio) or p.bio == ""),
        preload: [:team]
      )
      |> Repo.all()

    Enum.each(players_without_bio, fn player ->
      bio = generate_basic_bio(player)
      player
      |> Ecto.Changeset.change(%{bio: bio})
      |> Repo.update()
    end)

    Cache.del_pattern("sf:page:player:*")

    Logger.info("Generated SEO content for #{length(players_without_bio)} players")
    :ok
  end

  defp generate_basic_bio(player) do
    team_name = if player.team, do: player.team.name, else: "their team"
    position = player.position || "player"
    bats = if player.bats, do: " Bats #{String.downcase(player.bats)}.", else: ""
    throws = if player.throws, do: " Throws #{String.downcase(player.throws)}.", else: ""

    "#{player.full_name} is a #{String.downcase(position)} for the #{team_name}.#{bats}#{throws}"
  end
end
