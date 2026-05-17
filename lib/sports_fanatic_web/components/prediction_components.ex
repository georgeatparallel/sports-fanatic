defmodule SportsFanaticWeb.PredictionComponents do
  @moduledoc """
  Reusable prediction-related view components: today's hit-prediction banner
  used on player detail and scouting report pages.
  """

  use Phoenix.Component

  @doc """
  Prominent banner for today's hit prediction on a player page.

  Pass `prediction: nil` to render the "no game today" notice.
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
    <% else %>
      <section class="bg-gray-100 text-gray-700 rounded-lg p-4 mb-6 text-sm">
        No game today for this player.
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
