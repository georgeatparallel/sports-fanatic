defmodule SportsFanatic.Workers.FeedResearchWorker do
  @moduledoc """
  Oban worker that researches news for all active user feeds.

  Runs daily (default 9:00 AM ET / 13:00 UTC). For each feed, searches
  local news and Exa for each player, with a 2-second delay between
  Exa calls to avoid rate limiting. Caps at 50 players per feed.
  """

  use Oban.Worker, queue: :default, max_attempts: 2

  alias SportsFanatic.Agents.Actions.{SearchExa, SearchLocalNews}
  alias SportsFanatic.Feeds
  alias SportsFanatic.Mlb.Player
  alias SportsFanatic.Repo

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

    for feed <- feeds do
      research_feed(feed)
    end

    :ok
  end

  defp research_feed(feed) do
    player_ids = Enum.take(feed.player_ids, @max_players_per_feed)

    for player_id <- player_ids do
      case Repo.get(Player, player_id) do
        nil ->
          Logger.warning("FeedResearchWorker: player #{player_id} not found, skipping")

        player ->
          research_player(player)
      end
    end

    Feeds.update_feed(feed, %{last_researched_at: DateTime.utc_now()})
  rescue
    e ->
      Logger.error(
        "FeedResearchWorker: error researching feed #{feed.id}: #{Exception.message(e)}"
      )
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
  rescue
    e ->
      Logger.error(
        "FeedResearchWorker: error researching player #{player.full_name}: #{Exception.message(e)}"
      )
  end
end
