defmodule SportsFanaticWeb.DashboardLive do
  use SportsFanaticWeb, :live_view

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{ScheduledGame, Pick, HrPick}

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    games =
      from(sg in ScheduledGame,
        where: sg.game_date == ^today,
        order_by: sg.game_datetime
      )
      |> Repo.all()

    top_picks =
      from(p in Pick,
        where: p.prediction_date == ^today and p.prediction == "Hit",
        order_by: [desc: p.confidence],
        limit: 10
      )
      |> Repo.all()

    top_hr_picks =
      from(hp in HrPick,
        where: hp.prediction_date == ^today,
        order_by: [desc: hp.hr_probability],
        limit: 10
      )
      |> Repo.all()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "games:live")
    end

    {:ok,
     assign(socket,
       page_title: "Premium Dashboard",
       games: games,
       top_picks: top_picks,
       top_hr_picks: top_hr_picks,
       today: today
     )}
  end

  @impl true
  def handle_info({:game_update, game}, socket) do
    games =
      Enum.map(socket.assigns.games, fn g ->
        if g.game_id == game.game_id, do: game, else: g
      end)

    {:noreply, assign(socket, games: games)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold text-gray-900 mb-6">Premium Dashboard</h1>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2">
          <h2 class="text-xl font-semibold text-gray-900 mb-4">Today's Games</h2>
          <div class="space-y-3">
            <%= for game <- @games do %>
              <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
                <div class="flex justify-between items-center">
                  <div class="font-medium text-gray-900">
                    <%= game.away_name %> @ <%= game.home_name %>
                  </div>
                  <span class="text-sm text-gray-500"><%= game.status %></span>
                </div>
                <p class="text-sm text-gray-500 mt-1"><%= game.venue_name %></p>
                <div class="mt-2">
                  <.link
                    navigate={"/premium/game-day/#{Date.to_iso8601(@today)}/#{generate_slug(game)}"}
                    class="text-blue-600 text-sm hover:text-blue-800"
                  >
                    View Game Day Magazine &rarr;
                  </.link>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <aside>
          <h2 class="text-xl font-semibold text-gray-900 mb-4">Top Hit Predictions</h2>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4 mb-6">
            <%= for pick <- @top_picks do %>
              <div class="flex justify-between items-center py-2 border-b border-gray-100 last:border-0">
                <span class="font-medium text-sm"><%= pick.player_name %></span>
                <span class="text-green-600 font-bold text-sm">
                  <%= Float.round(pick.confidence * 100, 1) %>%
                </span>
              </div>
            <% end %>
          </div>

          <h2 class="text-xl font-semibold text-gray-900 mb-4">Top HR Picks</h2>
          <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
            <%= for pick <- @top_hr_picks do %>
              <div class="flex justify-between items-center py-2 border-b border-gray-100 last:border-0">
                <span class="font-medium text-sm"><%= pick.player_name %></span>
                <div class="flex items-center gap-2">
                  <span class="text-purple-600 font-bold text-sm">
                    <%= Float.round(pick.hr_probability * 100, 1) %>%
                  </span>
                  <span class={"px-1.5 py-0.5 text-xs rounded #{case pick.confidence_tier do
                    "A" -> "bg-green-100 text-green-700"
                    "B" -> "bg-yellow-100 text-yellow-700"
                    _ -> "bg-gray-100 text-gray-700"
                  end}"}>
                    <%= pick.confidence_tier %>
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </aside>
      </div>

      <div class="mt-8 flex gap-4">
        <.link
          navigate="/premium/archive/scouting"
          class="text-blue-600 hover:text-blue-800 font-medium"
        >
          Scouting Archives &rarr;
        </.link>
        <.link
          navigate="/premium/archive/game-day"
          class="text-blue-600 hover:text-blue-800 font-medium"
        >
          Game Day Archives &rarr;
        </.link>
      </div>
    </div>
    """
  end

  defp generate_slug(game) do
    away =
      String.downcase(game.away_name || "")
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    home =
      String.downcase(game.home_name || "")
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    "#{away}-vs-#{home}"
  end
end
