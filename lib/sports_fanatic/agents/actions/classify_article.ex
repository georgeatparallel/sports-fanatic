defmodule SportsFanatic.Agents.Actions.ClassifyArticle do
  @moduledoc """
  Classifies and stores a new article discovered via Exa.ai. Runs the
  article through the Python Bridge AI classification, resolves entities,
  inserts into news_items, and triggers cache invalidation + PubSub.
  """

  use SportsFanatic.Agents.Action,
    name: "classify_article",
    description: "Classify and enrich a new article via AI, then store it"

  alias SportsFanatic.AI.Claude
  alias SportsFanatic.Agents.Actions.ResolveEntities
  alias SportsFanatic.Cache
  alias SportsFanatic.News

  require Logger

  @impl true
  def run(params, context) do
    title = Map.fetch!(params, :title)
    body = Map.fetch!(params, :body)
    source_url = Map.fetch!(params, :source_url)
    author = Map.get(params, :author)

    # Check if this URL already exists
    if News.exists_by_source_url?(source_url) do
      {:ok, %{status: :already_exists, news_item_id: nil}}
    else
      # Step 1: AI classification via Python Bridge
      {category, sentiment, ai_summary} = classify_via_bridge(title, body)

      # Step 2: Entity resolution
      {:ok, entities} = ResolveEntities.run(%{text: "#{title} #{body}"}, context)

      # Step 3: Build slug
      slug = build_slug(title, source_url)

      # Step 4: Determine published date
      published_date = SportsFanatic.DateHelper.today()

      # Step 5: Insert news item
      attrs = %{
        source: "exa",
        external_id: hash_url(source_url),
        slug: slug,
        title: truncate(title, 500),
        body: truncate(body, 10_000),
        ai_summary: truncate(ai_summary, 1000),
        published_date: published_date,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second),
        player_ids: entities.player_ids,
        team_ids: entities.team_ids,
        category: category,
        sentiment: sentiment,
        source_url: source_url,
        author: truncate(author, 200),
        ai_processed: ai_summary != nil,
        domain_tags: []
      }

      case News.create_news_item(attrs) do
        {:ok, news_item} ->
          # Step 6: Cache invalidation and PubSub broadcast
          date_key = Cache.news_feed_key(published_date)
          Cache.del(date_key)

          Phoenix.PubSub.broadcast(
            SportsFanatic.PubSub,
            "news:feed:#{Date.to_iso8601(published_date)}",
            {:news_updated, published_date}
          )

          Phoenix.PubSub.broadcast(
            SportsFanatic.PubSub,
            "news:feed",
            {:news_updated, published_date}
          )

          {:ok, %{status: :created, news_item_id: news_item.id}}

        {:error, changeset} ->
          Logger.warning("Failed to insert Exa article: #{inspect(changeset.errors)}")
          {:error, {:insert_failed, changeset.errors}}
      end
    end
  rescue
    e ->
      Logger.error("ClassifyArticle error: #{inspect(e)}")
      {:error, {:classify_failed, Exception.message(e)}}
  end

  defp classify_via_bridge(title, body) do
    excerpt = String.slice(body || "", 0, 500)

    case Claude.classify_article(title, excerpt) do
      {:ok, result} when is_map(result) ->
        {
          Map.get(result, "category", "news"),
          Map.get(result, "sentiment", "neutral"),
          Map.get(result, "summary")
        }

      {:error, reason} ->
        Logger.warning("Claude classify failed: #{inspect(reason)}, using defaults")
        {"news", "neutral", nil}
    end
  end

  defp build_slug(title, source_url) do
    base =
      (title || source_url || "article")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.take(8)
      |> Enum.join("-")

    # Add a short hash for uniqueness
    hash = :erlang.phash2(source_url || title, 99999)
    "#{base}-#{hash}"
  end

  defp hash_url(url) do
    :crypto.hash(:sha256, url)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 32)
  end

  defp truncate(nil, _max), do: nil
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max)
end
