defmodule SportsFanatic.Agents.Actions.SearchLocalNews do
  @moduledoc """
  Searches the local news_items table using PostgreSQL full-text search.
  Uses the tsvector column on news_items for ranked relevance.
  """

  use SportsFanatic.Agents.Action,
    name: "search_local_news",
    description: "Search the local MLB news database for articles matching a query"

  import Ecto.Query
  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.Repo

  require Logger

  @impl true
  def run(params, _context) do
    query = Map.fetch!(params, :query)
    limit = Map.get(params, :limit, 10)
    date_from = Map.get(params, :date_from)
    date_to = Map.get(params, :date_to)

    if String.trim(query) == "" do
      {:ok, %{articles: [], count: 0}}
    else
      base_query =
        from(n in NewsItem,
          where:
            fragment(
              "search_vector @@ websearch_to_tsquery('english', ?)",
              ^query
            ),
          order_by: [
            desc:
              fragment(
                "ts_rank(search_vector, websearch_to_tsquery('english', ?))",
                ^query
              )
          ],
          limit: ^limit,
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

      base_query =
        case parse_date(date_from) do
          {:ok, d} -> where(base_query, [n], n.published_date >= ^d)
          _ -> base_query
        end

      base_query =
        case parse_date(date_to) do
          {:ok, d} -> where(base_query, [n], n.published_date <= ^d)
          _ -> base_query
        end

      articles = Repo.all(base_query)

      {:ok, %{articles: articles, count: length(articles)}}
    end
  rescue
    e ->
      Logger.error("SearchLocalNews error: #{inspect(e)}")
      {:error, {:search_failed, Exception.message(e)}}
  end

  defp parse_date(nil), do: :none

  defp parse_date(date_str) when is_binary(date_str) do
    Date.from_iso8601(date_str)
  end

  defp parse_date(%Date{} = d), do: {:ok, d}
  defp parse_date(_), do: :none
end
