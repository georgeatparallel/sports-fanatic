defmodule SportsFanatic.Scouting.Pipeline do
  @moduledoc """
  GenServer orchestrating the agentic scouting report pipeline.

  Processes only players in today's scheduled lineups through research,
  classification, and report generation phases with configurable concurrency.
  Typically ~60-100 players per day instead of all ~6,165 active players.

  Broadcasts progress via Phoenix PubSub on topic "scouting_pipeline".
  """

  use GenServer

  alias SportsFanatic.Cache
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Repo
  alias SportsFanatic.Scouting

  require Logger

  @pubsub SportsFanatic.PubSub
  @topic "scouting_pipeline"

  # --- Client API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start the pipeline with the given configuration."
  def start_pipeline(config \\ %{}) do
    GenServer.call(__MODULE__, {:start_pipeline, config}, :infinity)
  end

  @doc "Cancel the currently running pipeline."
  def cancel_pipeline do
    GenServer.call(__MODULE__, :cancel_pipeline)
  end

  @doc "Get the current pipeline status."
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc "Subscribe to pipeline progress updates."
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    {:ok, %{status: :idle, run: nil, task_sup: nil}}
  end

  @impl true
  def handle_call({:start_pipeline, config}, _from, %{status: :idle} = state) do
    research_concurrency = Map.get(config, "research_concurrency", 5)
    classification_concurrency = Map.get(config, "classification_concurrency", 5)

    # Load only players in today's lineups (not all active players)
    players = Scouting.players_in_todays_lineups()
    total = length(players)

    if total == 0 do
      Logger.info("No lineups for today — skipping scouting pipeline")
      {:reply, {:error, :no_lineups_today}, state}
    else
      # Create run record
      {:ok, run} =
        Scouting.create_run(%{
          status: "running",
          total_players: total,
          config: %{
            research_concurrency: research_concurrency,
            classification_concurrency: classification_concurrency
          },
          started_at: DateTime.utc_now()
        })

      broadcast(:pipeline_started, %{
        run_id: run.id,
        total_players: total,
        config: run.config
      })

      # Start processing in a separate process
      {:ok, task_sup} = Task.Supervisor.start_link()

      Task.start(fn ->
        process_players(run, players, research_concurrency, classification_concurrency)
      end)

      {:reply, {:ok, run}, %{state | status: :running, run: run, task_sup: task_sup}}
    end
  end

  def handle_call({:start_pipeline, _config}, _from, state) do
    {:reply, {:error, :already_running}, state}
  end

  def handle_call(:cancel_pipeline, _from, %{status: :running, run: run} = state) do
    Scouting.update_run(run, %{status: "cancelled", completed_at: DateTime.utc_now()})
    broadcast(:pipeline_cancelled, %{run_id: run.id})
    {:reply, :ok, %{state | status: :idle, run: nil}}
  end

  def handle_call(:cancel_pipeline, _from, state) do
    {:reply, {:error, :not_running}, state}
  end

  def handle_call(:get_status, _from, state) do
    status_info =
      case state.status do
        :idle ->
          %{status: :idle, run: nil}

        :running ->
          run = Scouting.get_run!(state.run.id)

          %{
            status: :running,
            run_id: run.id,
            total_players: run.total_players,
            processed_players: run.processed_players,
            config: run.config
          }
      end

    {:reply, status_info, state}
  end

  @impl true
  def handle_info({:pipeline_complete, run_id}, state) do
    if state.run && state.run.id == run_id do
      {:noreply, %{state | status: :idle, run: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Pipeline Processing ---

  defp process_players(run, players, research_concurrency, classification_concurrency) do
    players
    |> Task.async_stream(
      fn player ->
        process_single_player(run, player, classification_concurrency)
      end,
      max_concurrency: research_concurrency,
      timeout: 300_000,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, _result} -> :ok
      {:exit, reason} -> Logger.warning("Player processing task exited: #{inspect(reason)}")
    end)

    # Complete the run
    run = Scouting.get_run!(run.id)

    Scouting.update_run(run, %{
      status: "completed",
      completed_at: DateTime.utc_now()
    })

    broadcast(:pipeline_completed, %{
      run_id: run.id,
      total_players: run.total_players,
      processed_players: run.processed_players
    })

    send(Process.whereis(__MODULE__), {:pipeline_complete, run.id})
  rescue
    e ->
      Logger.error("Pipeline failed: #{inspect(e)}")

      Scouting.update_run(run, %{
        status: "failed",
        error: inspect(e),
        completed_at: DateTime.utc_now()
      })

      broadcast(:pipeline_failed, %{run_id: run.id, error: inspect(e)})
      send(Process.whereis(__MODULE__), {:pipeline_complete, run.id})
  end

  defp process_single_player(run, player, classification_concurrency) do
    player_name = player.full_name
    Logger.info("Processing scouting for: #{player_name}")

    broadcast(:player_started, %{
      run_id: run.id,
      player_id: player.id,
      player_name: player_name,
      step: "research"
    })

    # Step 1: Research via Exa
    log_step(run, player, "research", "started", "Starting Exa research for #{player_name}")

    sources =
      case research_player(player_name) do
        {:ok, sources} ->
          log_step(
            run,
            player,
            "research",
            "completed",
            "Found #{length(sources)} sources for #{player_name}",
            %{urls_found: length(sources)}
          )

          sources

        {:error, reason} ->
          log_step(
            run,
            player,
            "research",
            "failed",
            "Research failed for #{player_name}: #{inspect(reason)}"
          )

          []
      end

    # Step 2: Deduplicate URLs
    existing_urls = Scouting.existing_urls_for_player(player.id)

    new_sources =
      Enum.reject(sources, fn source ->
        MapSet.member?(existing_urls, source["url"])
      end)

    if new_sources == [] do
      log_step(run, player, "classify", "skipped", "No new URLs to classify for #{player_name}")
    else
      # Step 3: Classify new URLs
      broadcast(:player_started, %{
        run_id: run.id,
        player_id: player.id,
        player_name: player_name,
        step: "classify"
      })

      log_step(
        run,
        player,
        "classify",
        "started",
        "Classifying #{length(new_sources)} new URLs for #{player_name}"
      )

      classified_sources = classify_sources(player, new_sources, classification_concurrency)

      log_step(
        run,
        player,
        "classify",
        "completed",
        "Classified #{length(classified_sources)} URLs for #{player_name}",
        %{urls_classified: length(classified_sources)}
      )
    end

    # Step 4: Generate report
    broadcast(:player_started, %{
      run_id: run.id,
      player_id: player.id,
      player_name: player_name,
      step: "generate"
    })

    log_step(run, player, "generate", "started", "Generating scouting report for #{player_name}")

    case generate_report(player) do
      {:ok, _report} ->
        log_step(run, player, "generate", "completed", "Report generated for #{player_name}")

        # Invalidate cache
        if player.team do
          Cache.del(Cache.scouting_page_key(player.team.slug, player.slug))
          Cache.del(Cache.player_page_key(player.team.slug, player.slug))
        end

      {:error, reason} ->
        log_step(
          run,
          player,
          "generate",
          "failed",
          "Report generation failed for #{player_name}: #{inspect(reason)}"
        )
    end

    # Mark player complete
    updated_run = Scouting.increment_processed(run)

    broadcast(:player_completed, %{
      run_id: run.id,
      player_id: player.id,
      player_name: player_name,
      processed: updated_run.processed_players,
      total: updated_run.total_players
    })

    log_step(run, player, "complete", "completed", "Pipeline complete for #{player_name}")
  rescue
    e ->
      Logger.warning("Failed processing #{player.full_name}: #{inspect(e)}")

      log_step(
        run,
        player,
        "error",
        "failed",
        "Unexpected error for #{player.full_name}: #{inspect(e)}"
      )

      Scouting.increment_processed(run)
  end

  defp research_player(player_name) do
    case PythonBridge.search_player_multi(player_name) do
      {:ok, %{"sources" => sources}} -> {:ok, sources}
      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp classify_sources(player, sources, concurrency) do
    sources
    |> Task.async_stream(
      fn source ->
        classify_and_store(player, source)
      end,
      max_concurrency: concurrency,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.reduce([], fn
      {:ok, {:ok, source_url}}, acc -> [source_url | acc]
      _, acc -> acc
    end)
  end

  defp classify_and_store(player, source) do
    url = source["url"]
    text = source["text"] || ""
    title = source["title"] || ""
    source_type = source["source_type"] || "news"

    case PythonBridge.classify_content(title, text) do
      {:ok,
       %{"classification" => classification, "summary" => summary, "key_facts" => facts} = resp} ->
        Scouting.create_source_url(%{
          player_id: player.id,
          url: url,
          source_type: source_type,
          classification: classification,
          content_summary: summary,
          key_facts: %{"facts" => facts},
          digest: resp["digest"],
          content_text: if(text != "", do: text, else: nil),
          processed_at: DateTime.utc_now()
        })

      {:error, _reason} ->
        # Store without classification for later retry
        Scouting.create_source_url(%{
          player_id: player.id,
          url: url,
          source_type: source_type,
          content_text: if(text != "", do: text, else: nil),
          processed_at: DateTime.utc_now()
        })
    end
  end

  defp generate_report(player) do
    today = Date.utc_today()
    sources_by_category = Scouting.classified_sources_for_player(player.id)

    if sources_by_category == %{} do
      {:error, :no_sources}
    else
      source_texts = build_source_texts(sources_by_category)

      case PythonBridge.generate_scouting(player.full_name, player.id, source_texts) do
        {:ok, %{"report" => report}} ->
          save_report(player, today, report, sources_by_category)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_source_texts(sources_by_category) do
    sources_by_category
    |> Enum.flat_map(fn {category, sources} ->
      Enum.map(sources, &"[#{category}] #{&1.content_summary || &1.url}")
    end)
    |> Enum.take(15)
  end

  defp save_report(player, date, report, sources_by_category) do
    # Build category impact map from sources
    category_impact =
      sources_by_category
      |> Enum.map(fn {category, sources} ->
        {category, %{"count" => length(sources), "latest" => List.first(sources).content_summary}}
      end)
      |> Map.new()

    %ScoutingReport{}
    |> ScoutingReport.changeset(%{
      player_id: player.id,
      report_date: date,
      summary: report["news_summary"] || "No summary available",
      overall_grade: assign_grade(report),
      full_report: Map.put(report, "category_sections", category_impact),
      hit_probability: report["hit_probability"],
      hr_probability: report["hr_probability"],
      strengths: report["positive_factors"] || [],
      weaknesses: report["negative_factors"] || [],
      injury_risk: report["injury_status"] || "healthy",
      injury_detail: report["injury_detail"],
      category_impact: category_impact,
      confidence_modifier: report["confidence_modifier"] || 0.0,
      sources_count: Enum.sum(Enum.map(sources_by_category, fn {_, s} -> length(s) end)),
      model_version: "claude-sonnet-4-20250514",
      generation_ms: 0
    })
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: [:player_id, :report_date]
    )
  end

  defp assign_grade(report) do
    sentiment = report["overall_sentiment"] || "neutral"
    modifier = report["confidence_modifier"] || 0.0

    case {sentiment, modifier} do
      {"positive", m} when m > 0.05 -> "A+"
      {"positive", _} -> "A"
      {"neutral", m} when m > 0 -> "B+"
      {"neutral", _} -> "B"
      {"negative", m} when m < -0.05 -> "C"
      _ -> "B-"
    end
  end

  defp log_step(run, player, step, status, message, metadata \\ %{}) do
    Scouting.create_log(%{
      scouting_run_id: run.id,
      player_id: player.id,
      step: step,
      status: status,
      message: message,
      metadata: metadata
    })
  end

  defp broadcast(event, payload) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {event, payload})
  end
end
