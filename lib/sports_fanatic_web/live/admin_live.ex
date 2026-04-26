defmodule SportsFanaticWeb.AdminLive do
  use SportsFanaticWeb, :live_view

  alias Ecto.Adapters.SQL
  alias SportsFanatic.Repo
  require Logger

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

    statuses = load_initial_statuses()

    {:ok,
     assign(socket,
       page_title: "Admin Panel",
       workers: @workers,
       statuses: statuses
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

  @impl true
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
  defp parse_duration_ms(secs), do: round(secs * 1000)

  defp find_worker_key(worker_name) do
    case Enum.find(@workers, fn w -> inspect(w.module) == worker_name end) do
      %{key: key} -> key
      nil -> nil
    end
  end

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
      <p class="text-gray-500 mb-8">Manually trigger and monitor background workers.</p>

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
    </div>
    """
  end

  defp status_badge_class(:idle), do: "bg-gray-100 text-gray-700"
  defp status_badge_class(:running), do: "bg-blue-100 text-blue-700"
  defp status_badge_class(:completed), do: "bg-green-100 text-green-700"
  defp status_badge_class(:failed), do: "bg-red-100 text-red-700"

  defp status_label(:idle), do: "Idle"
  defp status_label(:running), do: "Running"
  defp status_label(:completed), do: "Completed"
  defp status_label(:failed), do: "Failed"
end
