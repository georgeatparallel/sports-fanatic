defmodule SportsFanatic.Agents.NewsAgent do
  @moduledoc """
  MLB news research agent. Orchestrates a ReAct-style tool-calling loop:

  1. Search local news database
  2. If insufficient results, search Exa.ai for external articles
  3. Classify and store any new articles discovered
  4. Return a summary with article IDs

  Progress updates are broadcast via PubSub to `chat:{user_id}`.
  """

  alias SportsFanatic.Agents.Actions.{ClassifyArticle, SearchExa, SearchLocalNews}

  require Logger

  @agent_timeout 60_000

  @doc """
  Executes the agent synchronously. Broadcasts progress updates to PubSub.
  Returns `{:ok, %{summary: text, news_item_ids: [uuid]}}` or `{:error, reason}`.
  """
  def run(query, opts \\ []) do
    user_id = Keyword.fetch!(opts, :user_id)
    context = Keyword.get(opts, :context, [])
    date = Keyword.get(opts, :date)

    task =
      Task.async(fn ->
        execute(query, user_id, context, date)
      end)

    case Task.yield(task, @agent_timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        broadcast_progress(user_id, "Agent timed out after #{div(@agent_timeout, 1000)} seconds.")
        {:error, :timeout}
    end
  end

  defp execute(query, user_id, _context, date) do
    all_article_ids = []

    # Step 1: Search local news
    broadcast_progress(user_id, "Searching local news database...")

    local_result =
      SearchLocalNews.run(
        %{
          query: query,
          limit: 10,
          date_from: date,
          date_to: date
        },
        %{}
      )

    {local_articles, all_article_ids} =
      case local_result do
        {:ok, %{articles: articles, count: count}} when count > 0 ->
          broadcast_progress(user_id, "Found #{count} local article#{if count != 1, do: "s"}.")
          ids = Enum.map(articles, & &1.id)
          {articles, ids}

        _ ->
          broadcast_progress(user_id, "No local articles found.")
          {[], all_article_ids}
      end

    # Step 2: Search Exa if local results are insufficient
    {exa_article_ids, new_count} =
      if length(local_articles) < 3 do
        search_exa(query, user_id)
      else
        {[], 0}
      end

    all_article_ids = (all_article_ids ++ exa_article_ids) |> Enum.uniq()

    # Step 3: Build summary
    total = length(all_article_ids)

    summary =
      cond do
        total == 0 ->
          "I couldn't find any articles matching your query. Try different search terms or check back later."

        new_count > 0 ->
          "Found #{total} article#{if total != 1, do: "s"} related to your query" <>
            " (#{new_count} newly discovered from external sources)."

        true ->
          "Found #{total} article#{if total != 1, do: "s"} related to your query."
      end

    {:ok, %{summary: summary, news_item_ids: all_article_ids}}
  rescue
    e ->
      Logger.error(
        "NewsAgent execution error: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      {:error, {:agent_error, Exception.message(e)}}
  end

  defp search_exa(query, user_id) do
    broadcast_progress(user_id, "Searching external sources via Exa.ai...")

    case SearchExa.run(%{query: "#{query} MLB baseball 2026", num_results: 5, days_back: 7}, %{}) do
      {:ok, %{known_articles: known, new_articles: new, new_count: new_count}} ->
        known_ids = Enum.map(known, & &1.id)

        new_ids =
          if new_count > 0 do
            broadcast_progress(
              user_id,
              "Processing #{new_count} new external article#{if new_count != 1, do: "s"}..."
            )

            classify_new_articles(new, user_id)
          else
            []
          end

        if known != [] do
          broadcast_progress(
            user_id,
            "Found #{length(known)} previously indexed article#{if length(known) != 1, do: "s"}."
          )
        end

        {known_ids ++ new_ids, length(new_ids)}

      {:error, reason} ->
        Logger.warning("Exa search failed: #{inspect(reason)}")
        broadcast_progress(user_id, "External search unavailable, showing local results only.")
        {[], 0}
    end
  end

  defp classify_new_articles(articles, user_id) do
    articles
    |> Enum.map(fn article ->
      case ClassifyArticle.run(
             %{
               title: article.title,
               body: article.text,
               source_url: article.url,
               author: article.author
             },
             %{}
           ) do
        {:ok, %{status: :created, news_item_id: id}} when not is_nil(id) ->
          id

        {:ok, %{status: :already_exists}} ->
          nil

        {:error, reason} ->
          Logger.warning("Failed to classify article: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> tap(fn ids ->
      if ids != [] do
        broadcast_progress(
          user_id,
          "Enriched and stored #{length(ids)} new article#{if length(ids) != 1, do: "s"}."
        )
      end
    end)
  end

  defp broadcast_progress(user_id, message) do
    Phoenix.PubSub.broadcast(
      SportsFanatic.PubSub,
      "chat:#{user_id}",
      {:agent_progress, %{message: message}}
    )
  end
end
