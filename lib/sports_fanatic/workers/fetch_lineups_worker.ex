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
    today = Date.utc_today() |> Date.to_iso8601()

    case FantasyNerds.fetch_lineups(today) do
      {:ok, players} ->
        # Batch-resolve FantasyNerds player IDs to internal Player UUIDs
        nerds_ids =
          players
          |> Enum.map(& &1.player_id)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        players_by_nerds_id = resolve_players_by_nerds_id(nerds_ids)

        Enum.each(players, fn player ->
          player_id = Map.get(players_by_nerds_id, player.player_id)

          %Lineup{}
          |> Lineup.changeset(%{
            game_date: Date.utc_today(),
            player_nerds_id: player.player_id,
            team_code: player.team_code,
            batting_order: player[:batting_order],
            position: player[:position],
            confirmed: true,
            player_id: player_id
          })
          |> Repo.insert(
            on_conflict:
              {:replace,
               [:team_code, :batting_order, :position, :confirmed, :player_id, :updated_at]},
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

  defp resolve_players_by_nerds_id([]), do: %{}

  defp resolve_players_by_nerds_id(nerds_ids) do
    Player
    |> where([p], fragment("(? ->> 'nerds_id')::int = ANY(?)", p.external_ids, ^nerds_ids))
    |> select([p], {fragment("(? ->> 'nerds_id')::int", p.external_ids), p.id})
    |> Repo.all()
    |> Map.new()
  end
end
