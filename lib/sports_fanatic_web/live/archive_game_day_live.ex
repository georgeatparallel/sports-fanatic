defmodule SportsFanaticWeb.ArchiveGameDayLive do
  use SportsFanaticWeb, :live_view

  import Ecto.Query
  alias SportsFanatic.Content.GameDayMagazine
  alias SportsFanatic.Repo

  @impl true
  def mount(_params, _session, socket) do
    magazines =
      GameDayMagazine
      |> where([m], m.status == "published")
      |> preload([:away_team, :home_team])
      |> order_by([m], desc: m.game_date)
      |> limit(50)
      |> Repo.all()

    {:ok,
     assign(socket,
       page_title: "Game Day Magazine Archive",
       magazines: magazines
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold text-gray-900 mb-6">Game Day Magazine Archive</h1>

      <div class="space-y-3">
        <%= for mag <- @magazines do %>
          <.link
            navigate={"/premium/game-day/#{Date.to_iso8601(mag.game_date)}/#{mag.slug}"}
            class="block bg-white rounded-lg shadow-sm border border-gray-100 p-4 hover:border-blue-300 transition"
          >
            <div class="flex justify-between items-center">
              <div>
                <span class="font-semibold text-gray-900"><%= mag.headline %></span>
              </div>
              <span class="text-sm text-gray-400">
                <%= Calendar.strftime(mag.game_date, "%b %d, %Y") %>
              </span>
            </div>
            <p class="text-sm text-gray-500 mt-1">
              <%= mag.away_team.name %> vs <%= mag.home_team.name %>
            </p>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end
end
