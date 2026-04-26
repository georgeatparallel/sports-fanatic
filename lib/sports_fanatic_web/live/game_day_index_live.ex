defmodule SportsFanaticWeb.GameDayIndexLive do
  use SportsFanaticWeb, :live_view

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Content.GameDayMagazine

  @impl true
  def mount(%{"date" => date_str}, _session, socket) do
    date = Date.from_iso8601!(date_str)

    magazines =
      from(m in GameDayMagazine,
        where: m.game_date == ^date and m.status == "published",
        preload: [:away_team, :home_team],
        order_by: m.inserted_at
      )
      |> Repo.all()

    {:ok,
     assign(socket,
       page_title: "Game Day Magazines - #{Calendar.strftime(date, "%B %d, %Y")}",
       magazines: magazines,
       date: date,
       date_str: date_str
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold text-gray-900 mb-6">
        Game Day Magazines - <%= Calendar.strftime(@date, "%B %d, %Y") %>
      </h1>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <%= for mag <- @magazines do %>
          <.link
            navigate={"/premium/game-day/#{@date_str}/#{mag.slug}"}
            class="block bg-white rounded-xl shadow-sm border border-gray-200 hover:border-blue-300 hover:shadow-md transition overflow-hidden"
          >
            <div class="bg-gradient-to-r from-slate-800 to-blue-900 text-white p-6">
              <h2 class="text-xl font-bold"><%= mag.headline %></h2>
              <%= if mag.subheadline do %>
                <p class="text-blue-200 text-sm mt-1"><%= mag.subheadline %></p>
              <% end %>
            </div>
            <div class="p-4">
              <div class="flex justify-between text-sm text-gray-600">
                <span><%= mag.away_team.name %></span>
                <span class="font-bold">vs</span>
                <span><%= mag.home_team.name %></span>
              </div>
            </div>
          </.link>
        <% end %>
      </div>

      <%= if Enum.empty?(@magazines) do %>
        <p class="text-gray-500 text-center py-8">No Game Day Magazines available for this date.</p>
      <% end %>
    </div>
    """
  end
end
