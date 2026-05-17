defmodule SportsFanaticWeb.ScoutingLive do
  use SportsFanaticWeb, :live_view

  import Ecto.Query
  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.Predictions
  alias SportsFanatic.Repo

  @impl true
  def mount(%{"team_slug" => team_slug, "player_slug" => player_slug}, _session, socket) do
    team = Repo.get_by!(Team, slug: team_slug)

    player =
      Player
      |> where([p], p.team_id == ^team.id and p.slug == ^player_slug)
      |> Repo.one!()

    report =
      ScoutingReport
      |> where([sr], sr.player_id == ^player.id)
      |> order_by([sr], desc: sr.report_date)
      |> limit(1)
      |> Repo.one()

    today_hit_prediction =
      case get_in(player.external_ids, ["mlb_id"]) do
        nil ->
          nil

        mlb_id ->
          Predictions.get_for_player(String.to_integer(to_string(mlb_id)), Date.utc_today())
      end

    {:ok,
     assign(socket,
       page_title: "#{player.full_name} - Full Scouting Report",
       player: player,
       team: team,
       report: report,
       today_hit_prediction: today_hit_prediction
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <SportsFanaticWeb.PredictionComponents.today_hit_banner prediction={@today_hit_prediction} />
      <div class="flex items-center gap-4 mb-6">
        <div class="text-center">
          <span class="text-4xl font-bold text-blue-600">
            <%= if @report, do: @report.overall_grade, else: "-" %>
          </span>
          <p class="text-xs text-gray-500">Grade</p>
        </div>
        <div>
          <h1 class="text-3xl font-bold text-gray-900"><%= @player.full_name %></h1>
          <p class="text-gray-600"><%= @team.name %> | <%= @player.position %></p>
        </div>
      </div>

      <%= if @report do %>
        <div class="space-y-6">
          <section class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
            <h2 class="text-lg font-semibold text-gray-900 mb-3">Summary</h2>
            <p class="text-gray-700 leading-relaxed"><%= @report.summary %></p>
          </section>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <section class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h2 class="text-lg font-semibold text-gray-900 mb-3">Predictions</h2>
              <%= if @report.hit_probability do %>
                <div class="mb-4">
                  <div class="flex justify-between text-sm mb-1">
                    <span class="text-gray-600">Hit Probability</span>
                    <span class="font-bold text-green-600">
                      <%= Float.round((@report.hit_probability || 0) * 100, 1) %>%
                    </span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2">
                    <div
                      class="bg-green-500 h-2 rounded-full"
                      style={"width: #{(@report.hit_probability || 0) * 100}%"}
                    >
                    </div>
                  </div>
                </div>
              <% end %>
              <%= if @report.hr_probability do %>
                <div>
                  <div class="flex justify-between text-sm mb-1">
                    <span class="text-gray-600">HR Probability</span>
                    <span class="font-bold text-purple-600">
                      <%= Float.round((@report.hr_probability || 0) * 100, 1) %>%
                    </span>
                  </div>
                  <div class="w-full bg-gray-200 rounded-full h-2">
                    <div
                      class="bg-purple-500 h-2 rounded-full"
                      style={"width: #{min((@report.hr_probability || 0) * 100 * 5, 100)}%"}
                    >
                    </div>
                  </div>
                </div>
              <% end %>
              <%= if @report.confidence_modifier do %>
                <p class="text-sm text-gray-500 mt-3">
                  Confidence modifier: <%= @report.confidence_modifier %>
                </p>
              <% end %>
            </section>

            <section class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
              <h2 class="text-lg font-semibold text-gray-900 mb-3">Injury Status</h2>
              <div class="flex items-center gap-2 mb-2">
                <span class={"px-2 py-1 rounded-full text-sm font-medium #{if @report.injury_risk == "healthy", do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800"}"}>
                  <%= @report.injury_risk || "healthy" %>
                </span>
              </div>
              <%= if @report.injury_detail do %>
                <p class="text-sm text-gray-600"><%= @report.injury_detail %></p>
              <% end %>
            </section>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <%= if @report.strengths && length(@report.strengths) > 0 do %>
              <section class="bg-white rounded-lg shadow-sm border border-green-200 p-6">
                <h2 class="text-lg font-semibold text-green-700 mb-3">Strengths</h2>
                <ul class="space-y-2">
                  <%= for s <- @report.strengths do %>
                    <li class="flex items-start gap-2 text-gray-700 text-sm">
                      <span class="text-green-500 mt-0.5">+</span>
                      <span><%= s %></span>
                    </li>
                  <% end %>
                </ul>
              </section>
            <% end %>

            <%= if @report.weaknesses && length(@report.weaknesses) > 0 do %>
              <section class="bg-white rounded-lg shadow-sm border border-red-200 p-6">
                <h2 class="text-lg font-semibold text-red-700 mb-3">Weaknesses</h2>
                <ul class="space-y-2">
                  <%= for w <- @report.weaknesses do %>
                    <li class="flex items-start gap-2 text-gray-700 text-sm">
                      <span class="text-red-500 mt-0.5">-</span>
                      <span><%= w %></span>
                    </li>
                  <% end %>
                </ul>
              </section>
            <% end %>
          </div>

          <p class="text-sm text-gray-400">
            Report generated: <%= Calendar.strftime(@report.report_date, "%B %d, %Y") %> | Sources: <%= @report.sources_count %> | Model: <%= @report.model_version %>
          </p>
        </div>
      <% else %>
        <div class="bg-gray-50 rounded-lg p-8 text-center">
          <p class="text-gray-500">No scouting report available for this player yet.</p>
        </div>
      <% end %>
    </div>
    """
  end
end
