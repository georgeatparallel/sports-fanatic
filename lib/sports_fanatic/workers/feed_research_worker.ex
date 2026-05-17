defmodule SportsFanatic.Workers.FeedResearchWorker do
  @moduledoc """
  Oban worker that researches news for all active user feeds.

  Runs daily (default 9:00 AM ET / 13:00 UTC). For each feed, searches
  local news and Exa for each player, with a 2-second delay between
  Exa calls to avoid rate limiting. Caps at 50 players per feed.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  alias SportsFanatic.Agents.Actions.{SearchExa, SearchLocalNews}
  alias SportsFanatic.AI.Claude
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Feeds
  alias SportsFanatic.Mlb.Player
  alias SportsFanatic.Repo

  import Ecto.Query

  require Logger

  @max_players_per_feed 50
  @exa_delay_ms 2_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    feeds =
      case Map.get(args, "feed_ids") do
        nil -> Feeds.list_all_active_feeds()
        ids when is_list(ids) -> Feeds.get_feeds(ids)
        _ -> Feeds.list_all_active_feeds()
      end

    # Deduplicate players across all feeds — if a player appears in 3 feeds,
    # research them only once
    all_player_ids =
      feeds
      |> Enum.flat_map(& &1.player_ids)
      |> Enum.uniq()
      |> Enum.take(@max_players_per_feed)

    Logger.info("FeedResearchWorker: researching #{length(all_player_ids)} unique players across #{length(feeds)} feeds")

    for player_id <- all_player_ids do
      case Repo.get(Player, player_id) do
        nil ->
          Logger.warning("FeedResearchWorker: player #{player_id} not found")

        player ->
          research_player(player)
      end
    end

    # Mark all feeds as researched
    now = DateTime.utc_now()
    for feed <- feeds do
      Feeds.update_feed(feed, %{last_researched_at: now})
    end

    :ok
  end

  defp research_player(player) do
    # Search local news
    SearchLocalNews.run(%{query: player.full_name, limit: 10}, %{})

    # Rate-limited Exa search
    Process.sleep(@exa_delay_ms)

    SearchExa.run(
      %{query: "#{player.full_name} MLB 2026", num_results: 10, days_back: 7},
      %{}
    )

    # Generate scouting report if we don't have one today
    maybe_generate_scouting(player)
  rescue
    e ->
      Logger.error(
        "FeedResearchWorker: error researching player #{player.full_name}: #{Exception.message(e)}"
      )
  end

  defp maybe_generate_scouting(player) do
    today = SportsFanatic.DateHelper.today()

    has_report_today =
      from(sr in ScoutingReport,
        where: sr.player_id == ^player.id and sr.report_date == ^today
      )
      |> Repo.exists?()

    unless has_report_today do
      Logger.info("FeedResearchWorker: generating scouting report for #{player.full_name}")

      # Search for source material via Exa (direct Elixir, parallel)
      case Claude.search_player_sources(player.full_name) do
        {:ok, sources} when sources != [] ->
          sources_text = Enum.map_join(sources, "\n\n---\n\n", fn s ->
            "#{s.title}\n#{s.text}"
          end)

          # Generate report via direct Claude call (no Python Bridge)
          case Claude.generate_scouting(player.full_name, sources_text) do
            {:ok, report} when is_map(report) ->
              %ScoutingReport{}
              |> ScoutingReport.changeset(%{
                player_id: player.id,
                report_date: today,
                summary: report["news_summary"] || "Scouting report for #{player.full_name}",
                full_report: report,
                overall_grade: report["overall_sentiment"] || "neutral",
                strengths: report["positive_factors"] || [],
                weaknesses: report["negative_factors"] || [],
                injury_risk: report["injury_status"] || "unknown",
                injury_detail: report["injury_detail"],
                sources_count: length(sources)
              })
              |> Repo.insert(on_conflict: :nothing)

            _ ->
              Logger.warning("FeedResearchWorker: scouting generation failed for #{player.full_name}")
          end

        _ ->
          Logger.info("FeedResearchWorker: no sources found for scouting on #{player.full_name}")
      end
    end
  rescue
    e ->
      Logger.warning("FeedResearchWorker: scouting error for #{player.full_name}: #{Exception.message(e)}")
  end
end
