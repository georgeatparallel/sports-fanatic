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

  alias SportsFanatic.AI.Claude
  alias SportsFanatic.Agents.Actions.{ClassifyArticle, SearchExa, SearchLocalNews}
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Mlb.Player
  alias SportsFanatic.Repo

  import Ecto.Query

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

    # Step 2: Only do Exa research if local results are insufficient
    {exa_sources, exa_ids} =
      if length(local_articles) < 5 do
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

    # Step 4: Generate scouting reports for mentioned players and append links
    # Skip if synthesis already included scouting links
    summary =
      if String.contains?(summary, "Scouting Report") do
        summary
      else
        maybe_add_scouting(summary, all_ids, user_id)
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

    case Claude.resolve_context(query, context) do
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

    broadcast_progress(user_id, "Searching #{length(search_queries)} angles in parallel...")

    # Run all Exa searches IN PARALLEL
    exa_results =
      search_queries
      |> Task.async_stream(
        fn search_query ->
          SearchExa.run(%{query: search_query, num_results: 10, days_back: 30}, %{})
        end,
        max_concurrency: 3,
        timeout: 20_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        _ -> {:error, :timeout}
      end)

    # Collect sources and known IDs from all searches
    {all_sources, all_new_articles, known_ids} =
      Enum.reduce(exa_results, {[], [], []}, fn
        {:ok, %{new_articles: new, known_articles: known}}, {src, new_acc, kid} ->
          raw = Enum.map(new, fn a ->
            %{title: a.title, text: a.text, url: a.url, author: a.author, published_date: a.published_date}
          end)
          {src ++ raw, new_acc ++ new, kid ++ Enum.map(known, & &1.id)}

        _, acc -> acc
      end)

    # Classify top 3 new articles IN PARALLEL (not 5 sequentially)
    new_ids =
      if all_new_articles != [] do
        to_classify = Enum.take(all_new_articles, 3)
        broadcast_progress(user_id, "Saving #{length(to_classify)} new article#{pl(length(to_classify))} in parallel...")

        to_classify
        |> Task.async_stream(
          fn article ->
            case ClassifyArticle.run(
              %{title: article.title, body: article.text, source_url: article.url, author: article.author},
              %{}
            ) do
              {:ok, %{status: :created, news_item_id: id}} when not is_nil(id) -> id
              _ -> nil
            end
          end,
          max_concurrency: 3,
          timeout: 15_000,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, id} -> id
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    unique_ids = Enum.uniq(new_ids ++ known_ids)

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
    # 2 focused searches — keeps total time under 60s
    [
      "#{query} MLB baseball 2026 latest news update",
      "#{query} MLB injury update fantasy outlook 2026"
    ]
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

    case Claude.synthesize_research(query, sources_for_llm, local_summaries) do
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

  # ── Scouting Report Integration ─────────────────────────────

  defp maybe_add_scouting(summary, article_ids, _user_id) when article_ids == [] do
    summary
  end

  defp maybe_add_scouting(summary, article_ids, user_id) do
    today = SportsFanatic.DateHelper.today()

    # Find players referenced in the matched articles
    player_ids =
      from(n in SportsFanatic.Content.NewsItem,
        where: n.id in ^article_ids,
        select: n.player_ids
      )
      |> Repo.all()
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if player_ids == [] do
      summary
    else
      # Load player info
      players =
        from(p in Player, where: p.id in ^player_ids)
        |> Repo.all()

      if players == [] do
        summary
      else
        # Check which players have scouting reports today
        existing_report_player_ids =
          from(sr in ScoutingReport,
            where: sr.player_id in ^player_ids and sr.report_date == ^today,
            select: sr.player_id
          )
          |> Repo.all()
          |> MapSet.new()

        # Generate reports for players missing them (max 3 to avoid timeout)
        players_needing_reports =
          players
          |> Enum.reject(&MapSet.member?(existing_report_player_ids, &1.id))
          |> Enum.take(3)

        if players_needing_reports != [] do
          broadcast_progress(user_id, "Generating scouting reports for #{length(players_needing_reports)} player#{pl(length(players_needing_reports))}...")

          for player <- players_needing_reports do
            generate_scouting_for_player(player, today)
          end
        end

        # Build scouting links section
        scouting_links =
          players
          |> Enum.take(5)
          |> Enum.map(fn player ->
            team = Repo.get(SportsFanatic.Mlb.Team, player.team_id)
            team_slug = if team, do: team.slug, else: "unknown"

            has_report = MapSet.member?(existing_report_player_ids, player.id) or
              player.id in Enum.map(players_needing_reports, & &1.id)

            if has_report do
              "- [**#{player.full_name}**](/mlb/scouting/#{team_slug}/#{player.slug})"
            else
              "- **#{player.full_name}** (scouting report pending)"
            end
          end)
          |> Enum.join("\n")

        # Get a teaser from the first scouting report
        teaser =
          case Repo.one(from sr in ScoutingReport,
            where: sr.player_id in ^player_ids and sr.report_date == ^today,
            order_by: [desc: sr.inserted_at],
            limit: 1
          ) do
            %{content: content} when is_map(content) ->
              news_summary = content["news_summary"] || ""
              sentiment = content["overall_sentiment"] || ""
              if news_summary != "", do: " #{sentiment |> String.capitalize()} outlook — #{news_summary}", else: ""
            _ -> ""
          end

        summary <>
          "\n\n---\n\n**Scouting Reports Available** — click a player to see their full scouting breakdown:#{teaser}\n\n" <>
          scouting_links
      end
    end
  rescue
    e ->
      Logger.warning("Scouting integration error: #{Exception.message(e)}")
      summary
  end

  defp generate_scouting_for_player(player, today) do
    case Claude.search_player_sources(player.full_name) do
      {:ok, sources} when sources != [] ->
        sources_text = Enum.map_join(sources, "\n\n---\n\n", fn s -> "#{s.title}\n#{s.text}" end)

        case Claude.generate_scouting(player.full_name, sources_text) do
          {:ok, report} when is_map(report) ->
            %ScoutingReport{}
            |> ScoutingReport.changeset(%{
              player_id: player.id,
              report_date: today,
              summary: report["news_summary"] || "Scouting report for #{player.full_name}",
              full_report: report,
              overall_grade: sentiment_to_grade(report["overall_sentiment"]),
              strengths: report["positive_factors"] || [],
              weaknesses: report["negative_factors"] || [],
              injury_risk: report["injury_status"] || "unknown",
              injury_detail: report["injury_detail"],
              sources_count: length(sources)
            })
            |> Repo.insert(on_conflict: :nothing)

          _ -> :skip
        end

      _ -> :skip
    end
  rescue
    _ -> :skip
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

  defp sentiment_to_grade("positive"), do: "A"
  defp sentiment_to_grade("neutral"), do: "B"
  defp sentiment_to_grade("negative"), do: "C"
  defp sentiment_to_grade(_), do: "B"
end
