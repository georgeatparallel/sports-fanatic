defmodule SportsFanatic.Workers.FetchLineupsWorker do
  @moduledoc "Fetches daily lineups from FantasyNerds every 30 minutes."

  use Oban.Worker,
    queue: :data_fetch,
    max_attempts: 3,
    unique: [period: 60]

  import Ecto.Query

  alias SportsFanatic.ExternalApis.FantasyNerds
  alias SportsFanatic.Mlb.{Lineup, Player}
  alias SportsFanatic.Predictions.Progress
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    date = parse_date(args["date"]) || SportsFanatic.DateHelper.today()
    run_id = parse_run_id(args["pipeline_run_id"])
    fetch_for_date(date, run_id)
  end

  @spec fetch_for_date(Date.t(), binary() | nil) :: {:ok, integer} | {:error, term}
  def fetch_for_date(date, run_id \\ nil)

  def fetch_for_date(%Date{} = date, run_id) do
    Progress.step_started(run_id, :fetch_lineups, total: 1)

    case FantasyNerds.fetch_lineups(Date.to_iso8601(date)) do
      {:ok, players} ->
        players_by_name = resolve_players_by_name(players)

        Enum.each(players, fn player ->
          name = player[:player_name]
          player_id = find_player_id(name, player.team_code, players_by_name)

          %Lineup{}
          |> Lineup.changeset(%{
            game_date: date,
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

        Logger.info("Fetched #{length(players)} lineup entries for #{date}")

        Progress.step_completed(run_id, :fetch_lineups,
          processed: length(players),
          total: length(players)
        )

        # NOTE: hit-prediction chaining lives in DailyHitPredictionsWorker.
        {:ok, length(players)}

      {:error, reason} = err ->
        Logger.error("Failed to fetch lineups: #{inspect(reason)}")

        Progress.step_failed(run_id, :fetch_lineups, reason,
          current_item: "FantasyNerds lineups #{Date.to_iso8601(date)}",
          endpoint: "FantasyNerds /lineups",
          http_status: extract_http_status(reason)
        )

        err
    end
  rescue
    e ->
      Progress.step_failed(run_id, :fetch_lineups, e,
        current_item: "FantasyNerds lineups #{Date.to_iso8601(date)}",
        endpoint: "FantasyNerds /lineups"
      )

      reraise e, __STACKTRACE__
  end

  defp extract_http_status({:http_error, s}) when is_integer(s), do: s
  defp extract_http_status({_, %{status: s}}) when is_integer(s), do: s
  defp extract_http_status(_), do: nil

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_run_id(nil), do: nil
  defp parse_run_id(s) when is_binary(s), do: s

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
