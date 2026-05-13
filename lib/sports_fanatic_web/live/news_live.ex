defmodule SportsFanaticWeb.NewsLive do
  @moduledoc """
  LiveView for the public MLB news feed. Provides live-updating news when
  new articles arrive via PubSub, and handles day transitions for users
  who leave the page open overnight.
  """

  use SportsFanaticWeb, :live_view

  alias SportsFanatic.DateHelper
  alias SportsFanatic.News

  import SportsFanaticWeb.NewsHTML, only: [category_badge: 1, sentiment_dot: 1]

  @tick_interval :timer.seconds(60)

  @impl true
  def mount(_params, _session, socket) do
    today = DateHelper.today()
    {:ok, assign(socket, :today, today)}
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
  end

  # Day transition and fallback feed refresh
  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_interval)
    new_today = DateHelper.today()
    old_today = socket.assigns.today

    cond do
      # Day changed and user is viewing "today" mode — transition to new day
      Date.compare(new_today, old_today) != :eq && socket.assigns.viewing_today ->
        socket =
          socket
          |> assign(:today, new_today)
          |> load_feed(new_today, true)

        {:noreply, socket}

      # Day changed but user is on a historical date — update nav boundary
      Date.compare(new_today, old_today) != :eq ->
        next_date = News.nearest_news_date_after(socket.assigns.date)

        next_date =
          if next_date && Date.compare(next_date, new_today) == :gt, do: nil, else: next_date

        {:noreply, assign(socket, today: new_today, next_date: next_date)}

      # Same day, viewing today — fallback re-fetch in case PubSub was missed
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
  @impl true
  def handle_info({:news_updated, date}, socket) do
    if Date.compare(date, socket.assigns.date) == :eq do
      {:ok, feed} = News.get_cached_feed(date)
      {:noreply, assign(socket, feed: feed, feed_count: length(feed))}
    else
      # Different date — might affect nav (new "next" arrow)
      next_date = News.nearest_news_date_after(socket.assigns.date)
      today = socket.assigns.today

      next_date =
        if next_date && Date.compare(next_date, today) == :gt, do: nil, else: next_date

      {:noreply, assign(socket, next_date: next_date)}
    end
  end
end
