defmodule SportsFanaticWeb.AdminDashboardLive do
  use SportsFanaticWeb, :live_view

  alias SportsFanatic.Repo

  @refresh_interval 10_000

  @worker_modules %{
    "FetchScheduleWorker" => SportsFanatic.Workers.FetchScheduleWorker,
    "FetchLineupsWorker" => SportsFanatic.Workers.FetchLineupsWorker,
    "FetchNewsWorker" => SportsFanatic.Workers.FetchNewsWorker,
    "GeneratePredictionsWorker" => SportsFanatic.Workers.GeneratePredictionsWorker,
    "GenerateScoutingWorker" => SportsFanatic.Workers.GenerateScoutingWorker,
    "GeneratePlayerSeoWorker" => SportsFanatic.Workers.GeneratePlayerSeoWorker,
    "GenerateGameDayWorker" => SportsFanatic.Workers.GenerateGameDayWorker,
    "WarmCacheWorker" => SportsFanatic.Workers.WarmCacheWorker,
    "GenerateSitemapWorker" => SportsFanatic.Workers.GenerateSitemapWorker,
    "CleanupWorker" => SportsFanatic.Workers.CleanupWorker
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh, @refresh_interval)
    end

    {:ok, assign(socket, page_title: "Admin Dashboard") |> load_data()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_interval)
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("trigger_worker", %{"worker" => worker_name}, socket) do
    case Map.get(@worker_modules, worker_name) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown worker: #{worker_name}")}

      module ->
        case %{} |> module.new() |> Oban.insert() do
          {:ok, _job} ->
            {:noreply,
             put_flash(socket, :info, "#{worker_name} enqueued successfully") |> load_data()}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to enqueue #{worker_name}: #{inspect(reason)}")}
        end
    end
  end

  defp load_data(socket) do
    assign(socket,
      db_stats: fetch_db_stats(),
      oban_stats: fetch_oban_stats()
    )
  end

  defp fetch_db_stats do
    # Count records from each major table
    [
      {"Teams", count_table("teams", "public")},
      {"Players", count_table("players", "public")},
      {"News Items", count_table("news_items", "content")},
      {"Lineups (today)", count_today_lineups()},
      {"Scouting Reports", count_table("scouting_reports", "content")},
      {"Game Day Magazines", count_table("game_day_magazines", "content")},
      {"Player Daily Content", count_table("player_daily_content", "content")}
    ]
  end

  defp count_table(table, prefix) do
    result = Repo.query!("SELECT count(*) FROM #{prefix}.#{table}")
    [[count]] = result.rows
    count
  end

  defp count_today_lineups do
    today = Date.utc_today() |> Date.to_iso8601()
    result = Repo.query!("SELECT count(*) FROM mlb.lineups WHERE game_date = $1", [today])
    [[count]] = result.rows
    count
  end

  defp fetch_oban_stats do
    cutoff = DateTime.utc_now() |> DateTime.add(-86_400, :second)

    result =
      Repo.query!(
        """
        SELECT
          worker,
          state,
          count(*)::integer as cnt
        FROM public.oban_jobs
        WHERE inserted_at > $1
        GROUP BY worker, state
        ORDER BY worker, state
        """,
        [cutoff]
      )

    result.rows
    |> Enum.group_by(fn [worker, _state, _cnt] -> worker end)
    |> Enum.map(fn {worker, rows} ->
      states =
        rows
        |> Enum.map(fn [_w, state, cnt] -> {state, cnt} end)
        |> Map.new()

      short_name = worker |> String.split(".") |> List.last()

      %{
        worker: short_name,
        full_worker: worker,
        available: Map.get(states, "available", 0),
        executing: Map.get(states, "executing", 0),
        completed: Map.get(states, "completed", 0),
        discarded: Map.get(states, "discarded", 0),
        retryable: Map.get(states, "retryable", 0)
      }
    end)
    |> Enum.sort_by(& &1.worker)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100">
      <%!-- Admin Nav --%>
      <nav class="bg-gray-900 text-white px-6 py-3">
        <div class="max-w-7xl mx-auto flex items-center justify-between">
          <div class="flex items-center gap-6">
            <span class="font-bold text-lg">Sports Fan Agent Admin</span>
            <.link navigate="/admin" class="text-gray-300 hover:text-white text-sm font-medium">
              Dashboard
            </.link>
            <.link navigate="/admin/jobs" class="text-gray-300 hover:text-white text-sm font-medium">
              Jobs
            </.link>
          </div>
          <span class="text-xs text-yellow-400 font-medium">DEV ONLY - No auth</span>
        </div>
      </nav>

      <div class="max-w-7xl mx-auto px-6 py-8">
        <h1 class="text-2xl font-bold text-gray-900 mb-6">Dashboard</h1>

        <%!-- DB Stats Grid --%>
        <section class="mb-8">
          <h2 class="text-lg font-semibold text-gray-700 mb-3">Database Stats</h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
            <%= for {label, count} <- @db_stats do %>
              <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
                <p class="text-sm text-gray-500"><%= label %></p>
                <p class="text-2xl font-bold text-gray-900 mt-1"><%= count %></p>
              </div>
            <% end %>
          </div>
        </section>

        <%!-- Oban Worker Status --%>
        <section class="mb-8">
          <h2 class="text-lg font-semibold text-gray-700 mb-3">Oban Workers (Last 24h)</h2>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-x-auto">
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                    Worker
                  </th>
                  <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                    Available
                  </th>
                  <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                    Executing
                  </th>
                  <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                    Completed
                  </th>
                  <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                    Discarded
                  </th>
                  <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                    Retryable
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-100">
                <%= for stat <- @oban_stats do %>
                  <tr class="hover:bg-gray-50">
                    <td class="px-4 py-3 text-sm font-medium text-gray-900"><%= stat.worker %></td>
                    <td class="px-4 py-3 text-sm text-center text-gray-600"><%= stat.available %></td>
                    <td class="px-4 py-3 text-sm text-center">
                      <span class={
                        if stat.executing > 0, do: "text-blue-600 font-medium", else: "text-gray-400"
                      }>
                        <%= stat.executing %>
                      </span>
                    </td>
                    <td class="px-4 py-3 text-sm text-center text-green-600">
                      <%= stat.completed %>
                    </td>
                    <td class="px-4 py-3 text-sm text-center">
                      <span class={
                        if stat.discarded > 0, do: "text-red-600 font-medium", else: "text-gray-400"
                      }>
                        <%= stat.discarded %>
                      </span>
                    </td>
                    <td class="px-4 py-3 text-sm text-center">
                      <span class={
                        if stat.retryable > 0,
                          do: "text-yellow-600 font-medium",
                          else: "text-gray-400"
                      }>
                        <%= stat.retryable %>
                      </span>
                    </td>
                  </tr>
                <% end %>
                <%= if @oban_stats == [] do %>
                  <tr>
                    <td colspan="6" class="px-4 py-6 text-sm text-gray-500 text-center">
                      No jobs in the last 24 hours
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>

        <%!-- Trigger Workers --%>
        <section>
          <h2 class="text-lg font-semibold text-gray-700 mb-3">Trigger Workers</h2>
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
            <%= for {name, _module} <- Enum.sort(@worker_modules) do %>
              <button
                phx-click="trigger_worker"
                phx-value-worker={name}
                class="bg-white border border-gray-300 rounded-lg px-3 py-2 text-sm font-medium text-gray-700 hover:bg-blue-50 hover:border-blue-300 hover:text-blue-700 transition shadow-sm"
              >
                <%= name
                |> String.replace("Worker", "")
                |> String.replace(~r/([A-Z])/, " \\1")
                |> String.trim() %>
              </button>
            <% end %>
          </div>
        </section>

        <p class="text-xs text-gray-400 mt-8">Auto-refreshes every 10 seconds</p>
      </div>
    </div>
    """
  end
end
