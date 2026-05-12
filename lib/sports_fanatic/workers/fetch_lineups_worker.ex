defmodule SportsFanatic.Workers.FetchLineupsWorker do
  @moduledoc "Fetches daily lineups from FantasyNerds every 30 minutes."

  use Oban.Worker,
    queue: :data_fetch,
    max_attempts: 3,
    unique: [period: 60]

  import Ecto.Query

  alias SportsFanatic.ExternalApis.FantasyNerds
  alias SportsFanatic.Mlb.{Lineup, Player}
  alias SportsFanatic.Repo
  alias SportsFanatic.Workers.GeneratePredictionsWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = SportsFanatic.DateHelper.today() |> Date.to_iso8601()

    case FantasyNerds.fetch_lineups(today) do
      {:ok, players} ->
        # Build name-based lookup: {lowercase_full_name, team_code} => player_id
        players_by_name = resolve_players_by_name(players)

        Enum.each(players, fn player ->
          name = player[:player_name]
          player_id = find_player_id(name, player.team_code, players_by_name)

          %Lineup{}
          |> Lineup.changeset(%{
            game_date: SportsFanatic.DateHelper.today(),
            player_nerds_id: player.player_id,
            player_name: name,
            team_code: player.team_code,
            batting_order: player[:batting_order],
            position: player[:position],
            confirmed: true,
            player_id: player_id
          })
          |> Repo.insert(
            on_conflict:
              {:replace,
               [
                 :team_code,
                 :batting_order,
                 :position,
                 :confirmed,
                 :player_id,
                 :player_name,
                 :updated_at
               ]},
            conflict_target: [:game_date, :player_nerds_id]
          )
        end)

        Logger.info("Fetched #{length(players)} lineup entries")

        # Trigger predictions after lineups confirmed
        if length(players) > 0 do
          %{date: today}
          |> GeneratePredictionsWorker.new()
          |> Oban.insert()
        end

        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch lineups: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # FantasyNerds uses different abbreviations than our DB for some teams
  @team_code_map %{"LA" => "LAD", "ANA" => "LAA", "ARI" => "AZ"}

  defp normalize_team_code(code), do: Map.get(@team_code_map, code, code)

  defp resolve_players_by_name(players) do
    team_codes =
      players
      |> Enum.map(&normalize_team_code(&1.team_code))
      |> Enum.uniq()

    Player
    |> join(:inner, [p], t in assoc(p, :team))
    |> where([p, t], t.abbreviation in ^team_codes)
    |> select([p, t], {p.full_name, t.abbreviation, p.id})
    |> Repo.all()
    |> Map.new(fn {name, abbr, id} -> {{normalize_name(name), abbr}, id} end)
  end

  defp find_player_id(nil, _team_code, _lookup), do: nil

  defp find_player_id(name, team_code, lookup) do
    Map.get(lookup, {normalize_name(name), normalize_team_code(team_code)})
  end

  defp normalize_name(name) do
    name
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036f}]/u, "")
    |> String.replace(".", "")
  end
end
