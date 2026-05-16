defmodule SportsFanatic.Agents.NewsAgent do
  @moduledoc """
  MLB news research agent. Orchestrates a ReAct-style tool-calling loop:

  1. Search local news database (no date restriction — search ALL articles)
  2. If results found, report what we have and how recent it is
  3. If insufficient results, automatically search Exa.ai with LLM-generated prompts
  4. Classify and store any new articles discovered
  5. Return a conversational summary with article IDs

  Progress updates are broadcast via PubSub to `chat:{user_id}`.
  """

  alias SportsFanatic.Agents.Actions.{ClassifyArticle, SearchExa, SearchLocalNews}
  alias SportsFanatic.PythonBridge

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

  defp execute(query, user_id, context, _date) do
    # Step 0: Resolve context if conversation history exists
    {resolved_query, pregenerated_prompts} =
      if context != [] and length(context) > 1 do
        resolve_context(query, context, user_id)
      else
        {query, nil}
      end

    # Step 1: Search local news (no date restriction — search everything)
    broadcast_progress(user_id, "Searching our news database...")

    local_result =
      SearchLocalNews.run(%{query: resolved_query, limit: 15}, %{})

    {local_articles, local_ids} =
      case local_result do
        {:ok, %{articles: articles, count: count}} when count > 0 ->
          # Report what we found and how old it is
          newest = articles |> Enum.map(& &1.published_date) |> Enum.max(Date)
          age_days = Date.diff(Date.utc_today(), newest)

          age_text =
            cond do
              age_days == 0 -> "from today"
              age_days == 1 -> "from yesterday"
              age_days <= 7 -> "from #{age_days} days ago"
              true -> "from #{age_days} days ago (#{Date.to_iso8601(newest)})"
            end

          broadcast_progress(
            user_id,
            "Found #{count} article#{if count != 1, do: "s"} in our database, most recent #{age_text}."
          )

          ids = Enum.map(articles, & &1.id)
          {articles, ids}

        _ ->
          broadcast_progress(user_id, "No articles found in our database for \"#{resolved_query}\".")
          {[], []}
      end

    # Step 2: If insufficient local results, do deep Exa research
    {exa_ids, exa_summary} =
      if length(local_articles) < 3 do
        deep_research(resolved_query, user_id, pregenerated_prompts)
      else
        {[], nil}
      end

    all_ids = (local_ids ++ exa_ids) |> Enum.uniq()

    # Step 3: Build conversational summary
    summary = build_summary(resolved_query, local_articles, exa_ids, exa_summary, all_ids)

    {:ok, %{summary: summary, news_item_ids: all_ids}}
  rescue
    e ->
      Logger.error(
        "NewsAgent execution error: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      {:error, {:agent_error, Exception.message(e)}}
  end

  # Resolve conversation context using LLM to detect topic changes and resolve references
  defp resolve_context(query, context, user_id) do
    broadcast_progress(user_id, "Understanding your question...")

    case PythonBridge.resolve_chat_context(query, context) do
      {:ok, %{"is_continuation" => true, "resolved_query" => resolved, "search_prompts" => prompts}} ->
        broadcast_progress(user_id, "Following up on previous topic...")
        Logger.info("Context resolved: continuation. Query: '#{query}' → '#{resolved}'")
        {resolved, prompts}

      {:ok, %{"is_continuation" => false, "resolved_query" => resolved, "search_prompts" => prompts}} ->
        broadcast_progress(user_id, "Starting new research topic...")
        Logger.info("Context resolved: new topic. Query: '#{query}' → '#{resolved}'")
        {resolved, prompts}

      {:ok, %{"resolved_query" => resolved, "search_prompts" => prompts}} ->
        # Fallback if is_continuation key is missing
        {resolved, prompts}

      {:error, reason} ->
        Logger.warning("Context resolution failed: #{inspect(reason)}, using raw query")
        {query, nil}
    end
  end

  # Deep research via Exa.ai with LLM-generated search prompts
  defp deep_research(query, user_id, pregenerated_prompts) do
    broadcast_progress(user_id, "Researching external sources for deeper coverage...")

    # Use pregenerated prompts from context resolver, or generate new ones
    search_queries =
      if pregenerated_prompts && pregenerated_prompts != [] do
        broadcast_progress(user_id, "Using #{length(pregenerated_prompts)} context-aware research queries.")
        pregenerated_prompts
      else
        generate_search_prompts(query, user_id)
      end

    # Execute all search prompts and aggregate results
    all_new_ids =
      Enum.flat_map(search_queries, fn search_query ->
        broadcast_progress(user_id, "Searching: \"#{String.slice(search_query, 0, 60)}\"...")

        case SearchExa.run(%{query: search_query, num_results: 25, days_back: 30}, %{}) do
          {:ok, %{new_articles: new, new_count: new_count, known_count: known_count}} ->
            if known_count > 0 do
              broadcast_progress(user_id, "Found #{known_count} previously indexed article#{if known_count != 1, do: "s"}.")
            end

            if new_count > 0 do
              broadcast_progress(user_id, "Discovering #{new_count} new article#{if new_count != 1, do: "s"}, processing...")
              classify_new_articles(new, user_id)
            else
              []
            end

          {:error, reason} ->
            Logger.warning("Exa search failed for '#{search_query}': #{inspect(reason)}")
            []
        end
      end)
      |> Enum.uniq()

    # Generate an aggregated summary from the Exa research
    exa_summary =
      if all_new_ids != [] do
        broadcast_progress(user_id, "Research complete — discovered #{length(all_new_ids)} new article#{if length(all_new_ids) != 1, do: "s"}.")
        "Discovered #{length(all_new_ids)} new articles from external sources and added them to our database."
      else
        broadcast_progress(user_id, "External search complete — no new articles found beyond what we already have.")
        nil
      end

    {all_new_ids, exa_summary}
  end

  # Generate intelligent search prompts using LLM via Python Bridge
  defp generate_search_prompts(query, user_id) do
    broadcast_progress(user_id, "Generating research queries...")

    # Start with a base MLB-qualified query
    base_query = "#{query} MLB baseball"

    # Try to generate smarter queries via LLM
    case generate_llm_prompts(query) do
      {:ok, prompts} when prompts != [] ->
        broadcast_progress(user_id, "Generated #{length(prompts)} research queries.")
        prompts

      _ ->
        # Fallback: manually generate variations
        Logger.info("LLM prompt generation unavailable, using manual variations")

        [
          base_query,
          "#{query} MLB 2026 news",
          "#{query} baseball stats season"
        ]
    end
  end

  # Use the Python Bridge to generate search prompts
  defp generate_llm_prompts(query) do
    case PythonBridge.analyze_news(
           "Generate Exa search queries for: #{query}",
           """
           Generate 3 search queries to find comprehensive MLB baseball news about: "#{query}"

           Requirements:
           - Each query should find different angles (recent news, stats, analysis)
           - Always include "MLB" or "baseball" to filter noise
           - Include the current year (2026) in at least one query
           - Be specific enough to get relevant results

           Return queries as a comma-separated list.
           """
         ) do
      {:ok, %{"ai_summary" => summary}} when is_binary(summary) and summary != "" ->
        prompts =
          summary
          |> String.split(~r/[,\n]+/, trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.take(4)

        if prompts != [], do: {:ok, prompts}, else: {:error, :empty}

      _ ->
        {:error, :llm_unavailable}
    end
  end

  defp classify_new_articles(articles, user_id) do
    articles
    |> Enum.take(25)
    |> Enum.with_index(1)
    |> Enum.map(fn {article, idx} ->
      if rem(idx, 5) == 0 do
        broadcast_progress(user_id, "Processing article #{idx}/#{min(length(articles), 25)}...")
      end

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
  end

  defp build_summary(query, local_articles, exa_ids, exa_summary, all_ids) do
    total = length(all_ids)

    cond do
      total == 0 ->
        "I searched our database and external sources for \"#{query}\" but couldn't find any relevant articles. " <>
          "This player or topic may not have recent MLB news coverage. " <>
          "Try searching with different terms, or ask me about a specific team or recent event."

      local_articles != [] and exa_ids == [] ->
        "I found #{length(local_articles)} article#{if length(local_articles) != 1, do: "s"} about \"#{query}\" in our database. " <>
          "These are the most relevant results from our news feed."

      local_articles == [] and exa_ids != [] ->
        "\"#{query}\" wasn't in our news feed, so I searched external sources and " <>
          "discovered #{length(exa_ids)} new article#{if length(exa_ids) != 1, do: "s"}. " <>
          "#{exa_summary || ""} These have been added to our feed and are now available for everyone."

      true ->
        "Found #{total} total article#{if total != 1, do: "s"} about \"#{query}\": " <>
          "#{length(local_articles)} from our database" <>
          if(exa_ids != [], do: " and #{length(exa_ids)} newly discovered from external research", else: "") <>
          ". #{exa_summary || ""}"
    end
  end

  defp broadcast_progress(user_id, message) do
    Phoenix.PubSub.broadcast(
      SportsFanatic.PubSub,
      "chat:#{user_id}",
      {:agent_progress, %{message: message}}
    )
  end
end
