defmodule SportsFanaticWeb.LineupHTML do
  use SportsFanaticWeb, :html

  embed_templates "lineup_html/*"

  @doc """
  Renders a player name as a link if the lineup has a preloaded player
  with a team, or as plain text fallback showing the FantasyNerds ID.
  """
  attr :lineup, :map, required: true

  def player_link(assigns) do
    player = assigns.lineup.player

    assigns = assign(assigns, :player, player)

    ~H"""
    <%= if @player && @player.team do %>
      <a href={"/mlb/players/#{@player.team.slug}/#{@player.slug}"} class="hover:text-blue-600">
        <%= @player.full_name %>
      </a>
    <% else %>
      <span><%= @lineup.player_name || "Player ##{@lineup.player_nerds_id}" %></span>
    <% end %>
    """
  end

  @doc """
  Renders a probable pitcher name as a link if resolvable, or plain text.
  """
  attr :pitcher_name, :string, default: nil
  attr :pitchers, :map, required: true

  def pitcher_link(assigns) do
    player = if assigns.pitcher_name, do: Map.get(assigns.pitchers, assigns.pitcher_name)
    assigns = assign(assigns, :player, player)

    ~H"""
    <%= if @player && @player.team do %>
      <a
        href={"/mlb/players/#{@player.team.slug}/#{@player.slug}"}
        class="text-blue-600 hover:text-blue-800"
      >
        <%= @pitcher_name %>
      </a>
    <% else %>
      <span><%= @pitcher_name || "TBD" %></span>
    <% end %>
    """
  end

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
