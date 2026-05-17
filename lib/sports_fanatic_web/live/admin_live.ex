defmodule SportsFanaticWeb.AdminLive do
  use SportsFanaticWeb, :live_view

  alias Ecto.Adapters.SQL
  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.Repo
  alias SportsFanatic.Scouting
  alias SportsFanatic.Scouting.Pipeline
  require Logger

  alias SportsFanatic.Agents
  alias SportsFanatic.ChatBot
  alias SportsFanatic.X, as: XContext
  alias SportsFanatic.X.{Post, SpendLedger, WatchedTarget}
  import Ecto.Query, only: [from: 2]

  @x_rate_limit_table :x_admin_rate_limit
  @x_admin_topic "admin:x_agent"

  @workers [
    %{key: "cleanup", module: SportsFanatic.Workers.CleanupWorker, label: "Cleanup"},
    %{
      key: "fetch_lineups",
      module: SportsFanatic.Workers.FetchLineupsWorker,
      label: "Fetch Lineups"
    },
    %{key: "fetch_news", module: SportsFanatic.Workers.FetchNewsWorker, label: "Fetch News"},
    %{
      key: "fetch_schedule",
      module: SportsFanatic.Workers.FetchScheduleWorker,
      label: "Fetch Schedule"
    },
    %{
      key: "generate_game_day",
      module: SportsFanatic.Workers.GenerateGameDayWorker,
      label: "Generate Game Day"
    },
    %{
      key: "generate_player_seo",
      module: SportsFanatic.Workers.GeneratePlayerSeoWorker,
      label: "Generate Player SEO"
    },
    %{
      key: "generate_predictions",
      module: SportsFanatic.Workers.GeneratePredictionsWorker,
      label: "Generate Predictions"
    },
    %{
      key: "generate_scouting",
      module: SportsFanatic.Workers.GenerateScoutingWorker,
      label: "Generate Scouting"
    },
    %{
      key: "scouting_pipeline",
      module: SportsFanatic.Workers.ScoutingPipelineWorker,
      label: "Scouting Pipeline"
    },
    %{
      key: "generate_sitemap",
      module: SportsFanatic.Workers.GenerateSitemapWorker,
      label: "Generate Sitemap"
    },
    %{key: "warm_cache", module: SportsFanatic.Workers.WarmCacheWorker, label: "Warm Cache"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      handler_id = "admin-live-#{inspect(self())}"

      :telemetry.attach(
        handler_id,
        [:oban, :job, :stop],
        &__MODULE__.handle_telemetry/4,
        %{pid: self()}
      )

      :telemetry.attach(
        "#{handler_id}-exception",
        [:oban, :job, :exception],
        &__MODULE__.handle_telemetry/4,
        %{pid: self()}
      )
    end

    if connected?(socket) do
      Pipeline.subscribe()
      :ok = ensure_x_rate_limit_table()
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, @x_admin_topic)
    end

    statuses = load_initial_statuses()
    flags = FeatureFlags.list_all()
    pipeline_status = safe_pipeline_status()
    pipeline_runs = Scouting.list_runs(limit: 10)
    todays_lineup_count = safe_lineup_count()

    {:ok,
     assign(socket,
       page_title: "Admin Panel",
       workers: @workers,
       statuses: statuses,
       active_tab: "workers",
       flags: flags,
       new_flag_key: "",
       new_flag_description: "",
       flag_error: nil,
       pipeline_status: pipeline_status,
       pipeline_runs: pipeline_runs,
       pipeline_logs: [],
       pipeline_player_statuses: %{},
       research_concurrency: 5,
       classification_concurrency: 5,
       selected_run_id: nil,
       todays_lineup_count: todays_lineup_count,
       agent_settings: [],
       agents_enabled: FeatureFlags.enabled?("news_agents_enabled"),
       query_clusters: [],
       chat_sessions_list: [],
       chatbot_enabled: FeatureFlags.enabled?("news_chatbot_enabled"),
       all_feeds: [],
       feed_research_stats: %{
         total_feeds: 0,
         researched_today: 0,
         pending_today: 0,
         total_players: 0
       },
       x_agent_enabled: FeatureFlags.enabled?("x_agent_enabled"),
       x_approval_required: FeatureFlags.enabled?("x_agent_approval_required"),
       x_outbound_enabled: FeatureFlags.enabled?("x_agent_outbound_replies_enabled"),
       x_today_mills: 0,
       x_daily_cap_mills: SpendLedger.daily_cap_mills(),
       x_pending_posts: [],
       x_recent_posts: [],
       x_watched_targets: [],
       x_circuit_state: :closed,
       x_status_message: nil
     )}
  end

  @impl true
  def terminate(_reason, _socket) do
    handler_id = "admin-live-#{inspect(self())}"
    :telemetry.detach(handler_id)
    :telemetry.detach("#{handler_id}-exception")
  end

  def handle_telemetry(event_name, measurements, metadata, %{pid: pid}) do
    worker = metadata.job.worker
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    state =
      case event_name do
        [:oban, :job, :exception] -> :failure
        _ -> Map.get(metadata, :state, :success)
      end

    send(pid, {:job_finished, worker, duration_ms, state})
  end

  @impl true
  def handle_event("trigger", %{"worker" => key}, socket) do
    worker_config = Enum.find(@workers, fn w -> w.key == key end)

    if worker_config do
      case %{} |> worker_config.module.new() |> Oban.insert() do
        {:ok, _job} ->
          statuses =
            Map.put(socket.assigns.statuses, key, %{
              state: :running,
              started_at: DateTime.utc_now(),
              duration_ms: nil
            })

          {:noreply, assign(socket, statuses: statuses)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to enqueue #{worker_config.label}.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket =
      case tab do
        "agents" ->
          all_settings = Agents.list_all_settings(limit: 50)

          assign(socket,
            agent_settings: all_settings,
            agents_enabled: FeatureFlags.enabled?("news_agents_enabled")
          )

        "queries" ->
          clusters = ChatBot.list_clusters(limit: 50)
          sessions = ChatBot.list_all_sessions(limit: 20)

          assign(socket,
            query_clusters: clusters,
            chat_sessions_list: sessions,
            chatbot_enabled: FeatureFlags.enabled?("news_chatbot_enabled")
          )

        "feeds" ->
          all_feeds = SportsFanatic.Feeds.list_all_feeds(limit: 100)
          stats = SportsFanatic.Feeds.feed_research_stats()

          assign(socket,
            all_feeds: all_feeds,
            feed_research_stats: stats
          )

        "x_agent" ->
          load_x_agent_state(socket)

        _ ->
          socket
      end

    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("run_feed_research", _params, socket) do
    case %{} |> SportsFanatic.Workers.FeedResearchWorker.new() |> Oban.insert() do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Feed research worker enqueued.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to enqueue feed research worker.")}
    end
  end

  def handle_event("toggle_flag", %{"key" => key}, socket) do
    flag = Enum.find(socket.assigns.flags, &(&1.key == key))

    if flag do
      if flag.enabled do
        FeatureFlags.disable(key)
      else
        FeatureFlags.enable(key)
      end

      {:noreply, assign(socket, flags: FeatureFlags.list_all(), flag_error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_new_flag", %{"key" => key, "description" => description}, socket) do
    {:noreply, assign(socket, new_flag_key: key, new_flag_description: description)}
  end

  def handle_event("create_flag", %{"key" => key, "description" => description}, socket) do
    key = String.trim(key)
    description = String.trim(description)

    if key == "" do
      {:noreply, assign(socket, flag_error: "Flag key is required.")}
    else
      case FeatureFlags.create(%{key: key, enabled: false, description: description}) do
        {:ok, _flag} ->
          {:noreply,
           assign(socket,
             flags: FeatureFlags.list_all(),
             new_flag_key: "",
             new_flag_description: "",
             flag_error: nil
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, flag_error: format_changeset_errors(changeset))}
      end
    end
  end

  def handle_event("delete_flag", %{"key" => key}, socket) do
    FeatureFlags.delete(key)
    {:noreply, assign(socket, flags: FeatureFlags.list_all(), flag_error: nil)}
  end

  def handle_event("run_all_agents", _params, socket) do
    case %{} |> SportsFanatic.Workers.RunNewsAgentsWorker.new() |> Oban.insert() do
      {:ok, _job} ->
        {:noreply, put_flash(socket, :info, "Agent execution enqueued.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to enqueue agent execution.")}
    end
  end

  def handle_event("toggle_agents_flag", _params, socket) do
    key = "news_agents_enabled"

    if FeatureFlags.enabled?(key) do
      case FeatureFlags.get(key) do
        nil -> :ok
        _flag -> FeatureFlags.disable(key)
      end
    else
      case FeatureFlags.get(key) do
        nil ->
          FeatureFlags.create(%{
            key: key,
            enabled: true,
            description: "Enable/disable news agent execution"
          })

        _flag ->
          FeatureFlags.enable(key)
      end
    end

    {:noreply,
     assign(socket,
       agents_enabled: FeatureFlags.enabled?(key),
       flags: FeatureFlags.list_all()
     )}
  end

  def handle_event("toggle_query_schedule", %{"cluster-id" => cluster_id}, socket) do
    case ChatBot.get_cluster(cluster_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Cluster not found.")}

      cluster ->
        new_scheduled = !cluster.scheduled
        new_freq = if new_scheduled, do: "daily", else: "disabled"

        case ChatBot.update_cluster(cluster, %{
               scheduled: new_scheduled,
               schedule_frequency: new_freq
             }) do
          {:ok, _} ->
            clusters = ChatBot.list_clusters(limit: 50)
            {:noreply, assign(socket, query_clusters: clusters)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update cluster.")}
        end
    end
  end

  def handle_event("set_query_frequency", %{"cluster-id" => cluster_id, "freq" => freq}, socket) do
    case ChatBot.get_cluster(cluster_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Cluster not found.")}

      cluster ->
        case ChatBot.update_cluster(cluster, %{schedule_frequency: freq}) do
          {:ok, _} ->
            clusters = ChatBot.list_clusters(limit: 50)
            {:noreply, assign(socket, query_clusters: clusters)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to update frequency.")}
        end
    end
  end

  def handle_event("run_query_now", %{"cluster-id" => cluster_id}, socket) do
    case ChatBot.get_cluster(cluster_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Cluster not found.")}

      cluster ->
        case %{"cluster_id" => cluster.id, "query" => cluster.representative_query}
             |> SportsFanatic.Workers.ScheduledExaSearchWorker.new()
             |> Oban.insert() do
          {:ok, _} ->
            {:noreply,
             put_flash(
               socket,
               :info,
               "Search enqueued for: #{String.slice(cluster.representative_query, 0, 50)}"
             )}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to enqueue search.")}
        end
    end
  end

  def handle_event("toggle_chatbot_flag", _params, socket) do
    key = "news_chatbot_enabled"

    if FeatureFlags.enabled?(key) do
      case FeatureFlags.get(key) do
        nil -> :ok
        _flag -> FeatureFlags.disable(key)
      end
    else
      case FeatureFlags.get(key) do
        nil ->
          FeatureFlags.create(%{
            key: key,
            enabled: true,
            description: "Enable/disable the news chatbot agent interface"
          })

        _flag ->
          FeatureFlags.enable(key)
      end
    end

    {:noreply,
     assign(socket,
       chatbot_enabled: FeatureFlags.enabled?(key),
       flags: FeatureFlags.list_all()
     )}
  end

  def handle_event("start_pipeline", _params, socket) do
    config = %{
      "research_concurrency" => socket.assigns.research_concurrency,
      "classification_concurrency" => socket.assigns.classification_concurrency
    }

    case Pipeline.start_pipeline(config) do
      {:ok, run} ->
        {:noreply,
         socket
         |> assign(
           pipeline_status: %{
             status: :running,
             run_id: run.id,
             total_players: run.total_players,
             processed_players: 0
           },
           pipeline_player_statuses: %{},
           pipeline_logs: []
         )
         |> put_flash(:info, "Scouting pipeline started.")}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "Pipeline is already running.")}

      {:error, :no_lineups_today} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No lineups for today — no games scheduled or lineups not yet fetched."
         )}

      {:error, :no_players} ->
        {:noreply, put_flash(socket, :error, "No players found in today's lineups.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start pipeline: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_pipeline", _params, socket) do
    case Pipeline.cancel_pipeline() do
      :ok ->
        {:noreply,
         socket
         |> assign(pipeline_status: %{status: :idle, run: nil})
         |> put_flash(:info, "Pipeline cancelled.")}

      {:error, :not_running} ->
        {:noreply, put_flash(socket, :error, "No pipeline is running.")}
    end
  end

  def handle_event("update_concurrency", %{"field" => "research", "value" => val}, socket) do
    {:noreply, assign(socket, research_concurrency: parse_concurrency(val))}
  end

  def handle_event("update_concurrency", %{"field" => "classification", "value" => val}, socket) do
    {:noreply, assign(socket, classification_concurrency: parse_concurrency(val))}
  end

  def handle_event("view_run", %{"run-id" => run_id}, socket) do
    logs = Scouting.list_logs_for_run(run_id)
    {:noreply, assign(socket, selected_run_id: run_id, pipeline_logs: logs)}
  end

  def handle_event("close_run_detail", _params, socket) do
    {:noreply, assign(socket, selected_run_id: nil, pipeline_logs: [])}
  end

  # ── X Agent tab ─────────────────────────────────────────────

  def handle_event("toggle_x_agent", %{"enabled" => enabled_str}, socket) do
    set_x_flag("x_agent_enabled", enabled_str == "true", socket, :x_agent_enabled)
  end

  def handle_event("toggle_x_approval", %{"required" => required_str}, socket) do
    set_x_flag("x_agent_approval_required", required_str == "true", socket, :x_approval_required)
  end

  def handle_event("toggle_x_outbound", %{"enabled" => enabled_str}, socket) do
    set_x_flag(
      "x_agent_outbound_replies_enabled",
      enabled_str == "true",
      socket,
      :x_outbound_enabled
    )
  end

  def handle_event("approve_post", %{"post_id" => post_id}, socket) do
    XContext.approve_post(post_id)
    {:noreply, load_x_agent_state(socket) |> put_flash(:info, "Post approved.")}
  end

  def handle_event("reject_post", %{"post_id" => post_id}, socket) do
    case Repo.get(Post, post_id) do
      nil ->
        {:noreply, socket}

      %Post{} = post ->
        post
        |> Post.changeset(%{status: "rejected"})
        |> Repo.update()

        {:noreply, load_x_agent_state(socket) |> put_flash(:info, "Post rejected.")}
    end
  end

  def handle_event("post_now", %{"type" => post_type}, socket)
      when post_type in ["top_hits", "injury", "team_magazine"] do
    if rate_limited?({:post_now, post_type}, 60_000) do
      {:noreply, put_flash(socket, :error, "Please wait before doing that again.")}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      actor = "joshua:#{System.system_time(:second)}"

      {:ok, post} =
        %Post{}
        |> Post.changeset(%{
          post_type: post_type,
          status: "pending",
          scheduled_at: now,
          main_body: "",
          context: %{actor: actor}
        })
        |> Repo.insert()

      %{"post_id" => post.id, "post_type" => post_type}
      |> SportsFanatic.Workers.MainPostWorker.new()
      |> Oban.insert()

      {:noreply, load_x_agent_state(socket) |> put_flash(:info, "Post enqueued.")}
    end
  end

  def handle_event("post_now", _params, socket) do
    {:noreply, put_flash(socket, :error, "Unknown post type.")}
  end

  def handle_event("reschedule_day", _params, socket) do
    if rate_limited?(:reschedule, 5 * 60_000) do
      {:noreply, put_flash(socket, :error, "Please wait before doing that again.")}
    else
      case %{} |> SportsFanatic.Workers.XPostSchedulerWorker.new() |> Oban.insert() do
        {:ok, _job} ->
          {:noreply, load_x_agent_state(socket) |> put_flash(:info, "Scheduler re-run enqueued.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to enqueue scheduler.")}
      end
    end
  end

  def handle_event("add_watched_target", %{"handle" => handle} = params, socket) do
    handle = handle |> String.trim() |> String.replace_prefix("@", "")

    if Regex.match?(~r/^[A-Za-z0-9_]{1,15}$/, handle) do
      focus = Map.get(params, "focus", "")

      %WatchedTarget{}
      |> WatchedTarget.changeset(%{handle: handle, focus: focus, enabled: true})
      |> Repo.insert(on_conflict: :nothing, conflict_target: :handle)

      {:noreply, load_x_agent_state(socket) |> put_flash(:info, "Watched target added.")}
    else
      {:noreply, put_flash(socket, :error, "Invalid X handle.")}
    end
  end

  def handle_event("remove_watched_target", %{"id" => id}, socket) do
    case Repo.get(WatchedTarget, id) do
      nil ->
        {:noreply, socket}

      %WatchedTarget{} = target ->
        Repo.delete(target)
        {:noreply, load_x_agent_state(socket) |> put_flash(:info, "Watched target removed.")}
    end
  end

  def handle_event("refresh_oauth", _params, socket) do
    case XContext.refresh_if_needed() do
      {:ok, _} ->
        {:noreply, assign(socket, x_status_message: "OAuth token refreshed.")}

      {:error, reason} ->
        {:noreply, assign(socket, x_status_message: "Refresh failed: #{inspect(reason)}")}
    end
  end

  def handle_event("connect_x_account", _params, socket) do
    {:noreply, push_navigate(socket, to: "/admin/x/oauth/start")}
  end

  @impl true
  def handle_info({:pipeline_started, payload}, socket) do
    {:noreply,
     assign(socket,
       pipeline_status: %{
         status: :running,
         run_id: payload.run_id,
         total_players: payload.total_players,
         processed_players: 0
       },
       pipeline_player_statuses: %{}
     )}
  end

  def handle_info({:player_started, payload}, socket) do
    player_statuses =
      Map.put(socket.assigns.pipeline_player_statuses, payload.player_id, %{
        name: payload.player_name,
        step: payload.step
      })

    {:noreply, assign(socket, pipeline_player_statuses: player_statuses)}
  end

  def handle_info({:player_completed, payload}, socket) do
    player_statuses = Map.delete(socket.assigns.pipeline_player_statuses, payload.player_id)

    pipeline_status =
      Map.merge(socket.assigns.pipeline_status, %{
        processed_players: payload.processed,
        total_players: payload.total
      })

    {:noreply,
     assign(socket, pipeline_player_statuses: player_statuses, pipeline_status: pipeline_status)}
  end

  def handle_info({:pipeline_completed, payload}, socket) do
    runs = Scouting.list_runs(limit: 10)

    {:noreply,
     socket
     |> assign(
       pipeline_status: %{status: :idle, run: nil},
       pipeline_player_statuses: %{},
       pipeline_runs: runs
     )
     |> put_flash(
       :info,
       "Pipeline completed. Processed #{payload.processed_players}/#{payload.total_players} players."
     )}
  end

  def handle_info({:pipeline_failed, payload}, socket) do
    runs = Scouting.list_runs(limit: 10)

    {:noreply,
     socket
     |> assign(
       pipeline_status: %{status: :idle, run: nil},
       pipeline_player_statuses: %{},
       pipeline_runs: runs
     )
     |> put_flash(:error, "Pipeline failed: #{payload.error}")}
  end

  def handle_info({:pipeline_cancelled, _payload}, socket) do
    runs = Scouting.list_runs(limit: 10)

    {:noreply,
     assign(socket,
       pipeline_status: %{status: :idle, run: nil},
       pipeline_player_statuses: %{},
       pipeline_runs: runs
     )}
  end

  def handle_info({:job_finished, worker_name, duration_ms, state}, socket) do
    key = worker_key_from_module(worker_name)

    if key do
      job_state = if state in [:success, "success"], do: :completed, else: :failed

      statuses =
        Map.put(socket.assigns.statuses, key, %{
          state: job_state,
          completed_at: DateTime.utc_now(),
          duration_ms: duration_ms
        })

      {:noreply, assign(socket, statuses: statuses)}
    else
      {:noreply, socket}
    end
  end

  # ── PubSub handlers for "admin:x_agent" topic ──────────────

  def handle_info({:post_state_change, _post}, socket) do
    {:noreply, load_x_agent_state(socket)}
  end

  def handle_info({:budget_exceeded, mills}, socket) do
    {:noreply,
     assign(socket,
       x_today_mills: mills,
       x_status_message: "Daily budget cap exceeded (#{mills} mills)."
     )}
  end

  def handle_info({:token_failure, reason}, socket) do
    {:noreply, assign(socket, x_status_message: "OAuth token failure: #{inspect(reason)}")}
  end

  def handle_info({:circuit_state_change, state}, socket) do
    {:noreply, assign(socket, x_circuit_state: state)}
  end

  def handle_info(:plan_updated, socket) do
    {:noreply, load_x_agent_state(socket)}
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  defp worker_key_from_module(worker_name) do
    worker_str = to_string(worker_name)

    case Enum.find(@workers, fn w -> inspect(w.module) == worker_str end) do
      %{key: key} -> key
      nil -> nil
    end
  end

  defp load_initial_statuses do
    worker_names = Enum.map(@workers, fn w -> inspect(w.module) end)

    query = """
    SELECT DISTINCT ON (worker) worker, state, completed_at, inserted_at,
      EXTRACT(EPOCH FROM (completed_at - attempted_at)) as duration_seconds
    FROM oban_jobs
    WHERE worker = ANY($1)
    ORDER BY worker, inserted_at DESC
    """

    case SQL.query(Repo, query, [worker_names]) do
      {:ok, %{rows: rows, columns: columns}} ->
        rows
        |> Enum.map(fn row -> columns |> Enum.zip(row) |> Map.new() end)
        |> Enum.reduce(%{}, &build_status_entry/2)

      {:error, _} ->
        %{}
    end
  end

  defp build_status_entry(row, acc) do
    case find_worker_key(row["worker"]) do
      nil -> acc
      key -> Map.put(acc, key, parse_worker_status(row))
    end
  end

  defp parse_worker_status(row) do
    %{
      state: parse_oban_state(row["state"]),
      completed_at: row["completed_at"],
      duration_ms: parse_duration_ms(row["duration_seconds"])
    }
  end

  defp parse_oban_state("completed"), do: :completed
  defp parse_oban_state("executing"), do: :running
  defp parse_oban_state("retryable"), do: :failed
  defp parse_oban_state("discarded"), do: :failed
  defp parse_oban_state(_), do: :idle

  defp parse_duration_ms(nil), do: nil

  defp parse_duration_ms(%Decimal{} = secs),
    do: secs |> Decimal.mult(1000) |> Decimal.round() |> Decimal.to_integer()

  defp parse_duration_ms(secs), do: round(secs * 1000)

  defp find_worker_key(worker_name) do
    case Enum.find(@workers, fn w -> inspect(w.module) == worker_name end) do
      %{key: key} -> key
      nil -> nil
    end
  end

  defp safe_lineup_count do
    Scouting.todays_lineup_player_count()
  rescue
    _ -> 0
  end

  defp safe_pipeline_status do
    case Process.whereis(SportsFanatic.Scouting.Pipeline) do
      nil -> %{status: :idle, run: nil}
      _pid -> Pipeline.get_status()
    end
  end

  defp parse_concurrency(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n >= 1 and n <= 20 -> n
      _ -> 5
    end
  end

  defp parse_concurrency(val) when is_integer(val), do: max(1, min(val, 20))
  defp parse_concurrency(_), do: 5

  defp pipeline_progress_pct(%{total_players: total, processed_players: processed})
       when total > 0 do
    round(processed / total * 100)
  end

  defp pipeline_progress_pct(_), do: 0

  defp step_label("research"), do: "Researching"
  defp step_label("classify"), do: "Classifying"
  defp step_label("generate"), do: "Generating"
  defp step_label(other), do: String.capitalize(to_string(other))

  defp run_status_color("completed"), do: "text-green-600"
  defp run_status_color("running"), do: "text-blue-600"
  defp run_status_color("failed"), do: "text-red-600"
  defp run_status_color("cancelled"), do: "text-yellow-600"
  defp run_status_color(_), do: "text-gray-600"

  defp log_status_icon("completed"), do: "bg-green-500"
  defp log_status_icon("started"), do: "bg-blue-500"
  defp log_status_icon("failed"), do: "bg-red-500"
  defp log_status_icon("skipped"), do: "bg-gray-400"
  defp log_status_icon(_), do: "bg-gray-400"

  defp status_for(statuses, key) do
    Map.get(statuses, key, %{state: :idle, completed_at: nil, duration_ms: nil})
  end

  defp format_duration(nil), do: ""
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp format_time(nil), do: "Never"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %H:%M:%S UTC")
  end

  defp format_time(%NaiveDateTime{} = ndt) do
    Calendar.strftime(ndt, "%b %d, %H:%M:%S UTC")
  end

  defp format_time(_), do: "Unknown"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold text-gray-900 mb-2">Admin Panel</h1>
      <p class="text-gray-500 mb-6">Manage workers and feature flags.</p>

      <%!-- Tab navigation --%>
      <div class="border-b border-gray-200 mb-8">
        <nav class="-mb-px flex space-x-8" aria-label="Tabs">
          <button
            phx-click="switch_tab"
            phx-value-tab="workers"
            class={[
              "py-3 px-1 border-b-2 font-medium text-sm transition",
              if(@active_tab == "workers",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Workers
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="scouting_pipeline"
            class={[
              "py-3 px-1 border-b-2 font-medium text-sm transition",
              if(@active_tab == "scouting_pipeline",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Scouting Pipeline
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="agents"
            class={[
              "py-3 px-1 border-b-2 font-medium text-sm transition",
              if(@active_tab == "agents",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Agents
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="queries"
            class={[
              "py-3 px-1 border-b-2 font-medium text-sm transition",
              if(@active_tab == "queries",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Queries
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="feeds"
            class={[
              "py-3 px-1 border-b-2 font-medium text-sm transition",
              if(@active_tab == "feeds",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Feeds
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="feature_flags"
            class={[
              "py-3 px-1 border-b-2 font-medium text-sm transition",
              if(@active_tab == "feature_flags",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            Feature Flags
            <span class="ml-2 bg-gray-100 text-gray-600 py-0.5 px-2 rounded-full text-xs">
              <%= length(@flags) %>
            </span>
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="x_agent"
            class={[
              "py-3 px-1 border-b-2 font-medium text-sm transition",
              if(@active_tab == "x_agent",
                do: "border-blue-500 text-blue-600",
                else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              )
            ]}
          >
            X Agent
          </button>
        </nav>
      </div>

      <%!-- Workers Tab --%>
      <%= if @active_tab == "workers" do %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for worker <- @workers do %>
            <% status = status_for(@statuses, worker.key) %>
            <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-5">
              <div class="flex items-center justify-between mb-3">
                <h3 class="font-semibold text-gray-900 text-sm"><%= worker.label %></h3>
                <span class={[
                  "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium",
                  status_badge_class(status.state)
                ]}>
                  <%= if status.state == :running do %>
                    <svg
                      class="animate-spin -ml-0.5 mr-1.5 h-3 w-3"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        class="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        stroke-width="4"
                      >
                      </circle>
                      <path
                        class="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                      >
                      </path>
                    </svg>
                  <% end %>
                  <%= status_label(status.state) %>
                </span>
              </div>

              <div class="text-xs text-gray-500 mb-3 space-y-1">
                <p>Last run: <%= format_time(status[:completed_at]) %></p>
                <%= if status[:duration_ms] do %>
                  <p>Duration: <%= format_duration(status[:duration_ms]) %></p>
                <% end %>
              </div>

              <button
                phx-click="trigger"
                phx-value-worker={worker.key}
                disabled={status.state == :running}
                class={[
                  "w-full px-3 py-2 text-sm font-medium rounded-md transition",
                  if(status.state == :running,
                    do: "bg-gray-100 text-gray-400 cursor-not-allowed",
                    else: "bg-blue-600 text-white hover:bg-blue-700"
                  )
                ]}
              >
                <%= if status.state == :running, do: "Running...", else: "Run" %>
              </button>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Scouting Pipeline Tab --%>
      <%= if @active_tab == "scouting_pipeline" do %>
        <div class="space-y-6">
          <%!-- Pipeline Controls --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-gray-900">Pipeline Controls</h3>
              <div class="flex items-center gap-2">
                <span class="text-sm text-gray-500">Today's lineup players:</span>
                <span class={[
                  "inline-flex items-center px-2.5 py-0.5 rounded-full text-sm font-semibold",
                  if(@todays_lineup_count > 0,
                    do: "bg-green-100 text-green-800",
                    else: "bg-yellow-100 text-yellow-800"
                  )
                ]}>
                  <%= @todays_lineup_count %>
                </span>
              </div>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Research Workers (1-20)
                </label>
                <input
                  type="number"
                  min="1"
                  max="20"
                  value={@research_concurrency}
                  phx-change="update_concurrency"
                  phx-value-field="research"
                  name="value"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                />
                <p class="mt-1 text-xs text-gray-400">Today's lineup players researched via Exa</p>
              </div>
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">
                  Classification Workers (1-20)
                </label>
                <input
                  type="number"
                  min="1"
                  max="20"
                  value={@classification_concurrency}
                  phx-change="update_concurrency"
                  phx-value-field="classification"
                  name="value"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                />
                <p class="mt-1 text-xs text-gray-400">AI classification calls per player</p>
              </div>
              <div class="flex items-end">
                <%= if @pipeline_status.status == :running do %>
                  <button
                    phx-click="cancel_pipeline"
                    class="w-full px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700 transition"
                  >
                    Cancel Pipeline
                  </button>
                <% else %>
                  <button
                    phx-click="start_pipeline"
                    class="w-full px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 transition"
                  >
                    Start Pipeline
                  </button>
                <% end %>
              </div>
            </div>

            <%!-- Live Progress --%>
            <%= if @pipeline_status.status == :running do %>
              <div class="border-t border-gray-200 pt-4">
                <div class="flex items-center justify-between mb-2">
                  <span class="text-sm font-medium text-gray-700">
                    Processing: <%= Map.get(@pipeline_status, :processed_players, 0) %> / <%= Map.get(
                      @pipeline_status,
                      :total_players,
                      0
                    ) %> players
                  </span>
                  <span class="text-sm text-gray-500">
                    <%= pipeline_progress_pct(@pipeline_status) %>%
                  </span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-2">
                  <div
                    class="bg-blue-600 h-2 rounded-full transition-all duration-300"
                    style={"width: #{pipeline_progress_pct(@pipeline_status)}%"}
                  >
                  </div>
                </div>

                <%!-- Active Players --%>
                <%= if map_size(@pipeline_player_statuses) > 0 do %>
                  <div class="mt-4">
                    <h4 class="text-sm font-medium text-gray-700 mb-2">Active Players</h4>
                    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-2">
                      <%= for {_id, player} <- @pipeline_player_statuses do %>
                        <div class="flex items-center gap-2 bg-blue-50 rounded px-3 py-2 text-sm">
                          <svg
                            class="animate-spin h-3 w-3 text-blue-500"
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                          >
                            <circle
                              class="opacity-25"
                              cx="12"
                              cy="12"
                              r="10"
                              stroke="currentColor"
                              stroke-width="4"
                            >
                            </circle>
                            <path
                              class="opacity-75"
                              fill="currentColor"
                              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                            >
                            </path>
                          </svg>
                          <span class="font-medium text-gray-800"><%= player.name %></span>
                          <span class="text-xs text-blue-600"><%= step_label(player.step) %></span>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Execution History --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-semibold text-gray-900">Execution History</h3>
            </div>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Started
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Players
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Config
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @pipeline_runs == [] do %>
                  <tr>
                    <td colspan="5" class="px-6 py-8 text-center text-gray-400 text-sm">
                      No pipeline runs yet. Click "Start Pipeline" to begin.
                    </td>
                  </tr>
                <% end %>
                <%= for run <- @pipeline_runs do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={"text-sm font-medium #{run_status_color(run.status)}"}>
                        <%= String.capitalize(run.status) %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= format_time(run.started_at || run.inserted_at) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= run.processed_players %>/<%= run.total_players %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      R:<%= get_in(run.config, ["research_concurrency"]) || "5" %> C:<%= get_in(
                        run.config,
                        ["classification_concurrency"]
                      ) || "5" %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-right text-sm">
                      <button
                        phx-click="view_run"
                        phx-value-run-id={run.id}
                        class="text-blue-600 hover:text-blue-800 font-medium"
                      >
                        View Logs
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%!-- Run Detail / Logs --%>
          <%= if @selected_run_id do %>
            <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold text-gray-900">Run Logs</h3>
                <button phx-click="close_run_detail" class="text-gray-400 hover:text-gray-600">
                  Close
                </button>
              </div>
              <div class="max-h-96 overflow-y-auto space-y-2">
                <%= if @pipeline_logs == [] do %>
                  <p class="text-sm text-gray-400">No log entries for this run.</p>
                <% end %>
                <%= for log <- @pipeline_logs do %>
                  <div class="flex items-start gap-3 py-2 border-b border-gray-100 last:border-0">
                    <div class={"mt-1.5 w-2 h-2 rounded-full flex-shrink-0 #{log_status_icon(log.status)}"}>
                    </div>
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center gap-2 text-xs text-gray-500">
                        <span class="font-medium text-gray-700"><%= log.step %></span>
                        <span><%= log.status %></span>
                        <span><%= format_time(log.inserted_at) %></span>
                      </div>
                      <p class="text-sm text-gray-600 mt-0.5 break-words"><%= log.message %></p>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <%!-- Agents Tab --%>
      <%= if @active_tab == "agents" do %>
        <div class="space-y-6">
          <%!-- Controls --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-gray-900">Agent Configuration</h3>
            </div>

            <div class="flex items-center gap-6 mb-4">
              <div class="flex items-center gap-3">
                <span class="text-sm font-medium text-gray-700">News Agents</span>
                <button
                  phx-click="toggle_agents_flag"
                  class={[
                    "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
                    if(@agents_enabled, do: "bg-blue-600", else: "bg-gray-200")
                  ]}
                  role="switch"
                  aria-checked={to_string(@agents_enabled)}
                >
                  <span class={[
                    "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                    if(@agents_enabled, do: "translate-x-5", else: "translate-x-0")
                  ]}>
                  </span>
                </button>
                <span class={[
                  "text-xs font-medium",
                  if(@agents_enabled, do: "text-blue-600", else: "text-gray-500")
                ]}>
                  <%= if @agents_enabled, do: "Enabled", else: "Disabled" %>
                </span>
              </div>

              <div class="text-sm text-gray-500">
                Schedule: Daily at 9:00 AM ET (13:00 UTC)
              </div>

              <button
                phx-click="run_all_agents"
                class="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700 transition"
              >
                Run All Agents Now
              </button>
            </div>
          </div>

          <%!-- All Users' Settings --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-semibold text-gray-900">
                All User Settings
                <span class="ml-2 text-sm font-normal text-gray-400">
                  (<%= length(@agent_settings) %>)
                </span>
              </h3>
            </div>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    User
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Prompt
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Created
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @agent_settings == [] do %>
                  <tr>
                    <td colspan="4" class="px-6 py-8 text-center text-gray-400 text-sm">
                      No agent settings found.
                    </td>
                  </tr>
                <% end %>
                <%= for setting <- @agent_settings do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                      <%= if setting.user, do: setting.user.email, else: "Unknown" %>
                    </td>
                    <td class="px-6 py-4 text-sm text-gray-800 max-w-md">
                      <p class="truncate" title={setting.raw_prompt}>
                        <%= String.slice(setting.raw_prompt, 0, 80) %>
                      </p>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{agent_setting_status_class(setting.status)}"}>
                        <%= setting.status %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= format_time(setting.inserted_at) %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>

      <%!-- Queries Tab --%>
      <%= if @active_tab == "queries" do %>
        <div class="space-y-6">
          <%!-- Chatbot Toggle --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-lg font-semibold text-gray-900">News Chatbot</h3>
                <p class="text-sm text-gray-500 mt-1">
                  Enable the agentic chatbot on the news feed page.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <button
                  phx-click="toggle_chatbot_flag"
                  class={[
                    "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
                    if(@chatbot_enabled, do: "bg-blue-600", else: "bg-gray-200")
                  ]}
                  role="switch"
                  aria-checked={to_string(@chatbot_enabled)}
                >
                  <span class={[
                    "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                    if(@chatbot_enabled, do: "translate-x-5", else: "translate-x-0")
                  ]}>
                  </span>
                </button>
                <span class={[
                  "text-sm font-medium",
                  if(@chatbot_enabled, do: "text-blue-600", else: "text-gray-500")
                ]}>
                  <%= if @chatbot_enabled, do: "Enabled", else: "Disabled" %>
                </span>
              </div>
            </div>
          </div>

          <%!-- Query Clusters --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-semibold text-gray-900">
                Query Clusters
                <span class="ml-2 text-sm font-normal text-gray-400">
                  (<%= length(@query_clusters) %>)
                </span>
              </h3>
            </div>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Query
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Count
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Entities
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Schedule
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Last Run
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @query_clusters == [] do %>
                  <tr>
                    <td colspan="6" class="px-6 py-8 text-center text-gray-400 text-sm">
                      No query clusters yet. Clusters are created automatically from user chat queries.
                    </td>
                  </tr>
                <% end %>
                <%= for cluster <- @query_clusters do %>
                  <tr>
                    <td class="px-6 py-4 text-sm text-gray-800 max-w-xs">
                      <p class="truncate" title={cluster.representative_query}>
                        <%= String.slice(cluster.representative_query, 0, 60) %>
                      </p>
                      <%= if cluster.topics != [] do %>
                        <div class="flex flex-wrap gap-1 mt-1">
                          <%= for topic <- Enum.take(cluster.topics, 5) do %>
                            <span class="text-xs px-1.5 py-0.5 rounded bg-gray-100 text-gray-600">
                              <%= topic %>
                            </span>
                          <% end %>
                        </div>
                      <% end %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600 font-medium">
                      <%= cluster.query_count %>
                    </td>
                    <td class="px-6 py-4 text-sm">
                      <div class="flex flex-wrap gap-1">
                        <%= for _pid <- Enum.take(cluster.entity_player_ids || [], 3) do %>
                          <span class="text-xs px-1.5 py-0.5 rounded bg-blue-50 text-blue-700">
                            Player
                          </span>
                        <% end %>
                        <%= for _tid <- Enum.take(cluster.entity_team_ids || [], 3) do %>
                          <span class="text-xs px-1.5 py-0.5 rounded bg-green-50 text-green-700">
                            Team
                          </span>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <div class="flex items-center gap-2">
                        <button
                          phx-click="toggle_query_schedule"
                          phx-value-cluster-id={cluster.id}
                          class={[
                            "relative inline-flex h-5 w-9 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out",
                            if(cluster.scheduled, do: "bg-blue-600", else: "bg-gray-200")
                          ]}
                          role="switch"
                        >
                          <span class={[
                            "pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                            if(cluster.scheduled, do: "translate-x-4", else: "translate-x-0")
                          ]}>
                          </span>
                        </button>
                        <%= if cluster.scheduled do %>
                          <select
                            phx-change="set_query_frequency"
                            phx-value-cluster-id={cluster.id}
                            name="freq"
                            class="text-xs border-gray-300 rounded py-0.5 px-1"
                          >
                            <option value="daily" selected={cluster.schedule_frequency == "daily"}>
                              Daily
                            </option>
                            <option value="hourly" selected={cluster.schedule_frequency == "hourly"}>
                              Hourly
                            </option>
                          </select>
                        <% end %>
                      </div>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= format_time(cluster.last_run_at) %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-right text-sm">
                      <button
                        phx-click="run_query_now"
                        phx-value-cluster-id={cluster.id}
                        class="text-blue-600 hover:text-blue-800 font-medium"
                      >
                        Run Now
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%!-- Chat Sessions --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-200">
              <h3 class="text-lg font-semibold text-gray-900">Recent Chat Sessions</h3>
            </div>
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    User
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Status
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Last Activity
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @chat_sessions_list == [] do %>
                  <tr>
                    <td colspan="3" class="px-6 py-8 text-center text-gray-400 text-sm">
                      No chat sessions yet.
                    </td>
                  </tr>
                <% end %>
                <%= for session <- @chat_sessions_list do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                      <%= if session.user, do: session.user.email, else: "Unknown" %>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <span class={"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium #{if session.status == "active", do: "bg-green-100 text-green-800", else: "bg-gray-100 text-gray-800"}"}>
                        <%= session.status %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      <%= format_time(session.last_activity_at) %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>

      <%!-- Feature Flags Tab --%>
      <%= if @active_tab == "feature_flags" do %>
        <div class="space-y-6">
          <%!-- Existing flags --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Flag Key
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Description
                  </th>
                  <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <%= if @flags == [] do %>
                  <tr>
                    <td colspan="4" class="px-6 py-8 text-center text-gray-400 text-sm">
                      No feature flags configured yet.
                    </td>
                  </tr>
                <% end %>
                <%= for flag <- @flags do %>
                  <tr>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <code class="text-sm font-mono bg-gray-100 px-2 py-1 rounded">
                        <%= flag.key %>
                      </code>
                    </td>
                    <td class="px-6 py-4 text-sm text-gray-600 max-w-md">
                      <p class="truncate" title={flag.description}>
                        <%= flag.description || "No description" %>
                      </p>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap">
                      <button
                        phx-click="toggle_flag"
                        phx-value-key={flag.key}
                        class={[
                          "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
                          if(flag.enabled, do: "bg-blue-600", else: "bg-gray-200")
                        ]}
                        role="switch"
                        aria-checked={to_string(flag.enabled)}
                      >
                        <span class={[
                          "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                          if(flag.enabled, do: "translate-x-5", else: "translate-x-0")
                        ]}>
                        </span>
                      </button>
                      <span class={[
                        "ml-2 text-xs font-medium",
                        if(flag.enabled, do: "text-blue-600", else: "text-gray-500")
                      ]}>
                        <%= if flag.enabled, do: "Enabled", else: "Disabled" %>
                      </span>
                    </td>
                    <td class="px-6 py-4 whitespace-nowrap text-right text-sm">
                      <button
                        phx-click="delete_flag"
                        phx-value-key={flag.key}
                        data-confirm={"Are you sure you want to delete the \"#{flag.key}\" flag?"}
                        class="text-red-600 hover:text-red-800 font-medium"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <%!-- Add new flag form --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">Add New Flag</h3>
            <%= if @flag_error do %>
              <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded-md text-sm text-red-700">
                <%= @flag_error %>
              </div>
            <% end %>
            <form phx-submit="create_flag" class="flex items-end gap-4">
              <div class="flex-1">
                <label for="flag-key" class="block text-sm font-medium text-gray-700 mb-1">
                  Key
                </label>
                <input
                  type="text"
                  id="flag-key"
                  name="key"
                  value={@new_flag_key}
                  phx-change="update_new_flag"
                  placeholder="my_feature_flag"
                  pattern="[a-z0-9_]+"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm font-mono"
                />
                <p class="mt-1 text-xs text-gray-400">
                  Lowercase letters, numbers, and underscores only.
                </p>
              </div>
              <div class="flex-[2]">
                <label for="flag-desc" class="block text-sm font-medium text-gray-700 mb-1">
                  Description
                </label>
                <input
                  type="text"
                  id="flag-desc"
                  name="description"
                  value={@new_flag_description}
                  phx-change="update_new_flag"
                  placeholder="What does this flag control?"
                  class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                />
              </div>
              <button
                type="submit"
                class="bg-blue-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-blue-700 transition whitespace-nowrap"
              >
                Add Flag
              </button>
            </form>
          </div>
        </div>
      <% end %>

      <%!-- Feeds Tab --%>
      <%= if @active_tab == "feeds" do %>
        <div class="space-y-6">
          <%!-- Research controls --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-5">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-gray-900">Feed Research</h3>
              <button
                phx-click="run_feed_research"
                class="bg-blue-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-blue-700 transition"
              >
                Run Now
              </button>
            </div>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
              <div class="bg-gray-50 rounded-lg p-3">
                <p class="text-xs text-gray-500 uppercase font-medium">Total Feeds</p>
                <p class="text-2xl font-bold text-gray-900">
                  <%= @feed_research_stats.total_feeds %>
                </p>
              </div>
              <div class="bg-gray-50 rounded-lg p-3">
                <p class="text-xs text-gray-500 uppercase font-medium">Total Players</p>
                <p class="text-2xl font-bold text-gray-900">
                  <%= @feed_research_stats.total_players %>
                </p>
              </div>
              <div class="bg-gray-50 rounded-lg p-3">
                <p class="text-xs text-gray-500 uppercase font-medium">Researched Today</p>
                <p class="text-2xl font-bold text-green-600">
                  <%= @feed_research_stats.researched_today %>
                </p>
              </div>
              <div class="bg-gray-50 rounded-lg p-3">
                <p class="text-xs text-gray-500 uppercase font-medium">Pending Today</p>
                <p class="text-2xl font-bold text-yellow-600">
                  <%= @feed_research_stats.pending_today %>
                </p>
              </div>
            </div>
            <p class="text-xs text-gray-400 mt-3">Schedule: Daily at 9:00 AM ET (13:00 UTC)</p>
          </div>

          <%!-- All feeds table --%>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-5">
            <h3 class="text-lg font-semibold text-gray-900 mb-4">All User Feeds</h3>
            <%= if @all_feeds == [] do %>
              <p class="text-gray-500 text-sm">No feeds created yet.</p>
            <% else %>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50">
                    <tr>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        User
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        Feed Name
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        Players
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        Teams
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        Active
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        Last Researched
                      </th>
                      <th class="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        Created
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-200">
                    <%= for feed <- @all_feeds do %>
                      <tr>
                        <td class="px-4 py-2 text-sm text-gray-700"><%= feed.user.email %></td>
                        <td class="px-4 py-2 text-sm font-medium text-gray-900"><%= feed.name %></td>
                        <td class="px-4 py-2 text-sm text-gray-600">
                          <%= length(feed.player_ids) %>
                        </td>
                        <td class="px-4 py-2 text-sm text-gray-600"><%= length(feed.team_ids) %></td>
                        <td class="px-4 py-2 text-sm">
                          <span class={if feed.is_active, do: "text-green-600", else: "text-gray-400"}>
                            <%= if feed.is_active, do: "Yes", else: "No" %>
                          </span>
                        </td>
                        <td class="px-4 py-2 text-sm text-gray-500">
                          <%= if feed.last_researched_at,
                            do: Calendar.strftime(feed.last_researched_at, "%Y-%m-%d %H:%M"),
                            else: "Never" %>
                        </td>
                        <td class="px-4 py-2 text-sm text-gray-500">
                          <%= Calendar.strftime(feed.inserted_at, "%Y-%m-%d") %>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- X Agent Tab --%>
      <%= if @active_tab == "x_agent" do %>
        <div class="space-y-6">
          <div class="bg-white rounded-lg border border-gray-200 p-5">
            <h2 class="text-lg font-semibold text-gray-900 mb-3">Status</h2>

            <div class="grid grid-cols-1 md:grid-cols-4 gap-4 text-sm">
              <div>
                <p class="text-gray-500 text-xs uppercase">Enabled</p>
                <p class="text-gray-900 font-medium">
                  <%= if @x_agent_enabled, do: "On", else: "Off" %>
                </p>
              </div>
              <div>
                <p class="text-gray-500 text-xs uppercase">Approval</p>
                <p class="text-gray-900 font-medium">
                  <%= if @x_approval_required, do: "Required", else: "Off" %>
                </p>
              </div>
              <div>
                <p class="text-gray-500 text-xs uppercase">Outbound</p>
                <p class="text-gray-900 font-medium">
                  <%= if @x_outbound_enabled, do: "On", else: "Off" %>
                </p>
              </div>
              <div>
                <p class="text-gray-500 text-xs uppercase">Today's Spend</p>
                <p class="text-gray-900 font-medium">
                  <%= @x_today_mills %> / <%= @x_daily_cap_mills %> mills
                </p>
              </div>
            </div>

            <div class="mt-4 flex flex-wrap gap-2 text-sm">
              <button
                phx-click="toggle_x_agent"
                phx-value-enabled={to_string(not @x_agent_enabled)}
                class="px-3 py-1 rounded bg-blue-600 text-white hover:bg-blue-700"
              >
                <%= if @x_agent_enabled, do: "Disable Agent", else: "Enable Agent" %>
              </button>
              <button
                phx-click="toggle_x_approval"
                phx-value-required={to_string(not @x_approval_required)}
                class="px-3 py-1 rounded bg-gray-200 text-gray-800 hover:bg-gray-300"
              >
                <%= if @x_approval_required, do: "Drop Approval", else: "Require Approval" %>
              </button>
              <button
                phx-click="toggle_x_outbound"
                phx-value-enabled={to_string(not @x_outbound_enabled)}
                class="px-3 py-1 rounded bg-gray-200 text-gray-800 hover:bg-gray-300"
              >
                <%= if @x_outbound_enabled, do: "Disable Outbound", else: "Enable Outbound" %>
              </button>
              <button
                phx-click="connect_x_account"
                class="px-3 py-1 rounded bg-indigo-600 text-white hover:bg-indigo-700"
              >
                Connect X
              </button>
              <button
                phx-click="refresh_oauth"
                class="px-3 py-1 rounded bg-gray-200 text-gray-800 hover:bg-gray-300"
              >
                Refresh Token
              </button>
              <button
                phx-click="reschedule_day"
                class="px-3 py-1 rounded bg-gray-200 text-gray-800 hover:bg-gray-300"
              >
                Reschedule Today
              </button>
            </div>

            <%= if @x_status_message do %>
              <p class="mt-3 text-sm text-amber-700"><%= @x_status_message %></p>
            <% end %>
          </div>

          <div class="bg-white rounded-lg border border-gray-200 p-5">
            <h2 class="text-lg font-semibold text-gray-900 mb-3">Approval Queue</h2>
            <%= if @x_pending_posts == [] do %>
              <p class="text-sm text-gray-500">No pending posts.</p>
            <% else %>
              <div class="space-y-3">
                <%= for post <- @x_pending_posts do %>
                  <div class="border border-gray-200 rounded-md p-3">
                    <div class="flex items-center justify-between text-xs text-gray-500 mb-1">
                      <span><%= post.post_type %></span>
                      <span>
                        <%= post.scheduled_at &&
                          Calendar.strftime(post.scheduled_at, "%Y-%m-%d %H:%M UTC") %>
                      </span>
                    </div>
                    <p class="text-sm text-gray-800 whitespace-pre-line"><%= post.main_body %></p>
                    <%= if post.reply_body do %>
                      <p class="mt-2 text-xs text-gray-600">Reply: <%= post.reply_body %></p>
                    <% end %>
                    <div class="mt-2 flex gap-2 text-xs">
                      <button
                        phx-click="approve_post"
                        phx-value-post_id={post.id}
                        class="px-2 py-1 rounded bg-emerald-600 text-white hover:bg-emerald-700"
                      >
                        Approve
                      </button>
                      <button
                        phx-click="reject_post"
                        phx-value-post_id={post.id}
                        class="px-2 py-1 rounded bg-rose-600 text-white hover:bg-rose-700"
                      >
                        Reject
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <div class="bg-white rounded-lg border border-gray-200 p-5">
            <h2 class="text-lg font-semibold text-gray-900 mb-3">Post Now</h2>
            <div class="flex gap-2 text-sm">
              <button
                phx-click="post_now"
                phx-value-type="top_hits"
                class="px-3 py-1 rounded bg-gray-200 text-gray-800 hover:bg-gray-300"
              >
                Top Hits
              </button>
              <button
                phx-click="post_now"
                phx-value-type="injury"
                class="px-3 py-1 rounded bg-gray-200 text-gray-800 hover:bg-gray-300"
              >
                Injury
              </button>
              <button
                phx-click="post_now"
                phx-value-type="team_magazine"
                class="px-3 py-1 rounded bg-gray-200 text-gray-800 hover:bg-gray-300"
              >
                Team Magazine
              </button>
            </div>
          </div>

          <div class="bg-white rounded-lg border border-gray-200 p-5">
            <h2 class="text-lg font-semibold text-gray-900 mb-3">Watched Targets</h2>

            <form phx-submit="add_watched_target" class="flex flex-wrap gap-2 mb-4 text-sm">
              <input
                type="text"
                name="handle"
                placeholder="@handle"
                class="border border-gray-300 rounded px-2 py-1"
              />
              <input
                type="text"
                name="focus"
                placeholder="focus (free text)"
                class="border border-gray-300 rounded px-2 py-1 flex-1"
              />
              <button type="submit" class="px-3 py-1 rounded bg-blue-600 text-white hover:bg-blue-700">
                Add
              </button>
            </form>

            <%= if @x_watched_targets == [] do %>
              <p class="text-sm text-gray-500">No watched targets.</p>
            <% else %>
              <ul class="divide-y divide-gray-100 text-sm">
                <%= for target <- @x_watched_targets do %>
                  <li class="flex items-center justify-between py-2">
                    <span>
                      @<%= target.handle %>
                      <%= if target.focus && target.focus != "" do %>
                        <span class="text-gray-500 ml-2"><%= target.focus %></span>
                      <% end %>
                    </span>
                    <button
                      phx-click="remove_watched_target"
                      phx-value-id={target.id}
                      class="text-xs text-rose-600 hover:underline"
                    >
                      Remove
                    </button>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>

          <div class="bg-white rounded-lg border border-gray-200 p-5">
            <h2 class="text-lg font-semibold text-gray-900 mb-3">Recent Posts</h2>
            <%= if @x_recent_posts == [] do %>
              <p class="text-sm text-gray-500">No posts yet.</p>
            <% else %>
              <ul class="divide-y divide-gray-100 text-sm">
                <%= for post <- @x_recent_posts do %>
                  <li class="py-2">
                    <div class="flex items-center justify-between text-xs text-gray-500">
                      <span><%= post.post_type %> · <%= post.status %></span>
                      <span>
                        <%= post.posted_at && Calendar.strftime(post.posted_at, "%Y-%m-%d %H:%M UTC") %>
                      </span>
                    </div>
                    <p class="text-gray-800 mt-1"><%= post.main_body %></p>
                  </li>
                <% end %>
              </ul>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp agent_setting_status_class("pending"), do: "bg-yellow-100 text-yellow-800"
  defp agent_setting_status_class("active"), do: "bg-green-100 text-green-800"
  defp agent_setting_status_class("running"), do: "bg-blue-100 text-blue-800"
  defp agent_setting_status_class("completed"), do: "bg-green-100 text-green-800"
  defp agent_setting_status_class("failed"), do: "bg-red-100 text-red-800"
  defp agent_setting_status_class("expired"), do: "bg-gray-100 text-gray-800"
  defp agent_setting_status_class(_), do: "bg-gray-100 text-gray-800"

  defp status_badge_class(:idle), do: "bg-gray-100 text-gray-700"
  defp status_badge_class(:running), do: "bg-blue-100 text-blue-700"
  defp status_badge_class(:completed), do: "bg-green-100 text-green-700"
  defp status_badge_class(:failed), do: "bg-red-100 text-red-700"

  # ── X agent helpers ─────────────────────────────────────────

  defp ensure_x_rate_limit_table do
    if :ets.whereis(@x_rate_limit_table) == :undefined do
      :ets.new(@x_rate_limit_table, [:named_table, :public, :set])
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp rate_limited?(key, window_ms) do
    ensure_x_rate_limit_table()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@x_rate_limit_table, key) do
      [{^key, last_at}] when now - last_at < window_ms ->
        true

      _ ->
        :ets.insert(@x_rate_limit_table, {key, now})
        false
    end
  end

  defp set_x_flag(key, value, socket, assign_key) do
    if value do
      FeatureFlags.enable(key)
    else
      FeatureFlags.disable(key)
    end

    {:noreply, assign(socket, assign_key, value)}
  end

  defp load_x_agent_state(socket) do
    pending =
      Repo.all(
        from p in Post,
          where: p.status == "pending",
          order_by: [asc: p.scheduled_at],
          limit: 20
      )

    recent =
      Repo.all(
        from p in Post,
          where: p.status in ["posted", "failed", "rejected"],
          order_by: [desc: p.updated_at],
          limit: 20
      )

    targets = Repo.all(from t in WatchedTarget, order_by: [asc: t.handle])

    assign(socket,
      x_agent_enabled: FeatureFlags.enabled?("x_agent_enabled"),
      x_approval_required: FeatureFlags.enabled?("x_agent_approval_required"),
      x_outbound_enabled: FeatureFlags.enabled?("x_agent_outbound_replies_enabled"),
      x_today_mills: SpendLedger.today_mills(),
      x_daily_cap_mills: SpendLedger.daily_cap_mills(),
      x_pending_posts: pending,
      x_recent_posts: recent,
      x_watched_targets: targets
    )
  end

  defp status_label(:idle), do: "Idle"
  defp status_label(:running), do: "Running"
  defp status_label(:completed), do: "Completed"
  defp status_label(:failed), do: "Failed"
end
