defmodule SportsFanatic.Workers.FetchScheduleWorker do
  @moduledoc "Fetches daily MLB schedule. Runs at 6 AM ET daily."

  use Oban.Worker,
    queue: :data_fetch,
    max_attempts: 3,
    unique: [period: 3600]

  alias SportsFanatic.Mlb.ScheduledGame
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today() |> Date.to_iso8601()

    # The Python bridge wraps MLB Stats API for schedule data
    case PythonBridge.fetch_schedule(today) do
      {:ok, %{"games" => games}} ->
        Enum.each(games, fn game ->
          %ScheduledGame{}
          |> ScheduledGame.changeset(%{
            game_id: game["game_id"],
            game_date: Date.from_iso8601!(game["game_date"]),
            game_datetime: parse_datetime(game["game_datetime"]),
            away_mlb_id: game["away_mlb_id"],
            home_mlb_id: game["home_mlb_id"],
            away_name: game["away_name"],
            home_name: game["home_name"],
            away_probable_pitcher: game["away_probable_pitcher"],
            home_probable_pitcher: game["home_probable_pitcher"],
            venue_id: game["venue_id"],
            venue_name: game["venue_name"]
          })
          |> Repo.insert(
            on_conflict: :replace_all,
            conflict_target: :game_id
          )
        end)

        Logger.info("Fetched #{length(games)} scheduled games")
        :ok

      {:error, reason} ->
        Logger.warning("Schedule fetch failed: #{inspect(reason)}, will retry")
        {:error, reason}
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
