defmodule SportsFanaticWeb.PredictionComponents do
  @moduledoc """
  Reusable prediction-related view components: today's game card sourced
  from `mlb.scheduled_games`, and the hit-prediction overlay banner used on
  player detail and scouting report pages.

  The two components stack: `game_card_panel/1` renders first (the canonical
  "today's game" UI), and `today_hit_banner/1` renders below as an additive
  enrichment when an `mlb.hit_predictions` row is available.
  """

  use Phoenix.Component

  @doc """
  Today's game card. Returns `nil` (renders nothing) when `card` is `nil`.

  When present, `card` is a map with the keys defined in
  `SportsFanatic.Mlb.todays_game_for_player/2`.
  """
  attr :card, :any, default: nil

  def game_card_panel(assigns) do
    ~H"""
    <%= if @card do %>
      <section class="bg-white border border-gray-200 rounded-lg shadow-sm p-6 mb-6">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p class="text-xs uppercase tracking-wider text-gray-500">Today's Game</p>
            <p class="text-2xl font-semibold text-gray-900 mt-1">
              <%= if @card.is_home, do: "vs", else: "@" %>
              <%= if @card.opponent_team do %>
                <a
                  href={"/mlb/teams/#{@card.opponent_team.slug}"}
                  class="text-blue-700 hover:text-blue-900"
                >
                  <%= @card.opponent_name %>
                </a>
              <% else %>
                <%= @card.opponent_name %>
              <% end %>
            </p>
            <p class="text-sm text-gray-600 mt-1">
              <%= @card.local_time_label %>
              <%= if @card.venue_name do %>
                · <%= @card.venue_name %>
              <% end %>
            </p>
          </div>
          <div class="text-right text-sm text-gray-700 space-y-1">
            <%= if @card.probable_pitcher_name do %>
              <p>
                vs <span class="font-medium"><%= @card.probable_pitcher_name %></span>
                <%= if @card.pitcher_record_label do %>
                  <span class="text-gray-500">(<%= @card.pitcher_record_label %>)</span>
                <% end %>
              </p>
            <% end %>
            <%= if @card.weather_oneliner do %>
              <p class="text-gray-600"><%= @card.weather_oneliner %></p>
            <% end %>
          </div>
        </div>
      </section>
    <% end %>
    """
  end

  @doc """
  Hit-prediction overlay banner. Renders nothing when `prediction` is `nil`
  (the canonical "today's game" UI is now `game_card_panel/1`).
  """
  attr :prediction, :any, default: nil

  def today_hit_banner(assigns) do
    ~H"""
    <%= if @prediction do %>
      <section class="bg-gradient-to-r from-blue-600 to-emerald-500 text-white rounded-lg shadow-md p-6 mb-6">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p class="text-xs uppercase tracking-wider opacity-80">Today's Hit Prediction</p>
            <p class="text-4xl font-bold mt-1">
              <%= format_pct(@prediction.hit_prob) %>
            </p>
            <p class="text-sm mt-2 opacity-95">
              <%= @prediction.player_team %> <%= if @prediction.is_home, do: "vs", else: "@" %> <%= @prediction.vs_team %>
              <%= if @prediction.venue_name do %>
                · <%= @prediction.venue_name %>
              <% end %>
              <%= if @prediction.game_datetime do %>
                · <%= format_time(@prediction.game_datetime) %>
              <% end %>
            </p>
          </div>
          <div class="text-right text-sm opacity-95 space-y-1">
            <%= if @prediction.probable_pitcher_name do %>
              <p>vs <%= @prediction.probable_pitcher_name %></p>
            <% end %>
            <p><%= weather_line(@prediction) %></p>
            <%= if @prediction.batting_order do %>
              <p>Batting <%= ordinal(@prediction.batting_order) %></p>
            <% end %>
          </div>
        </div>
      </section>
    <% end %>
    """
  end

  defp format_pct(nil), do: "—"

  defp format_pct(p) when is_float(p),
    do: "#{Float.round(p * 100, 1)}% #{if p >= 0.5, do: "Hit", else: "No Hit"}"

  defp format_pct(_), do: "—"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%-I:%M %p UTC")
  defp format_time(_), do: ""

  defp weather_line(p) when is_map(p) do
    parts =
      [
        if(Map.get(p, :temperature), do: "#{round(p.temperature)}°F", else: nil),
        if(Map.get(p, :wind_speed), do: "Wind #{round(p.wind_speed)} mph", else: nil),
        if(Map.get(p, :precipitation) && p.precipitation > 0,
          do: "Rain #{Float.round(p.precipitation * 1.0, 2)}\"",
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, " · ")
  end

  defp weather_line(_), do: ""

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n) when is_integer(n), do: "#{n}th"
  defp ordinal(_), do: ""
end
