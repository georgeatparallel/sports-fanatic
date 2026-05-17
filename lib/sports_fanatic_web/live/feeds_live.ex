defmodule SportsFanaticWeb.FeedsLive do
  @moduledoc """
  LiveView for managing user news feeds. Provides full CRUD for feeds
  including player and team search with typeahead.

  Requires authentication -- redirects to login if not logged in.
  """

  use SportsFanaticWeb, :live_view

  alias SportsFanatic.Accounts
  alias SportsFanatic.Feeds
  alias SportsFanatic.Feeds.UserFeed
  alias SportsFanatic.News

  import Ecto.Query
  import SportsFanaticWeb.NewsHTML, only: [category_badge: 1, sentiment_dot: 1]

  @impl true
  def mount(_params, session, socket) do
    current_user = load_user_from_session(session)

    if is_nil(current_user) do
      {:ok,
       socket
       |> put_flash(:error, "You must log in to manage feeds.")
       |> redirect(to: "/login?return_to=/feeds")}
    else
      feeds = Feeds.list_feeds(current_user.id)

      {:ok,
       socket
       |> assign(:current_user, current_user)
       |> assign(:page_title, "Manage Feeds")
       |> assign(:feeds, feeds)
       |> assign(:view, :list)
       |> assign(:selected_feed, nil)
       |> assign(:feed_name, "")
       |> assign(:player_search, "")
       |> assign(:player_results, [])
       |> assign(:team_search, "")
       |> assign(:team_results, [])
       |> assign(:feed_players, [])
       |> assign(:feed_teams, [])
       |> assign(:feed_articles, [])
       |> assign(:creating, false)}
    end
  end

  @impl true
  def handle_params(%{"id" => feed_id}, _uri, socket) do
    try do
      feed = Feeds.get_feed!(feed_id, socket.assigns.current_user.id)
      {:noreply, load_feed_detail(socket, feed)}
    rescue
      Ecto.NoResultsError ->
        {:noreply,
         socket
         |> put_flash(:error, "Feed not found.")
         |> push_patch(to: "/feeds")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:view, :list)
     |> assign(:selected_feed, nil)
     |> assign(:creating, false)}
  end

  # -- Event Handlers --

  @impl true
  def handle_event("new_feed", _params, socket) do
    {:noreply,
     socket
     |> assign(:view, :create)
     |> assign(:creating, true)
     |> assign(:feed_name, "")
     |> assign(:player_search, "")
     |> assign(:player_results, [])
     |> assign(:team_search, "")
     |> assign(:team_results, [])
     |> assign(:feed_players, [])
     |> assign(:feed_teams, [])}
  end

  def handle_event("create_feed", %{"name" => name}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Feed name cannot be empty.")}
    else
      player_ids = Enum.map(socket.assigns.feed_players, & &1.id)
      team_ids = Enum.map(socket.assigns.feed_teams, & &1.id)

      case Feeds.create_feed(socket.assigns.current_user.id, name, %{
             player_ids: player_ids,
             team_ids: team_ids
           }) do
        {:ok, _feed} ->
          feeds = Feeds.list_feeds(socket.assigns.current_user.id)

          {:noreply,
           socket
           |> assign(:feeds, feeds)
           |> assign(:view, :list)
           |> assign(:creating, false)
           |> put_flash(:info, "Feed created.")}

        {:error, :max_feeds_reached} ->
          {:noreply, put_flash(socket, :error, "Maximum of 10 feeds reached.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          error_msg = format_changeset_error(changeset)
          {:noreply, put_flash(socket, :error, error_msg)}
      end
    end
  end

  def handle_event("edit_feed", %{"id" => feed_id}, socket) do
    try do
      feed = Feeds.get_feed!(feed_id, socket.assigns.current_user.id)
      {:noreply, load_feed_detail(socket, feed)}
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Feed not found.")}
    end
  end

  def handle_event("save_feed", %{"name" => name}, socket) do
    feed = socket.assigns.selected_feed
    name = String.trim(name)

    if name == "" do
      {:noreply, put_flash(socket, :error, "Feed name cannot be empty.")}
    else
      player_ids = Enum.map(socket.assigns.feed_players, & &1.id)
      team_ids = Enum.map(socket.assigns.feed_teams, & &1.id)

      case Feeds.update_feed(feed, socket.assigns.current_user.id, %{
             name: name,
             player_ids: player_ids,
             team_ids: team_ids
           }) do
        {:ok, updated_feed} ->
          feeds = Feeds.list_feeds(socket.assigns.current_user.id)

          {:noreply,
           socket
           |> assign(:feeds, feeds)
           |> assign(:selected_feed, updated_feed)
           |> assign(:feed_name, updated_feed.name)
           |> put_flash(:info, "Feed saved.")}

        {:error, :unauthorized} ->
          {:noreply, put_flash(socket, :error, "Unauthorized.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          error_msg = format_changeset_error(changeset)
          {:noreply, put_flash(socket, :error, error_msg)}
      end
    end
  end

  def handle_event("delete_feed", %{"id" => feed_id}, socket) do
    try do
      Feeds.delete_feed(feed_id, socket.assigns.current_user.id)
      feeds = Feeds.list_feeds(socket.assigns.current_user.id)

      {:noreply,
       socket
       |> assign(:feeds, feeds)
       |> assign(:view, :list)
       |> assign(:selected_feed, nil)
       |> put_flash(:info, "Feed deleted.")}
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Feed not found.")}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:view, :list)
     |> assign(:creating, false)
     |> assign(:selected_feed, nil)
     |> push_patch(to: "/feeds")}
  end

  def handle_event("view_feed_news", %{"id" => feed_id}, socket) do
    try do
      feed = Feeds.get_feed!(feed_id, socket.assigns.current_user.id)
      today = SportsFanatic.DateHelper.today()
      {:ok, all_articles} = News.get_cached_feed(today)
      {feed_articles, _rest} = Feeds.partition_articles_by_feed(feed, all_articles)

      {:noreply,
       socket
       |> assign(:view, :news)
       |> assign(:selected_feed, feed)
       |> assign(:feed_articles, feed_articles)}
    rescue
      Ecto.NoResultsError ->
        {:noreply, put_flash(socket, :error, "Feed not found.")}
    end
  end

  # Player search
  def handle_event("search_players", %{"query" => query}, socket) do
    query = String.trim(query)

    results =
      if String.length(query) >= 2 do
        search_players(query)
      else
        []
      end

    # Filter out already-added players
    existing_ids = MapSet.new(Enum.map(socket.assigns.feed_players, & &1.id))
    results = Enum.reject(results, fn p -> MapSet.member?(existing_ids, p.id) end)

    {:noreply,
     socket
     |> assign(:player_search, query)
     |> assign(:player_results, results)}
  end

  def handle_event("add_player", %{"id" => player_id}, socket) do
    player = SportsFanatic.Repo.get(SportsFanatic.Mlb.Player, player_id)

    if player do
      team = if player.team_id, do: SportsFanatic.Repo.get(SportsFanatic.Mlb.Team, player.team_id)

      player_info = %{
        id: player.id,
        full_name: player.full_name,
        slug: player.slug,
        position: player.position,
        team_name: if(team, do: team.name, else: nil),
        team_slug: if(team, do: team.slug, else: nil)
      }

      feed_players = socket.assigns.feed_players ++ [player_info]

      {:noreply,
       socket
       |> assign(:feed_players, feed_players)
       |> assign(:player_search, "")
       |> assign(:player_results, [])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_player", %{"id" => player_id}, socket) do
    feed_players = Enum.reject(socket.assigns.feed_players, &(&1.id == player_id))
    {:noreply, assign(socket, :feed_players, feed_players)}
  end

  # Team search
  def handle_event("search_teams", %{"query" => query}, socket) do
    query = String.trim(query)

    results =
      if String.length(query) >= 2 do
        search_teams(query)
      else
        []
      end

    existing_ids = MapSet.new(Enum.map(socket.assigns.feed_teams, & &1.id))
    results = Enum.reject(results, fn t -> MapSet.member?(existing_ids, t.id) end)

    {:noreply,
     socket
     |> assign(:team_search, query)
     |> assign(:team_results, results)}
  end

  def handle_event("add_team", %{"id" => team_id}, socket) do
    team = SportsFanatic.Repo.get(SportsFanatic.Mlb.Team, team_id)

    if team do
      team_info = %{
        id: team.id,
        name: team.name,
        slug: team.slug,
        abbreviation: team.abbreviation
      }

      feed_teams = socket.assigns.feed_teams ++ [team_info]

      {:noreply,
       socket
       |> assign(:feed_teams, feed_teams)
       |> assign(:team_search, "")
       |> assign(:team_results, [])}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_team", %{"id" => team_id}, socket) do
    feed_teams = Enum.reject(socket.assigns.feed_teams, &(&1.id == team_id))
    {:noreply, assign(socket, :feed_teams, feed_teams)}
  end

  def handle_event("update_feed_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :feed_name, value)}
  end

  # -- Private --

  defp load_user_from_session(session) do
    token = session["session_token"]
    token && Accounts.get_user_by_session_token(token)
  end

  defp load_feed_detail(socket, %UserFeed{} = feed) do
    # Load player details for the feed
    feed_players = load_players_for_ids(feed.player_ids)
    feed_teams = load_teams_for_ids(feed.team_ids)

    socket
    |> assign(:view, :edit)
    |> assign(:selected_feed, feed)
    |> assign(:feed_name, feed.name)
    |> assign(:feed_players, feed_players)
    |> assign(:feed_teams, feed_teams)
    |> assign(:player_search, "")
    |> assign(:player_results, [])
    |> assign(:team_search, "")
    |> assign(:team_results, [])
  end

  defp load_players_for_ids([]), do: []

  defp load_players_for_ids(ids) do
    SportsFanatic.Mlb.Player
    |> where([p], p.id in ^ids)
    |> SportsFanatic.Repo.all()
    |> SportsFanatic.Repo.preload(:team)
    |> Enum.map(fn p ->
      %{
        id: p.id,
        full_name: p.full_name,
        slug: p.slug,
        position: p.position,
        team_name: if(p.team, do: p.team.name, else: nil),
        team_slug: if(p.team, do: p.team.slug, else: nil)
      }
    end)
  end

  defp load_teams_for_ids([]), do: []

  defp load_teams_for_ids(ids) do
    SportsFanatic.Mlb.Team
    |> where([t], t.id in ^ids)
    |> SportsFanatic.Repo.all()
    |> Enum.map(fn t ->
      %{
        id: t.id,
        name: t.name,
        slug: t.slug,
        abbreviation: t.abbreviation
      }
    end)
  end

  defp search_players(query) do
    like_query = "%#{query}%"

    SportsFanatic.Mlb.Player
    |> where([p], ilike(p.full_name, ^like_query))
    |> order_by([p], asc: p.full_name)
    |> limit(10)
    |> SportsFanatic.Repo.all()
    |> SportsFanatic.Repo.preload(:team)
    |> Enum.map(fn p ->
      %{
        id: p.id,
        full_name: p.full_name,
        slug: p.slug,
        position: p.position,
        team_name: if(p.team, do: p.team.name, else: nil),
        team_slug: if(p.team, do: p.team.slug, else: nil)
      }
    end)
  end

  defp search_teams(query) do
    like_query = "%#{query}%"

    SportsFanatic.Mlb.Team
    |> where([t], ilike(t.name, ^like_query) or ilike(t.abbreviation, ^like_query))
    |> order_by([t], asc: t.name)
    |> limit(10)
    |> SportsFanatic.Repo.all()
    |> Enum.map(fn t ->
      %{
        id: t.id,
        name: t.name,
        slug: t.slug,
        abbreviation: t.abbreviation
      }
    end)
  end

  defp format_changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end
