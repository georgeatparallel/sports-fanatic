defmodule SportsFanatic.Agents.Actions.SearchExa do
  @moduledoc """
  Searches Exa.ai for external MLB news articles and deduplicates
  against existing news_items by source_url.
  """

  use SportsFanatic.Agents.Action,
    name: "search_exa",
    description: "Search the web for MLB news articles via Exa.ai"

  import Ecto.Query
  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.ExternalApis.Exa
  alias SportsFanatic.Repo

  require Logger

  @impl true
  def run(params, _context) do
    query = Map.fetch!(params, :query)
    num_results = Map.get(params, :num_results, 5)
    days_back = Map.get(params, :days_back, 7)

    case Exa.search(query, num_results: num_results, days_back: days_back) do
      {:ok, results} when results != [] ->
        urls = Enum.map(results, & &1.url) |> Enum.filter(&is_binary/1)

        existing_urls =
          if urls != [] do
            from(n in NewsItem, where: n.source_url in ^urls, select: n.source_url)
            |> Repo.all()
            |> MapSet.new()
          else
            MapSet.new()
          end

        {known, new} =
          Enum.split_with(results, fn r -> MapSet.member?(existing_urls, r.url) end)

        known_articles =
          if known != [] do
            known_urls = Enum.map(known, & &1.url)

            from(n in NewsItem,
              where: n.source_url in ^known_urls,
              select: %{
                id: n.id,
                title: n.title,
                ai_summary: n.ai_summary,
                published_date: n.published_date,
                category: n.category,
                sentiment: n.sentiment,
                source_url: n.source_url,
                author: n.author,
                player_ids: n.player_ids,
                team_ids: n.team_ids,
                domain_tags: n.domain_tags
              }
            )
            |> Repo.all()
          else
            []
          end

        {:ok,
         %{
           known_articles: known_articles,
           new_articles: new,
           total_results: length(results),
           new_count: length(new),
           known_count: length(known)
         }}

      {:ok, []} ->
        {:ok,
         %{known_articles: [], new_articles: [], total_results: 0, new_count: 0, known_count: 0}}

      {:error, reason} ->
        Logger.error("SearchExa failed: #{inspect(reason)}")
        {:error, {:exa_search_failed, reason}}
    end
  end
end
