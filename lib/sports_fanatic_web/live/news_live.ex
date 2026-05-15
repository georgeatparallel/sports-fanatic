defmodule SportsFanaticWeb.NewsLive do
  @moduledoc """
  LiveView for the public MLB news feed. Provides live-updating news when
  new articles arrive via PubSub, and handles day transitions for users
  who leave the page open overnight.

  Supports agent commands for authenticated users:
  - /settings-apply "prompt" - creates a new agent setting
  - /settings-clear - removes all settings
  - Plain text - filters the feed client-side
  """

  use SportsFanaticWeb, :live_view

  alias SportsFanatic.Accounts
  alias SportsFanatic.Agents
  alias SportsFanatic.DateHelper
  alias SportsFanatic.News

  import SportsFanaticWeb.NewsHTML, only: [category_badge: 1, sentiment_dot: 1]

  @tick_interval :timer.seconds(60)

  @impl true
  def mount(_params, session, socket) do
    today = DateHelper.today()

    # Load current_user from session token (available in all browser pipelines)
    current_user = load_user_from_session(session)

    socket =
      socket
      |> assign(:today, today)
      |> assign(:current_user, current_user)
      |> assign(:active_tab, "feed")
      |> assign(:search_query, "")
      |> assign(:command_input, "")
      |> assign(:user_settings, [])
      |> assign(:agent_results, [])
      |> assign(:filtered_feed, nil)

    # Load user-specific data and subscribe to agent PubSub topics
    socket =
      if current_user && connected?(socket) do
        user_id = current_user.id
        Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "agent:settings:#{user_id}")
        Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "agent:results:#{user_id}")

        settings = Agents.list_user_settings(user_id)
        results = Agents.latest_results_for_user(user_id)

        socket
        |> assign(:user_settings, settings)
        |> assign(:agent_results, results)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :home, _params) do
    today = socket.assigns.today
    load_feed(socket, today, true)
  end

  defp apply_action(socket, :today, _params) do
    today = socket.assigns.today
    load_feed(socket, today, true)
  end

  defp apply_action(socket, :index, %{"date" => date_str}) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        today = socket.assigns.today
        viewing_today = Date.compare(date, today) == :eq
        load_feed(socket, date, viewing_today)

      {:error, _} ->
        push_navigate(socket, to: "/mlb/news")
    end
  end

  defp load_feed(socket, date, viewing_today) do
    {:ok, feed} = News.get_cached_feed(date)
    prev_date = News.nearest_news_date_before(date)
    today = socket.assigns.today
    raw_next = News.nearest_news_date_after(date)

    # Cap next_date at today
    next_date =
      if raw_next && Date.compare(raw_next, today) != :gt, do: raw_next, else: nil

    if connected?(socket) do
      # Unsubscribe from previous date-specific topic if navigating between dates
      if old_topic = socket.assigns[:subscribed_topic] do
        Phoenix.PubSub.unsubscribe(SportsFanatic.PubSub, old_topic)
      end

      topic = "news:feed:#{Date.to_iso8601(date)}"
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, topic)

      # Subscribe to general topic only once per session
      unless socket.assigns[:general_subscribed] do
        Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "news:feed")
      end

      # Schedule tick only once per connected session
      unless socket.assigns[:tick_started] do
        Process.send_after(self(), :tick, @tick_interval)
      end
    end

    date_str = Date.to_iso8601(date)
    formatted_date = Calendar.strftime(date, "%B %d, %Y")
    canonical = SportsFanaticWeb.Endpoint.url() <> "/mlb/news/#{date_str}"

    json_ld =
      Jason.encode!(%{
        "@context" => "https://schema.org",
        "@type" => "CollectionPage",
        "name" => "MLB News for #{formatted_date}",
        "url" => canonical,
        "publisher" => %{"@type" => "Organization", "name" => "Sports Fan Agent"}
      })

    socket
    |> assign(:date, date)
    |> assign(:date_str, date_str)
    |> assign(:formatted_date, formatted_date)
    |> assign(:feed, feed)
    |> assign(:feed_count, length(feed))
    |> assign(:prev_date, prev_date)
    |> assign(:next_date, next_date)
    |> assign(:viewing_today, viewing_today)
    |> assign(:subscribed_topic, "news:feed:#{date_str}")
    |> assign(:tick_started, true)
    |> assign(:general_subscribed, true)
    |> assign(:page_title, "MLB News for #{formatted_date}")
    |> assign(
      :meta_description,
      "Latest MLB news, injuries, trades, and player updates for #{formatted_date}."
    )
    |> assign(:canonical_url, canonical)
    |> assign(:json_ld, json_ld)
    |> assign(:filtered_feed, nil)
    |> assign(:search_query, "")
  end

  # ── Command/Event Handlers ─────────────────────────────────

  @impl true
  def handle_event("submit_command", %{"input" => input}, socket) do
    input = String.trim(input)

    cond do
      input == "" ->
        {:noreply, socket}

      String.starts_with?(input, "/settings-clear") ->
        if socket.assigns.current_user,
          do: handle_settings_clear(socket),
          else: {:noreply, put_flash(socket, :error, "Please log in to use agent commands.")}

      String.starts_with?(input, "/settings-apply") ->
        if socket.assigns.current_user,
          do: handle_settings_apply(input, socket),
          else: {:noreply, put_flash(socket, :error, "Please log in to use agent commands.")}

      true ->
        # Plain text search — available to all users
        handle_search(input, socket)
    end
  end

  def handle_event("search_feed", %{"query" => query}, socket) do
    handle_search(query, socket)
  end

  def handle_event("switch_news_tab", %{"tab" => tab}, socket) when tab in ~w(feed agents) do
    socket =
      if tab == "agents" && socket.assigns.current_user do
        user_id = socket.assigns.current_user.id
        settings = Agents.list_user_settings(user_id)
        results = Agents.latest_results_for_user(user_id)

        socket
        |> assign(:user_settings, settings)
        |> assign(:agent_results, results)
      else
        socket
      end

    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_event("delete_setting", %{"id" => setting_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, put_flash(socket, :error, "Please log in.")}

      user ->
        try do
          Agents.delete_setting(setting_id, user.id)
          settings = Agents.list_user_settings(user.id)
          {:noreply, assign(socket, :user_settings, settings)}
        rescue
          Ecto.NoResultsError ->
            {:noreply, put_flash(socket, :error, "Setting not found.")}
        end
    end
  end

  def handle_event("update_command_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :command_input, value)}
  end

  # ── Command Handlers ───────────────────────────────────────

  defp handle_settings_apply(input, socket) do
    # Extract the prompt: /settings-apply "prompt here" or /settings-apply prompt here
    raw_prompt =
      input
      |> String.replace_prefix("/settings-apply", "")
      |> String.trim()
      |> String.trim("\"")
      |> String.trim()

    if raw_prompt == "" do
      {:noreply, put_flash(socket, :error, "Please provide a description for your setting.")}
    else
      user_id = socket.assigns.current_user.id

      case Agents.create_setting(user_id, raw_prompt) do
        {:ok, setting} ->
          # Enqueue async LLM parsing
          %{"setting_id" => setting.id}
          |> SportsFanatic.Workers.ParseSettingWorker.new()
          |> Oban.insert()

          settings = Agents.list_user_settings(user_id)

          {:noreply,
           socket
           |> assign(:user_settings, settings)
           |> assign(:command_input, "")
           |> assign(:active_tab, "agents")
           |> put_flash(:info, "Setting created. Parsing in progress...")}

        {:error, :max_settings_reached} ->
          {:noreply, put_flash(socket, :error, "Maximum of 20 settings reached.")}

        {:error, :hourly_rate_limit_exceeded} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Rate limit reached. You can create up to 5 settings per hour."
           )}

        {:error, changeset} ->
          error_msg = format_changeset_error(changeset)
          {:noreply, put_flash(socket, :error, error_msg)}
      end
    end
  end

  defp handle_settings_clear(socket) do
    user_id = socket.assigns.current_user.id
    Agents.clear_user_settings(user_id)

    {:noreply,
     socket
     |> assign(:user_settings, [])
     |> assign(:command_input, "")
     |> put_flash(:info, "All settings cleared.")}
  end

  defp handle_search(query, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       socket
       |> assign(:filtered_feed, nil)
       |> assign(:search_query, "")}
    else
      filtered = filter_feed(socket.assigns.feed, query)

      {:noreply,
       socket
       |> assign(:filtered_feed, filtered)
       |> assign(:search_query, query)}
    end
  end

  defp filter_feed(feed, query) do
    query_lower = String.downcase(query)

    Enum.filter(feed, fn item ->
      searchable =
        [
          item["title"] || "",
          item["ai_summary"] || "",
          item["body"] || "",
          item["summary"] || ""
        ] ++
          Enum.map(item["players"] || [], fn p -> p["full_name"] || "" end) ++
          Enum.map(item["teams"] || [], fn t -> t["name"] || "" end) ++
          (item["domain_tags"] || [])

      searchable
      |> Enum.join(" ")
      |> String.downcase()
      |> String.contains?(query_lower)
    end)
  end

  # ── PubSub Handlers ────────────────────────────────────────

  @impl true
  def handle_info({:setting_updated, _setting}, socket) do
    if socket.assigns.current_user do
      settings = Agents.list_user_settings(socket.assigns.current_user.id)
      {:noreply, assign(socket, :user_settings, settings)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:agent_results, _user_id}, socket) do
    if socket.assigns.current_user do
      results = Agents.latest_results_for_user(socket.assigns.current_user.id)
      {:noreply, assign(socket, :agent_results, results)}
    else
      {:noreply, socket}
    end
  end

  # Day transition and fallback feed refresh
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_interval)
    new_today = DateHelper.today()
    old_today = socket.assigns.today

    cond do
      # Day changed and user is viewing "today" mode -- transition to new day
      Date.compare(new_today, old_today) != :eq && socket.assigns.viewing_today ->
        socket =
          socket
          |> assign(:today, new_today)
          |> load_feed(new_today, true)

        {:noreply, socket}

      # Day changed but user is on a historical date -- update nav boundary
      Date.compare(new_today, old_today) != :eq ->
        next_date = News.nearest_news_date_after(socket.assigns.date)

        next_date =
          if next_date && Date.compare(next_date, new_today) == :gt, do: nil, else: next_date

        {:noreply, assign(socket, today: new_today, next_date: next_date)}

      # Same day, viewing today -- fallback re-fetch in case PubSub was missed
      socket.assigns.viewing_today ->
        {:ok, feed} = News.get_cached_feed(socket.assigns.date)

        if length(feed) != socket.assigns.feed_count do
          {:noreply, assign(socket, feed: feed, feed_count: length(feed))}
        else
          {:noreply, socket}
        end

      true ->
        {:noreply, socket}
    end
  end

  # PubSub: new articles for any date
  def handle_info({:news_updated, date}, socket) do
    if Date.compare(date, socket.assigns.date) == :eq do
      {:ok, feed} = News.get_cached_feed(date)
      {:noreply, assign(socket, feed: feed, feed_count: length(feed))}
    else
      # Different date -- might affect nav (new "next" arrow)
      next_date = News.nearest_news_date_after(socket.assigns.date)
      today = socket.assigns.today

      next_date =
        if next_date && Date.compare(next_date, today) == :gt, do: nil, else: next_date

      {:noreply, assign(socket, next_date: next_date)}
    end
  end

  # ── Helpers ────────────────────────────────────────────────

  defp load_user_from_session(session) do
    token = session["session_token"]
    token && Accounts.get_user_by_session_token(token)
  end

  defp format_changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  defp format_changeset_error(_), do: "An error occurred."

  # Template helper: setting status badge color
  def setting_status_class("pending"), do: "bg-yellow-100 text-yellow-800"
  def setting_status_class("active"), do: "bg-green-100 text-green-800"
  def setting_status_class("running"), do: "bg-blue-100 text-blue-800"
  def setting_status_class("completed"), do: "bg-green-100 text-green-800"
  def setting_status_class("failed"), do: "bg-red-100 text-red-800"
  def setting_status_class("expired"), do: "bg-gray-100 text-gray-800"
  def setting_status_class(_), do: "bg-gray-100 text-gray-800"
end
