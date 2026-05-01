defmodule SportsFanaticWeb.LineupHTML do
  use SportsFanaticWeb, :html

  embed_templates "lineup_html/*"

  @doc """
  Renders a player name as a link if found in the lookup map,
  or as plain text fallback.
  """
  attr :players_by_nerds_id, :map, required: true
  attr :lineup, :map, required: true

  def player_link(assigns) do
    player = Map.get(assigns.players_by_nerds_id, assigns.lineup.player_nerds_id)

    assigns = assign(assigns, :player, player)

    ~H"""
    <%= if @player && @player.team do %>
      <a href={"/mlb/players/#{@player.team.slug}/#{@player.slug}"} class="hover:text-blue-600">
        <%= @player.full_name %>
      </a>
    <% else %>
      <span>Player #<%= @lineup.player_nerds_id %></span>
    <% end %>
    """
  end

  @doc """
  Renders a team name as a link if a team record is available,
  or as plain text fallback.
  """
  attr :team, :map, default: nil
  attr :name, :string, required: true

  def team_link(assigns) do
    ~H"""
    <%= if @team do %>
      <a href={"/mlb/teams/#{@team.slug}"} class="hover:text-blue-600"><%= @name %></a>
    <% else %>
      <span><%= @name %></span>
    <% end %>
    """
  end
end
