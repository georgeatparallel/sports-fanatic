defmodule SportsFanaticWeb.ArchiveScoutingLive do
  use SportsFanaticWeb, :live_view

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Mlb.{Player, Team}

  @impl true
  def mount(_params, _session, socket) do
    reports =
      from(sr in ScoutingReport,
        join: p in Player,
        on: sr.player_id == p.id,
        join: t in Team,
        on: p.team_id == t.id,
        select: %{report: sr, player: p, team: t},
        order_by: [desc: sr.report_date],
        limit: 50
      )
      |> Repo.all()

    {:ok,
     assign(socket,
       page_title: "Scouting Report Archive",
       reports: reports
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold text-gray-900 mb-6">Scouting Report Archive</h1>

      <div class="space-y-3">
        <%= for %{report: report, player: player, team: team} <- @reports do %>
          <.link navigate={"/premium/scouting/#{team.slug}/#{player.slug}"}
            class="block bg-white rounded-lg shadow-sm border border-gray-100 p-4 hover:border-blue-300 transition">
            <div class="flex justify-between items-center">
              <div>
                <span class="font-semibold text-gray-900"><%= player.full_name %></span>
                <span class="text-gray-500 text-sm ml-2"><%= team.name %></span>
              </div>
              <div class="flex items-center gap-3">
                <span class="text-xl font-bold text-blue-600"><%= report.overall_grade %></span>
                <span class="text-sm text-gray-400"><%= Calendar.strftime(report.report_date, "%b %d") %></span>
              </div>
            </div>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end
end
