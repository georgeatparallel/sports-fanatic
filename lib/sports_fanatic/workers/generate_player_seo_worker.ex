defmodule SportsFanatic.Workers.GeneratePlayerSeoWorker do
  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 2,
    unique: [period: 3600]

  import Ecto.Query
  alias SportsFanatic.Cache
  alias SportsFanatic.Mlb.Player
  alias SportsFanatic.Repo
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    query =
      from(p in Player,
        where: p.status == "active" and (is_nil(p.bio) or p.bio == ""),
        preload: [:team]
      )

    players_without_bio = Repo.all(query)

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

  @position_names %{
    "P" => "pitcher",
    "C" => "catcher",
    "1B" => "first baseman",
    "2B" => "second baseman",
    "3B" => "third baseman",
    "SS" => "shortstop",
    "LF" => "left fielder",
    "CF" => "center fielder",
    "RF" => "right fielder",
    "OF" => "outfielder",
    "DH" => "designated hitter",
    "IF" => "infielder",
    "UT" => "utility player"
  }

  defp generate_basic_bio(player) do
    team_name = if player.team, do: player.team.name, else: "their team"
    position = expand_position(player.position)
    bats = if player.bats, do: " Bats #{String.downcase(player.bats)}.", else: ""
    throws = if player.throws, do: " Throws #{String.downcase(player.throws)}.", else: ""

    "#{player.full_name} is a #{position} for the #{team_name}.#{bats}#{throws}"
  end

  defp expand_position(nil), do: "player"
  defp expand_position(abbrev), do: Map.get(@position_names, abbrev, String.downcase(abbrev))
end
