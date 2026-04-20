defmodule SportsFanaticWeb.AdminJobsLive do
  use SportsFanaticWeb, :live_view

  alias SportsFanatic.Repo

  @per_page 100

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Admin - Jobs",
       filter_worker: "",
       filter_state: "",
       expanded_job_id: nil,
       per_page: @per_page
     )
     |> load_jobs()}
  end

  @impl true
  def handle_event("filter", %{"worker" => worker, "state" => state}, socket) do
    {:noreply,
     socket
     |> assign(filter_worker: worker, filter_state: state)
     |> load_jobs()}
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    id = String.to_integer(id)

    new_expanded =
      if socket.assigns.expanded_job_id == id, do: nil, else: id

    {:noreply, assign(socket, expanded_job_id: new_expanded)}
  end

  @impl true
  def handle_event("retry_job", %{"id" => id}, socket) do
    id = String.to_integer(id)

    # Find the failed job and re-insert with same args
    result = Repo.query!("SELECT worker, args FROM public.oban_jobs WHERE id = $1", [id])

    case result.rows do
      [[worker, args]] ->
        # Insert a new job with the same worker and args
        Repo.query!(
          """
          INSERT INTO public.oban_jobs (state, queue, worker, args, max_attempts, inserted_at, scheduled_at)
          VALUES ('available', 'default', $1, $2, 3, now(), now())
          """,
          [worker, args]
        )

        {:noreply,
         put_flash(socket, :info, "Job retried: #{short_worker(worker)}") |> load_jobs()}

      _ ->
        {:noreply, put_flash(socket, :error, "Job not found")}
    end
  end

  defp load_jobs(socket) do
    %{filter_worker: filter_worker, filter_state: filter_state} = socket.assigns

    {where_clauses, params} = build_filters(filter_worker, filter_state)

    query = """
    SELECT id, worker, state, attempt, max_attempts, args,
           inserted_at, attempted_at, completed_at, errors
    FROM public.oban_jobs
    #{where_clauses}
    ORDER BY inserted_at DESC
    LIMIT $#{length(params) + 1}
    """

    result = Repo.query!(query, params ++ [@per_page])

    jobs =
      Enum.map(result.rows, fn [
                                 id,
                                 worker,
                                 state,
                                 attempt,
                                 max_attempts,
                                 args,
                                 inserted_at,
                                 attempted_at,
                                 completed_at,
                                 errors
                               ] ->
        %{
          id: id,
          worker: short_worker(worker),
          full_worker: worker,
          state: state,
          attempt: attempt,
          max_attempts: max_attempts,
          args: args,
          inserted_at: inserted_at,
          attempted_at: attempted_at,
          completed_at: completed_at,
          errors: errors || []
        }
      end)

    # Get distinct worker names for filter dropdown
    workers_result = Repo.query!("SELECT DISTINCT worker FROM public.oban_jobs ORDER BY worker")
    worker_names = Enum.map(workers_result.rows, fn [w] -> w end)

    assign(socket, jobs: jobs, worker_names: worker_names)
  end

  defp build_filters(filter_worker, filter_state) do
    clauses = []
    params = []
    idx = 1

    {clauses, params, idx} =
      if filter_worker != "" do
        {clauses ++ ["worker = $#{idx}"], params ++ [filter_worker], idx + 1}
      else
        {clauses, params, idx}
      end

    {clauses, params, _idx} =
      if filter_state != "" do
        {clauses ++ ["state = $#{idx}"], params ++ [filter_state], idx + 1}
      else
        {clauses, params, idx}
      end

    where =
      if clauses == [] do
        ""
      else
        "WHERE " <> Enum.join(clauses, " AND ")
      end

    {where, params}
  end

  defp short_worker(worker) do
    worker |> String.split(".") |> List.last()
  end

  defp format_timestamp(nil), do: "-"

  defp format_timestamp(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_timestamp(_), do: "-"

  defp state_badge_class(state) do
    case state do
      "completed" -> "bg-green-100 text-green-800"
      "available" -> "bg-blue-100 text-blue-800"
      "executing" -> "bg-yellow-100 text-yellow-800"
      "discarded" -> "bg-red-100 text-red-800"
      "retryable" -> "bg-orange-100 text-orange-800"
      "cancelled" -> "bg-gray-100 text-gray-800"
      "scheduled" -> "bg-purple-100 text-purple-800"
      _ -> "bg-gray-100 text-gray-600"
    end
  end

  defp truncate_error(errors) when is_list(errors) and length(errors) > 0 do
    errors
    |> List.last()
    |> case do
      %{"message" => msg} -> String.slice(to_string(msg), 0, 80)
      %{"error" => err} -> String.slice(to_string(err), 0, 80)
      err when is_binary(err) -> String.slice(err, 0, 80)
      err -> String.slice(inspect(err), 0, 80)
    end
  end

  defp truncate_error(_), do: nil

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
            <.link navigate="/admin/jobs" class="text-white text-sm font-medium">Jobs</.link>
          </div>
          <span class="text-xs text-yellow-400 font-medium">DEV ONLY - No auth</span>
        </div>
      </nav>

      <div class="max-w-7xl mx-auto px-6 py-8">
        <h1 class="text-2xl font-bold text-gray-900 mb-6">Job History</h1>

        <%!-- Filters --%>
        <form phx-change="filter" class="flex flex-wrap gap-4 mb-6">
          <select
            name="worker"
            class="rounded-lg border-gray-300 text-sm focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="">All Workers</option>
            <%= for w <- @worker_names do %>
              <option value={w} selected={@filter_worker == w}>
                <%= w |> String.split(".") |> List.last() %>
              </option>
            <% end %>
          </select>

          <select
            name="state"
            class="rounded-lg border-gray-300 text-sm focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="">All States</option>
            <%= for s <- ["available", "scheduled", "executing", "completed", "retryable", "discarded", "cancelled"] do %>
              <option value={s} selected={@filter_state == s}><%= s %></option>
            <% end %>
          </select>
        </form>

        <%!-- Jobs Table --%>
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">ID</th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Worker
                </th>
                <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                  State
                </th>
                <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                  Attempt
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Inserted
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Attempted
                </th>
                <th class="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">Error</th>
                <th class="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100">
              <%= for job <- @jobs do %>
                <tr class="hover:bg-gray-50">
                  <td class="px-4 py-3 text-sm text-gray-500"><%= job.id %></td>
                  <td class="px-4 py-3 text-sm font-medium text-gray-900"><%= job.worker %></td>
                  <td class="px-4 py-3 text-center">
                    <span class={"px-2 py-1 text-xs font-medium rounded-full #{state_badge_class(job.state)}"}>
                      <%= job.state %>
                    </span>
                  </td>
                  <td class="px-4 py-3 text-sm text-center text-gray-600">
                    <%= job.attempt %>/<%= job.max_attempts %>
                  </td>
                  <td class="px-4 py-3 text-xs text-gray-500">
                    <%= format_timestamp(job.inserted_at) %>
                  </td>
                  <td class="px-4 py-3 text-xs text-gray-500">
                    <%= format_timestamp(job.attempted_at) %>
                  </td>
                  <td class="px-4 py-3 text-xs text-gray-500 max-w-xs truncate">
                    <%= if truncate_error(job.errors) do %>
                      <button
                        phx-click="toggle_expand"
                        phx-value-id={job.id}
                        class="text-left text-red-600 hover:text-red-800 cursor-pointer"
                      >
                        <%= truncate_error(job.errors) %>...
                      </button>
                    <% end %>
                  </td>
                  <td class="px-4 py-3 text-center">
                    <%= if job.state in ["discarded", "retryable"] do %>
                      <button
                        phx-click="retry_job"
                        phx-value-id={job.id}
                        class="text-xs bg-blue-100 text-blue-700 px-2 py-1 rounded hover:bg-blue-200 transition"
                      >
                        Retry
                      </button>
                    <% end %>
                  </td>
                </tr>
                <%!-- Expandable error details --%>
                <%= if @expanded_job_id == job.id && job.errors != [] do %>
                  <tr>
                    <td colspan="8" class="px-4 py-3 bg-red-50">
                      <div class="text-xs text-red-800 font-mono whitespace-pre-wrap max-h-48 overflow-y-auto">
                        <%= inspect(job.errors, pretty: true, limit: :infinity) %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              <% end %>
              <%= if @jobs == [] do %>
                <tr>
                  <td colspan="8" class="px-4 py-6 text-sm text-gray-500 text-center">
                    No jobs found
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <p class="text-xs text-gray-400 mt-4">Showing up to <%= @per_page %> most recent jobs</p>
      </div>
    </div>
    """
  end
end
