defmodule SportsFanatic.Workers.GenerateScoutingOnDemandWorker do
  @moduledoc """
  On-demand scouting report generation triggered when a user views a player
  page without a fresh report. Uses Oban's unique constraint to ensure only
  one report is generated per player per day, even if multiple users request
  it simultaneously.
  """

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 2,
    unique: [
      period: 300,
      fields: [:args],
      keys: [:player_id],
      states: [:available, :scheduled, :executing]
    ]

  import Ecto.Query

  alias SportsFanatic.AI.Claude
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Mlb.Player
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"player_id" => player_id}}) do
    today = SportsFanatic.DateHelper.today()

    # Double-check — another job may have completed while we were queued
    existing =
      ScoutingReport
      |> where([sr], sr.player_id == ^player_id and sr.report_date == ^today)
      |> Repo.exists?()

    if existing do
      Logger.info("ScoutingOnDemand: report already exists for #{player_id} today")
      :ok
    else
      case Repo.get(Player, player_id) do
        nil ->
          Logger.warning("ScoutingOnDemand: player #{player_id} not found")
          :ok

        player ->
          generate_report(player, today)
      end
    end
  end

  defp generate_report(player, today) do
    Logger.info("ScoutingOnDemand: generating report for #{player.full_name}")

    case Claude.search_player_sources(player.full_name) do
      {:ok, sources} when sources != [] ->
        sources_text =
          Enum.map_join(sources, "\n\n---\n\n", fn s -> "#{s.title}\n#{s.text}" end)

        case Claude.generate_scouting(player.full_name, sources_text) do
          {:ok, report} when is_map(report) ->
            attrs = %{
              player_id: player.id,
              report_date: today,
              summary: report["news_summary"] || "Scouting report for #{player.full_name}",
              full_report: report,
              overall_grade: sentiment_to_grade(report["overall_sentiment"]),
              hit_probability: report["hit_probability"],
              hr_probability: report["hr_probability"],
              strengths: report["positive_factors"] || [],
              weaknesses: report["negative_factors"] || [],
              injury_risk: report["injury_status"] || "unknown",
              injury_detail: report["injury_detail"],
              confidence_modifier: report["confidence_modifier"],
              sources_count: length(sources)
            }

            case %ScoutingReport{}
                 |> ScoutingReport.changeset(attrs)
                 |> Repo.insert(on_conflict: :nothing) do
              {:ok, _} ->
                Logger.info("ScoutingOnDemand: report generated for #{player.full_name}")
                invalidate_player_card(player)
                invalidate_all_players_pages()
                :ok

              {:error, changeset} ->
                Logger.error(
                  "ScoutingOnDemand: insert failed for #{player.full_name}: #{inspect(changeset.errors)}"
                )

                {:error, :insert_failed}
            end

          {:error, reason} ->
            Logger.warning(
              "ScoutingOnDemand: generation failed for #{player.full_name}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      _ ->
        Logger.warning("ScoutingOnDemand: no sources found for #{player.full_name}, will retry")
        {:error, :no_sources}
    end
  end

  defp sentiment_to_grade("positive"), do: "A"
  defp sentiment_to_grade("neutral"), do: "B"
  defp sentiment_to_grade("negative"), do: "C"
  defp sentiment_to_grade(_), do: "B"

  defp invalidate_player_card(player) do
    id = card_cache_id(player)
    SportsFanatic.Cache.del(SportsFanatic.Cache.player_card_key(id))
  rescue
    _ -> :ok
  end

  defp invalidate_all_players_pages do
    SportsFanatic.Cache.del_pattern("sf:page:players:*")
  rescue
    _ -> :ok
  end

  defp card_cache_id(%{external_ids: %{} = ext, id: id}) do
    case Map.get(ext, "mlb_id") || Map.get(ext, :mlb_id) do
      v when is_integer(v) -> v
      v when is_binary(v) and v != "" -> v
      _ -> id
    end
  end

  defp card_cache_id(%{id: id}), do: id
end
