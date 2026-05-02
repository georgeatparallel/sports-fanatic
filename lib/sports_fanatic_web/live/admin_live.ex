defmodule SportsFanaticWeb.AdminLive do
  use SportsFanaticWeb, :live_view

  alias Ecto.Adapters.SQL
  alias SportsFanatic.FeatureFlags
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
    flags = FeatureFlags.list_all()

    {:ok,
     assign(socket,
       page_title: "Admin Panel",
       workers: @workers,
       statuses: statuses,
       active_tab: "workers",
       flags: flags,
       new_flag_key: "",
       new_flag_description: "",
       flag_error: nil
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
    {:noreply, assign(socket, active_tab: tab)}
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

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  def handle_event("delete_flag", %{"key" => key}, socket) do
    FeatureFlags.delete(key)
    {:noreply, assign(socket, flags: FeatureFlags.list_all(), flag_error: nil)}
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

  defp parse_duration_ms(%Decimal{} = secs),
    do: secs |> Decimal.mult(1000) |> Decimal.round() |> Decimal.to_integer()

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
