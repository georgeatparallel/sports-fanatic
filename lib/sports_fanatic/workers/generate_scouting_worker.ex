defmodule SportsFanatic.Workers.GenerateScoutingWorker do
  @moduledoc "Generates scouting reports for players in today's lineups."

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 3,
    unique: [period: 3600]

  import Ecto.Query
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Mlb.{Lineup, Player}
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = SportsFanatic.DateHelper.today()

    # Get players in today's lineups
    players =
      Lineup
      |> join(:inner, [l], p in Player,
        on: fragment("(? ->> 'nerds_id')::int = ?", p.external_ids, l.player_nerds_id)
      )
      |> where([l], l.game_date == ^today)
      |> select([l, p], p)
      |> Repo.all()

    Logger.info("Generating scouting reports for #{length(players)} players")

    Enum.each(players, fn player ->
      # Check if report already exists for today
      existing =
        ScoutingReport
        |> where([sr], sr.player_id == ^player.id and sr.report_date == ^today)
        |> Repo.one()

      if is_nil(existing) do
        generate_report(player, today)
      end
    end)

    # Debounced page-cache invalidation: one pattern delete per perform/1,
    # rather than per insert. Per-card keys were already invalidated inside
    # save_scouting_report/5.
    invalidate_all_players_pages()

    :ok
  end

  defp generate_report(player, date) do
    start_ms = System.monotonic_time(:millisecond)

    with {:ok, %{"sources" => sources}} <- PythonBridge.search_player(player.full_name),
         source_texts <- sources |> Enum.map(& &1["text"]) |> Enum.filter(& &1),
         {:ok, %{"report" => report}} <-
           PythonBridge.generate_scouting(player.full_name, player.id, source_texts) do
      elapsed = System.monotonic_time(:millisecond) - start_ms
      save_scouting_report(player, date, report, sources, elapsed)
    else
      {:error, reason} ->
        Logger.warning("Scouting failed for #{player.full_name}: #{inspect(reason)}")
    end
  end

  defp save_scouting_report(player, date, report, sources, elapsed) do
    result =
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

    case result do
      {:ok, _report} ->
        invalidate_player_card(player)
        result

      _ ->
        result
    end
  end

  defp assign_grade(report) do
    sentiment = report["overall_sentiment"] || "neutral"
    modifier = report["confidence_modifier"] || 0.0
    grade_for_sentiment(sentiment, modifier)
  end

  defp grade_for_sentiment("positive", modifier) when modifier > 0.05, do: "A+"
  defp grade_for_sentiment("positive", _modifier), do: "A"
  defp grade_for_sentiment("neutral", modifier) when modifier > 0, do: "B+"
  defp grade_for_sentiment("neutral", _modifier), do: "B"
  defp grade_for_sentiment("negative", modifier) when modifier < -0.05, do: "C"
  defp grade_for_sentiment(_sentiment, _modifier), do: "B-"

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
