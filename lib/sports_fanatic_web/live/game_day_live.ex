defmodule SportsFanaticWeb.GameDayLive do
  use SportsFanaticWeb, :live_view

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Content.GameDayMagazine

  @impl true
  def mount(%{"date" => date_str, "slug" => slug}, _session, socket) do
    date = Date.from_iso8601!(date_str)

    magazine =
      from(m in GameDayMagazine,
        where: m.game_date == ^date and m.slug == ^slug,
        preload: [:away_team, :home_team]
      )
      |> Repo.one!()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "game:#{magazine.game_id}")
    end

    {:ok,
     assign(socket,
       page_title: magazine.headline,
       magazine: magazine,
       date: date
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto px-4 py-8">
      <%!-- Magazine Header -- styled as digital ballpark program --%>
      <header class="bg-gradient-to-br from-slate-900 via-blue-900 to-indigo-900 text-white rounded-2xl p-10 mb-8 relative overflow-hidden">
        <div class="absolute top-0 right-0 w-64 h-64 bg-white/5 rounded-full -translate-y-1/2 translate-x-1/2"></div>
        <p class="text-blue-300 text-sm font-bold uppercase tracking-widest mb-3">Game Day Magazine</p>
        <h1 class="text-4xl font-bold mb-2 relative"><%= @magazine.headline %></h1>
        <%= if @magazine.subheadline do %>
          <p class="text-blue-200 text-xl"><%= @magazine.subheadline %></p>
        <% end %>
        <div class="flex gap-6 mt-6 text-sm text-blue-200">
          <span><%= Calendar.strftime(@date, "%B %d, %Y") %></span>
        </div>
      </header>

      <%!-- Teams matchup --%>
      <div class="grid grid-cols-2 gap-1 mb-8">
        <div class="bg-white rounded-l-xl shadow-sm border border-gray-200 p-8 text-center">
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-2">Away</p>
          <h2 class="text-2xl font-bold text-gray-900"><%= @magazine.away_team.name %></h2>
          <p class="text-lg text-gray-600 mt-1"><%= get_in(@magazine.away_pitcher, ["name"]) || "TBD" %></p>
        </div>
        <div class="bg-white rounded-r-xl shadow-sm border border-gray-200 p-8 text-center">
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-2">Home</p>
          <h2 class="text-2xl font-bold text-gray-900"><%= @magazine.home_team.name %></h2>
          <p class="text-lg text-gray-600 mt-1"><%= get_in(@magazine.home_pitcher, ["name"]) || "TBD" %></p>
        </div>
      </div>

      <%!-- Matchup Analysis --%>
      <section class="bg-white rounded-xl shadow-sm border border-gray-200 p-8 mb-8">
        <h2 class="text-2xl font-bold text-gray-900 mb-4 flex items-center gap-2">
          <span class="w-1 h-6 bg-blue-600 rounded-full"></span>
          Matchup Analysis
        </h2>
        <div class="text-gray-700 leading-relaxed prose max-w-none">
          <%= for paragraph <- String.split(@magazine.matchup_analysis || "", "\n", trim: true) do %>
            <p><%= paragraph %></p>
          <% end %>
        </div>
      </section>

      <%!-- Weather Impact --%>
      <%= if @magazine.weather_impact do %>
        <section class="bg-blue-50 rounded-xl p-6 mb-8 border border-blue-100">
          <h3 class="font-semibold text-blue-900 mb-2">Weather Impact</h3>
          <p class="text-blue-800 text-sm"><%= get_in(@magazine.weather_impact, ["summary"]) || Jason.encode!(@magazine.weather_impact) %></p>
        </section>
      <% end %>

      <%!-- Batter Matchup Cards --%>
      <%= if @magazine.batter_matchups do %>
        <section class="mb-8">
          <h2 class="text-2xl font-bold text-gray-900 mb-4 flex items-center gap-2">
            <span class="w-1 h-6 bg-purple-600 rounded-full"></span>
            Batter Matchups
          </h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <%= for {_key, matchup} <- @magazine.batter_matchups || %{} do %>
              <div class="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
                <div class="flex justify-between items-center mb-3">
                  <span class="font-semibold text-gray-900"><%= matchup["player_name"] || "Unknown" %></span>
                  <span class="text-sm text-gray-500"><%= matchup["team"] %></span>
                </div>
                <%= if matchup["hit_prob"] do %>
                  <div class="mb-2">
                    <div class="flex justify-between text-xs mb-1">
                      <span>Hit</span>
                      <span class="font-bold"><%= Float.round((matchup["hit_prob"] || 0) * 100, 1) %>%</span>
                    </div>
                    <div class="w-full bg-gray-100 rounded-full h-1.5">
                      <div class="bg-green-500 h-1.5 rounded-full" style={"width: #{(matchup["hit_prob"] || 0) * 100}%"}></div>
                    </div>
                  </div>
                <% end %>
                <%= if matchup["hr_prob"] do %>
                  <div>
                    <div class="flex justify-between text-xs mb-1">
                      <span>HR</span>
                      <span class="font-bold"><%= Float.round((matchup["hr_prob"] || 0) * 100, 1) %>%</span>
                    </div>
                    <div class="w-full bg-gray-100 rounded-full h-1.5">
                      <div class="bg-purple-500 h-1.5 rounded-full" style={"width: #{min((matchup["hr_prob"] || 0) * 100 * 5, 100)}%"}></div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </section>
      <% end %>

      <%!-- Key Storylines --%>
      <%= if @magazine.key_storylines && length(@magazine.key_storylines) > 0 do %>
        <section class="bg-gray-50 rounded-xl p-8 mb-8">
          <h2 class="text-xl font-bold text-gray-900 mb-4">Key Storylines</h2>
          <ul class="space-y-3">
            <%= for storyline <- @magazine.key_storylines do %>
              <li class="flex items-start gap-3 text-gray-700">
                <span class="w-2 h-2 bg-blue-500 rounded-full mt-2 flex-shrink-0"></span>
                <span><%= storyline %></span>
              </li>
            <% end %>
          </ul>
        </section>
      <% end %>

      <%!-- Prediction --%>
      <%= if @magazine.prediction do %>
        <section class="bg-white rounded-xl shadow-sm border border-gray-200 p-8">
          <h2 class="text-xl font-bold text-gray-900 mb-4">AI Prediction</h2>
          <p class="text-gray-700"><%= get_in(@magazine.prediction, ["summary"]) || Jason.encode!(@magazine.prediction) %></p>
        </section>
      <% end %>
    </div>
    """
  end
end
