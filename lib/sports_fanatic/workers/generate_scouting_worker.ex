defmodule SportsFanatic.Workers.GenerateScoutingWorker do
  @moduledoc "Generates scouting reports for players in today's lineups."

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 3,
    unique: [period: 3600]

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Lineup, Player}
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.PythonBridge

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()

    # Get players in today's lineups
    players =
      from(l in Lineup,
        join: p in Player,
        on: fragment("(? ->> 'nerds_id')::int = ?", p.external_ids, l.player_nerds_id),
        where: l.game_date == ^today,
        select: p
      )
      |> Repo.all()

    Logger.info("Generating scouting reports for #{length(players)} players")

    Enum.each(players, fn player ->
      # Check if report already exists for today
      existing =
        from(sr in ScoutingReport,
          where: sr.player_id == ^player.id and sr.report_date == ^today
        )
        |> Repo.one()

      if is_nil(existing) do
        generate_report(player, today)
      end
    end)

    :ok
  end

  defp generate_report(player, date) do
    start_ms = System.monotonic_time(:millisecond)

    # Search for player info
    case PythonBridge.search_player(player.full_name) do
      {:ok, %{"sources" => sources}} ->
        source_texts = Enum.map(sources, & &1["text"]) |> Enum.filter(& &1)

        case PythonBridge.generate_scouting(player.full_name, player.id, source_texts) do
          {:ok, %{"report" => report}} ->
            elapsed = System.monotonic_time(:millisecond) - start_ms

            %ScoutingReport{}
            |> ScoutingReport.changeset(%{
              player_id: player.id,
              report_date: date,
              summary: report["news_summary"] || "No summary available",
              overall_grade: assign_grade(report),
              full_report: report,
              hit_probability: report["hit_probability"],
              hr_probability: report["hr_probability"],
              strengths: report["positive_factors"] || [],
              weaknesses: report["negative_factors"] || [],
              injury_risk: report["injury_status"] || "healthy",
              injury_detail: report["injury_detail"],
              confidence_modifier: report["confidence_modifier"] || 0.0,
              sources_count: report["sources_count"] || length(sources),
              model_version: "claude-sonnet-4-20250514",
              generation_ms: elapsed
            })
            |> Repo.insert(
              on_conflict: :replace_all,
              conflict_target: [:player_id, :report_date]
            )

          {:error, reason} ->
            Logger.warning("Scouting generation failed for #{player.full_name}: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Player search failed for #{player.full_name}: #{inspect(reason)}")
    end
  end

  defp assign_grade(report) do
    sentiment = report["overall_sentiment"] || "neutral"
    modifier = report["confidence_modifier"] || 0.0

    cond do
      sentiment == "positive" and modifier > 0.05 -> "A+"
      sentiment == "positive" -> "A"
      sentiment == "neutral" and modifier > 0 -> "B+"
      sentiment == "neutral" -> "B"
      sentiment == "negative" and modifier < -0.05 -> "C"
      true -> "B-"
    end
  end
end
