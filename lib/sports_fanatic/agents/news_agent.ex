defmodule SportsFanatic.Agents.NewsAgent do
  @moduledoc """
  MLB deep research agent. Provides rich, Claude-like research responses by:

  1. Searching local news database for existing coverage
  2. Generating multi-angle Exa.ai search prompts (injury timeline, fantasy, performance)
  3. Fetching up to 25 articles per search from Exa.ai
  4. Synthesizing ALL source material through an LLM for a comprehensive response
  5. Storing new articles in the feed for all users

  The agent acts like a knowledgeable baseball friend — covering injury timelines,
  rehab status, fantasy implications, betting angles, and more.
  """

  alias SportsFanatic.Agents.Actions.{ClassifyArticle, SearchExa, SearchLocalNews}
  alias SportsFanatic.PythonBridge

  require Logger

  @agent_timeout 120_000

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
        broadcast_progress(user_id, "Research timed out. Try a more specific question.")
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

    # Step 1: Search local news
    broadcast_progress(user_id, "Searching our news database...")

    local_result = SearchLocalNews.run(%{query: resolved_query, limit: 15}, %{})

    {local_articles, local_ids} =
      case local_result do
        {:ok, %{articles: articles, count: count}} when count > 0 ->
          newest = articles |> Enum.map(& &1.published_date) |> Enum.max(Date)
          age_days = Date.diff(Date.utc_today(), newest)

          age_text =
            cond do
              age_days == 0 -> "from today"
              age_days == 1 -> "from yesterday"
              age_days <= 7 -> "from #{age_days} days ago"
              true -> "from #{age_days} days ago"
            end

          broadcast_progress(
            user_id,
            "Found #{count} article#{pl(count)} in our database (most recent #{age_text})."
          )

          ids = Enum.map(articles, & &1.id)
          {articles, ids}

        _ ->
          broadcast_progress(
            user_id,
            "Nothing in our database yet — researching external sources..."
          )

          {[], []}
      end

    # Step 2: Always do Exa research for comprehensive coverage
    # (even with some local results, unless we have 10+)
    {exa_sources, exa_ids} =
      if length(local_articles) < 10 do
        deep_research(resolved_query, user_id, pregenerated_prompts)
      else
        broadcast_progress(user_id, "We have extensive coverage already.")
        {[], []}
      end

    all_ids = (local_ids ++ exa_ids) |> Enum.uniq()

    # Step 3: Synthesize everything into a rich response via LLM
    summary =
      if exa_sources != [] or local_articles != [] do
        synthesize_response(resolved_query, local_articles, exa_sources, user_id)
      else
        "I searched our database and external sources for \"#{resolved_query}\" but couldn't find any relevant MLB coverage. " <>
          "Try being more specific — for example, include the player's team or a specific topic like 'injury update' or 'season stats'."
      end

    {:ok, %{summary: summary, news_item_ids: all_ids}}
  rescue
    e ->
      Logger.error(
        "NewsAgent error: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      {:error, {:agent_error, Exception.message(e)}}
  end

  # ── Context Resolution ──────────────────────────────────────

  defp resolve_context(query, context, user_id) do
    broadcast_progress(user_id, "Understanding your question...")

    case PythonBridge.resolve_chat_context(query, context) do
      {:ok, %{"resolved_query" => resolved, "search_prompts" => prompts}} ->
        if resolved != query do
          broadcast_progress(user_id, "I see — you're asking about: #{resolved}")
        end

        Logger.info("Context resolved: '#{query}' → '#{resolved}'")
        {resolved, prompts}

      {:error, reason} ->
        Logger.warning("Context resolution failed: #{inspect(reason)}")
        {query, nil}
    end
  end

  # ── Deep Multi-Angle Research ───────────────────────────────

  defp deep_research(query, user_id, pregenerated_prompts) do
    broadcast_progress(user_id, "Launching deep research...")

    # Generate multi-angle search prompts
    search_queries =
      if pregenerated_prompts && pregenerated_prompts != [] do
        pregenerated_prompts
      else
        generate_multi_angle_prompts(query)
      end

    broadcast_progress(user_id, "Researching #{length(search_queries)} angles...")

    # Execute all searches and collect raw sources
    {all_sources, all_new_ids} =
      search_queries
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {search_query, idx}, {sources_acc, ids_acc} ->
        short_query = String.slice(search_query, 0, 55)
        broadcast_progress(user_id, "(#{idx}/#{length(search_queries)}) #{short_query}...")

        case SearchExa.run(%{query: search_query, num_results: 25, days_back: 30}, %{}) do
          {:ok, %{new_articles: new, known_articles: known, new_count: new_count}} ->
            # Collect raw sources for synthesis (both known and new)
            raw_sources =
              Enum.map(new, fn a ->
                %{
                  title: a.title,
                  text: a.text,
                  url: a.url,
                  author: a.author,
                  published_date: a.published_date
                }
              end)

            # Classify top 5 new articles inline, rest will be in sources for synthesis
            new_ids =
              if new_count > 0 do
                classify_count = min(new_count, 5)

                broadcast_progress(
                  user_id,
                  "Saving #{classify_count} of #{new_count} new article#{pl(new_count)}..."
                )

                classify_new_articles(Enum.take(new, 5), user_id)
              else
                []
              end

            # Also include known article IDs
            known_ids = Enum.map(known, & &1.id)

            {sources_acc ++ raw_sources, ids_acc ++ new_ids ++ known_ids}

          {:error, reason} ->
            Logger.warning("Exa search failed for '#{search_query}': #{inspect(reason)}")
            {sources_acc, ids_acc}
        end
      end)

    unique_ids = Enum.uniq(all_new_ids)

    if all_sources != [] do
      broadcast_progress(
        user_id,
        "Found #{length(all_sources)} sources across all searches. Analyzing..."
      )
    end

    {all_sources, unique_ids}
  end

  # Generate search prompts covering multiple angles
  defp generate_multi_angle_prompts(query) do
    # Base queries that cover different angles
    base = String.downcase(query)

    prompts = [
      # General news and latest updates
      "#{query} MLB baseball 2026 latest news update",
      # Injury / IL status (very common query intent)
      "#{query} MLB injury update IL status return timeline 2026",
      # Performance and stats
      "#{query} MLB 2026 season stats performance"
    ]

    # Add fantasy angle if it seems player-related (not a topic like "trade deadline")
    if not String.contains?(base, ~w(trade deadline streak standings playoff)) do
      prompts ++ ["#{query} fantasy baseball 2026 outlook value"]
    else
      prompts
    end
  end

  # ── LLM Synthesis ───────────────────────────────────────────

  defp synthesize_response(query, local_articles, exa_sources, user_id) do
    broadcast_progress(user_id, "Synthesizing research into a comprehensive response...")

    # Prepare local article summaries
    local_summaries =
      local_articles
      |> Enum.take(10)
      |> Enum.map(fn a ->
        summary = a.ai_summary || a.title || ""
        category = a.category || ""
        date = if a.published_date, do: " (#{a.published_date})", else: ""
        "[#{category}]#{date} #{summary}"
      end)

    # Prepare Exa sources for synthesis
    sources_for_llm =
      exa_sources
      |> Enum.take(25)
      |> Enum.map(fn s ->
        %{
          title: s.title || "",
          text: s.text || "",
          url: s.url || "",
          author: s.author,
          published_date: s.published_date
        }
      end)

    case PythonBridge.synthesize_research(query, sources_for_llm, local_summaries) do
      {:ok, %{"response" => response}} when is_binary(response) and response != "" ->
        broadcast_progress(user_id, "Research complete!")
        response

      {:error, reason} ->
        Logger.warning("Synthesis failed: #{inspect(reason)}")
        # Fallback: basic summary
        total = length(local_articles) + length(exa_sources)

        "I found #{total} source#{pl(total)} about \"#{query}\" but couldn't generate a detailed analysis right now. " <>
          "The articles are displayed below for you to browse."

      _ ->
        "Research complete. Check the articles below for details."
    end
  end

  # ── Article Classification ──────────────────────────────────

  defp classify_new_articles(articles, user_id) do
    articles
    |> Enum.take(25)
    |> Enum.with_index(1)
    |> Enum.map(fn {article, idx} ->
      if rem(idx, 10) == 0 do
        broadcast_progress(user_id, "Classifying article #{idx}/#{min(length(articles), 25)}...")
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
        {:ok, %{status: :created, news_item_id: id}} when not is_nil(id) -> id
        {:ok, %{status: :already_exists}} -> nil
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ── Helpers ─────────────────────────────────────────────────

  defp pl(1), do: ""
  defp pl(_), do: "s"

  defp broadcast_progress(user_id, message) do
    Phoenix.PubSub.broadcast(
      SportsFanatic.PubSub,
      "chat:#{user_id}",
      {:agent_progress, %{message: message}}
    )
  end
end
