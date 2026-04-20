defmodule SportsFanatic.Workers.FetchLineupsWorker do
  @moduledoc "Fetches daily lineups from FantasyNerds every 30 minutes."

  use Oban.Worker,
    queue: :data_fetch,
    max_attempts: 3,
    unique: [period: 60]

  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.Lineup
  alias SportsFanatic.ExternalApis.FantasyNerds

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today() |> Date.to_iso8601()

    case FantasyNerds.fetch_lineups(today) do
      {:ok, players} ->
        Enum.each(players, fn player ->
          %Lineup{}
          |> Lineup.changeset(%{
            game_date: Date.utc_today(),
            player_nerds_id: player.player_id,
            team_code: player.team_code,
            batting_order: player[:batting_order],
            position: player[:position],
            confirmed: true
          })
          |> Repo.insert(
            on_conflict: {:replace, [:team_code, :batting_order, :position, :confirmed, :updated_at]},
            conflict_target: [:game_date, :player_nerds_id]
          )
        end)

        Logger.info("Fetched #{length(players)} lineup entries")

        # Trigger predictions after lineups confirmed
        if length(players) > 0 do
          %{date: today}
          |> SportsFanatic.Workers.GeneratePredictionsWorker.new()
          |> Oban.insert()
        end

        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch lineups: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
