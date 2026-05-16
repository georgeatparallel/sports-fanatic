defmodule SportsFanaticWeb.NewsLive do
  @moduledoc """
  LiveView for the public MLB news feed. Provides live-updating news when
  new articles arrive via PubSub, and handles day transitions for users
  who leave the page open overnight.

  Supports two input modes based on the `news_chatbot_enabled` feature flag:

  **Chat mode (flag on)**: Authenticated users interact via a conversational
  agent. The agent searches local news, discovers articles via Exa.ai, and
  streams progress updates to the chat thread.

  **Legacy mode (flag off)**: Agent commands via /settings-apply and
  client-side feed search.
  """

  use SportsFanaticWeb, :live_view

  alias SportsFanatic.Accounts
  alias SportsFanatic.Agents
  alias SportsFanatic.Agents.AgentSupervisor
  alias SportsFanatic.ChatBot
  alias SportsFanatic.ChatBot.SkillRouter

  alias SportsFanatic.ChatBot.Skills.{
    AddFeedSkill,
    HelpSkill,
    ListFeedsSkill,
    LoginSkill,
    ManageFeedsSkill,
    RegisterSkill,
    UploadSkill
  }

  alias SportsFanatic.DateHelper
  alias SportsFanatic.Feeds
  alias SportsFanatic.FeatureFlags
  alias SportsFanatic.News

  import SportsFanaticWeb.NewsHTML, only: [category_badge: 1, sentiment_dot: 1]

  @tick_interval :timer.seconds(60)

  @impl true
  def mount(_params, session, socket) do
    today = DateHelper.today()
    current_user = load_user_from_session(session)
    chat_enabled = FeatureFlags.enabled?("news_chatbot_enabled")

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
      # Chat-specific assigns
      |> assign(:chat_enabled, chat_enabled)
      |> assign(:chat_messages, [
        %{
          id: "welcome",
          role: "assistant",
          content: "How can I help you today? Try one of these:\n\n" <>
            "- **How is Hunter Brown doing?**\n" <>
            "- **What's the Mets injury report?**\n" <>
            "- **Current HR streaks**\n" <>
            "- **Upload a roster** — drag and drop your fantasy CSV to create a player feed\n\n" <>
            "Type **/help** for all commands.",
          inserted_at: DateTime.utc_now()
        }
      ])
      |> assign(:chat_session_id, nil)
      |> assign(:agent_running, false)
      |> assign(:chat_input, "")
      |> assign(:chat_articles, [])
      |> assign(:anon_id, nil)
      |> assign(:chat_subscribed, false)
      # Feed-specific assigns
      |> assign(:user_feeds, [])
      |> assign(:active_feed, nil)
      |> assign(:feed_articles, [])
      |> assign(:skill_state, nil)
      |> allow_upload(:roster_csv, accept: ~w(.csv), max_entries: 1, max_file_size: 1_048_576)

    socket =
      if current_user && connected?(socket) do
        user_id = current_user.id

        # Load user feeds
        user_feeds = Feeds.list_feeds(user_id)
        active_feed = Feeds.get_active_feed(user_id)

        socket =
          socket
          |> assign(:user_feeds, user_feeds)
          |> assign(:active_feed, active_feed)

        if chat_enabled do
          # Subscribe to chat PubSub channel
          Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "chat:#{user_id}")

          # Load or create chat session
          case ChatBot.get_or_create_session(user_id) do
            {:ok, session_record} ->
              db_messages = ChatBot.list_session_messages(session_record.id)
              formatted = format_messages(db_messages)

              # Always include welcome message at the start
              welcome = %{
                id: "welcome",
                role: "assistant",
                content: "How can I help you today? Try one of these:\n\n" <>
                  "- **How is Hunter Brown doing?**\n" <>
                  "- **What's the Mets injury report?**\n" <>
                  "- **Current HR streaks**\n" <>
                  "- **Upload a roster** — drag and drop your fantasy CSV to create a player feed\n\n" <>
                  "Type **/help** for all commands.",
                inserted_at: DateTime.utc_now()
              }

              all_messages = if formatted == [], do: [welcome], else: [welcome | formatted]

              socket
              |> assign(:chat_session_id, session_record.id)
              |> assign(:chat_messages, all_messages)

            {:error, _} ->
              socket
          end
        else
          # Legacy mode subscriptions
          Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "agent:settings:#{user_id}")
          Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "agent:results:#{user_id}")

          settings = Agents.list_user_settings(user_id)
          results = Agents.latest_results_for_user(user_id)

          socket
          |> assign(:user_settings, settings)
          |> assign(:agent_results, results)
        end
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

    # Partition feed into user feed articles and general articles
    active_feed = socket.assigns[:active_feed]
    {feed_articles, _rest} = Feeds.partition_articles_by_feed(active_feed, feed)

    socket
    |> assign(:date, date)
    |> assign(:date_str, date_str)
    |> assign(:formatted_date, formatted_date)
    |> assign(:feed, feed)
    |> assign(:feed_count, length(feed))
    |> assign(:feed_articles, feed_articles)
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

  # ── Chat Event Handlers ───────────────────────────────────────

  @impl true
  def handle_event("submit_chat", %{"message" => text}, socket) do
    text = String.trim(text)

    cond do
      text == "" ->
        {:noreply, socket}

      socket.assigns.agent_running ->
        {:noreply,
         put_flash(socket, :info, "Please wait for the current search to complete, or cancel it.")}

      true ->
        handle_chat_submit(text, socket)
    end
  end

  def handle_event("clear_chat", _params, socket) do
    # Clear persisted session for authenticated users
    if socket.assigns.current_user && socket.assigns.chat_session_id do
      ChatBot.clear_session(socket.assigns.chat_session_id, socket.assigns.current_user.id)
    end

    # Create a new session for authenticated users
    new_session_id =
      if socket.assigns.current_user do
        case ChatBot.get_or_create_session(socket.assigns.current_user.id) do
          {:ok, s} -> s.id
          _ -> nil
        end
      else
        nil
      end

    {:noreply,
     socket
     |> assign(:chat_messages, [])
     |> assign(:chat_session_id, new_session_id)
     |> assign(:agent_running, false)
     |> assign(:chat_articles, [])
     |> assign(:chat_input, "")}
  end

  def handle_event("cancel_agent", _params, socket) do
    user_id =
      if socket.assigns.current_user,
        do: socket.assigns.current_user.id,
        else: socket.assigns[:anon_id]

    if user_id, do: AgentSupervisor.cancel_agent(user_id)

    {:noreply, assign(socket, :agent_running, false)}
  end

  def handle_event("update_chat_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :chat_input, value)}
  end

  def handle_event("switch_feed", %{"feed_id" => ""}, socket) do
    {_feed_articles, _rest} = Feeds.partition_articles_by_feed(nil, socket.assigns.feed)

    {:noreply,
     socket
     |> assign(:active_feed, nil)
     |> assign(:feed_articles, [])}
  end

  def handle_event("switch_feed", %{"feed_id" => feed_id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply, socket}

      user ->
        try do
          feed = Feeds.get_feed!(feed_id, user.id)
          {feed_articles, _rest} = Feeds.partition_articles_by_feed(feed, socket.assigns.feed)

          {:noreply,
           socket
           |> assign(:active_feed, feed)
           |> assign(:feed_articles, feed_articles)}
        rescue
          Ecto.NoResultsError ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("upload_csv", _params, socket) do
    context = %{current_user: socket.assigns.current_user}

    result =
      consume_uploaded_entries(socket, :roster_csv, fn %{path: path}, _entry ->
        csv_binary = File.read!(path)
        {:ok, csv_binary}
      end)

    case result do
      [csv_binary | _] ->
        case UploadSkill.process_csv(csv_binary, context) do
          {:reply, message, new_skill_state} ->
            {:noreply, apply_skill_reply(socket, message, new_skill_state)}

          {:reply, message, new_skill_state, :feeds_changed} ->
            {:noreply,
             socket
             |> apply_skill_reply(message, new_skill_state)
             |> reload_user_feeds()}
        end

      [] ->
        {:noreply, socket}
    end
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  # ── Legacy Event Handlers (feature flag off) ──────────────────

  def handle_event("submit_command", %{"key" => "Enter", "value" => input}, socket) do
    if socket.assigns.chat_enabled do
      handle_event("submit_chat", %{"message" => input}, socket)
    else
      handle_command_input(String.trim(input), socket)
    end
  end

  def handle_event("submit_command", %{"input" => input}, socket) do
    if socket.assigns.chat_enabled do
      handle_event("submit_chat", %{"message" => input}, socket)
    else
      handle_command_input(String.trim(input), socket)
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

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:filtered_feed, nil)
     |> assign(:search_query, "")
     |> assign(:command_input, "")}
  end

  # ── Chat Submission Logic ─────────────────────────────────────

  defp handle_chat_submit(text, socket) do
    # Route through skill router first
    case SkillRouter.route(text, socket.assigns.skill_state) do
      {:skill, :cancel} ->
        cancel_msg = %{
          id: Ecto.UUID.generate(),
          role: "assistant",
          content: "Operation cancelled.",
          inserted_at: DateTime.utc_now()
        }

        {:noreply,
         socket
         |> append_user_msg(text)
         |> update(:chat_messages, &(&1 ++ [cancel_msg]))
         |> assign(:skill_state, nil)
         |> assign(:chat_input, "")
         |> push_event("scroll_to_bottom", %{})}

      {:skill, skill_name} ->
        handle_skill(skill_name, text, nil, socket)

      {:continue, skill_name, input} ->
        handle_skill(skill_name, input, socket.assigns.skill_state, socket)

      {:agent, text} ->
        # Fall through to existing agent logic
        do_agent_submit(text, socket)
    end
  end

  defp handle_skill(skill_name, text, skill_state, socket) do
    context = %{current_user: socket.assigns.current_user}

    result =
      case skill_name do
        :help -> HelpSkill.handle(text, skill_state, context)
        :register -> RegisterSkill.handle(text, skill_state, context)
        :login -> LoginSkill.handle(text, skill_state, context)
        :add_feed -> AddFeedSkill.handle(text, skill_state, context)
        :list_feeds -> ListFeedsSkill.handle(text, skill_state, context)
        :manage_feeds -> ManageFeedsSkill.handle(text, skill_state, context)
        :upload -> UploadSkill.handle(text, skill_state, context)
      end

    socket = append_user_msg(socket, text)

    case result do
      {:reply, message, new_skill_state} ->
        {:noreply, apply_skill_reply(socket, message, new_skill_state)}

      {:reply, message, new_skill_state, :feeds_changed} ->
        {:noreply,
         socket
         |> apply_skill_reply(message, new_skill_state)
         |> reload_user_feeds()}

      {:reply_with_auth, message, token, _user} ->
        assistant_msg = %{
          id: Ecto.UUID.generate(),
          role: "assistant",
          content: message,
          inserted_at: DateTime.utc_now()
        }

        return_to =
          if socket.assigns[:date_str],
            do: "/mlb/news/#{socket.assigns.date_str}",
            else: "/mlb/news"

        {:noreply,
         socket
         |> update(:chat_messages, &(&1 ++ [assistant_msg]))
         |> assign(:skill_state, nil)
         |> assign(:chat_input, "")
         |> push_navigate(to: "/auth/session/#{token}?return_to=#{return_to}")}
    end
  end

  defp apply_skill_reply(socket, message, new_skill_state) do
    assistant_msg = %{
      id: Ecto.UUID.generate(),
      role: "assistant",
      content: message,
      inserted_at: DateTime.utc_now()
    }

    # Do not persist password messages to chat history
    is_password_step =
      new_skill_state != nil and
        Map.get(new_skill_state, :step) in [:await_password]

    # Persist assistant message for authenticated users (skip password prompts)
    if socket.assigns.current_user && socket.assigns.chat_session_id && !is_password_step do
      ChatBot.create_message(%{
        session_id: socket.assigns.chat_session_id,
        role: "assistant",
        content: message
      })
    end

    socket
    |> update(:chat_messages, &(&1 ++ [assistant_msg]))
    |> assign(:skill_state, new_skill_state)
    |> assign(:chat_input, "")
    |> push_event("scroll_to_bottom", %{})
  end

  defp append_user_msg(socket, text) do
    # Do not persist password inputs
    is_password_input =
      socket.assigns.skill_state != nil and
        Map.get(socket.assigns.skill_state, :step) == :await_password

    user_msg = %{
      id: Ecto.UUID.generate(),
      role: "user",
      content: if(is_password_input, do: "********", else: text),
      inserted_at: DateTime.utc_now()
    }

    # Persist non-password user messages
    if socket.assigns.current_user && socket.assigns.chat_session_id && !is_password_input do
      ChatBot.create_message(%{
        session_id: socket.assigns.chat_session_id,
        role: "user",
        content: text
      })
    end

    update(socket, :chat_messages, &(&1 ++ [user_msg]))
  end

  defp reload_user_feeds(socket) do
    if socket.assigns.current_user do
      user_feeds = Feeds.list_feeds(socket.assigns.current_user.id)
      active_feed = Feeds.get_active_feed(socket.assigns.current_user.id)
      {feed_articles, _rest} = Feeds.partition_articles_by_feed(active_feed, socket.assigns.feed)

      socket
      |> assign(:user_feeds, user_feeds)
      |> assign(:active_feed, active_feed)
      |> assign(:feed_articles, feed_articles)
    else
      socket
    end
  end

  defp do_agent_submit(text, socket) do
    # Use user_id if logged in, otherwise generate an anonymous session key
    user_id =
      if socket.assigns.current_user,
        do: socket.assigns.current_user.id,
        else: socket.assigns[:anon_id] || Ecto.UUID.generate()

    # Rate limit for authenticated users only
    if socket.assigns.current_user do
      case ChatBot.check_rate_limit(user_id) do
        {:error, :hourly_limit_exceeded} ->
          {:noreply, put_flash(socket, :error, "Rate limit reached (max 10 queries per hour).")}

        {:error, :daily_limit_exceeded} ->
          {:noreply, put_flash(socket, :error, "Rate limit reached (max 50 queries per day).")}

        :ok ->
          do_chat_submit(text, user_id, socket)
      end
    else
      # Anonymous users: no rate limit, no persistence
      socket = assign(socket, :anon_id, user_id)
      do_chat_submit(text, user_id, socket)
    end
  end

  defp do_chat_submit(text, user_id, socket) do
    session_id = socket.assigns.chat_session_id

    # Persist chat session for authenticated users only
    session_id =
      if socket.assigns.current_user do
        if is_nil(session_id) do
          case ChatBot.get_or_create_session(user_id) do
            {:ok, s} -> s.id
            _ -> nil
          end
        else
          ChatBot.touch_session(session_id)
          session_id
        end
      else
        session_id
      end

    # Store message for authenticated users
    if socket.assigns.current_user && session_id do
      ChatBot.create_message(%{
        session_id: session_id,
        role: "user",
        content: text
      })
    end

    # Add to chat messages for display
    user_msg = %{
      id: Ecto.UUID.generate(),
      role: "user",
      content: text,
      inserted_at: DateTime.utc_now()
    }

    chat_messages = socket.assigns.chat_messages ++ [user_msg]

    # Subscribe to agent PubSub if not already
    if not socket.assigns[:chat_subscribed] do
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "chat:#{user_id}")
    end

    # Build conversation context (last 10 user+assistant messages, skip progress/welcome)
    context_messages =
      chat_messages
      |> Enum.filter(fn msg ->
        msg.role in ["user", "assistant"] and msg.id != "welcome"
      end)
      |> Enum.take(-10)
      |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)

    # Get date context for agent
    date = socket.assigns[:date_str]

    # Spawn agent with conversation context
    AgentSupervisor.start_agent(user_id, text, date: date, context: context_messages)

    {:noreply,
     socket
     |> assign(:chat_messages, chat_messages)
     |> assign(:chat_session_id, session_id)
     |> assign(:agent_running, true)
     |> assign(:chat_input, "")
     |> assign(:chat_articles, [])
     |> assign(:chat_subscribed, true)
     |> push_event("scroll_to_bottom", %{})}
  end

  # ── Legacy Command Handlers ───────────────────────────────────

  defp handle_command_input(input, socket) do
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
        # Plain text search -- available to all users
        handle_search(input, socket)
    end
  end

  defp handle_settings_apply(input, socket) do
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

  @stop_words ~w(a an the is was are were be been being have has had do does did
    will would shall should may might can could and but or nor for yet so at by
    from in into of on to with about above after before between through during
    only just very also more most other some such no not than too any each every
    all both few many much own same so still when where how what which who whom
    this that these those my our your its his her their me us you him them show
    me tell give find get)

  defp filter_feed(feed, query) do
    terms =
      query
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reject(&(&1 in @stop_words))
      |> Enum.flat_map(&expand_term/1)

    # If all words were stop words, show everything
    if terms == [] do
      feed
    else
      Enum.filter(feed, fn item ->
        # Build separate search contexts for precise matching
        leagues =
          item["teams"] |> List.wrap() |> Enum.map(fn t -> String.downcase(t["league"] || "") end)

        abbreviations =
          item["teams"]
          |> List.wrap()
          |> Enum.map(fn t -> String.downcase(t["abbreviation"] || "") end)

        text_parts =
          [
            item["title"] || "",
            item["ai_summary"] || "",
            item["body"] || "",
            item["summary"] || "",
            item["category"] || ""
          ] ++
            Enum.map(item["players"] || [], fn p -> p["full_name"] || "" end) ++
            Enum.map(item["teams"] || [], fn t ->
              "#{t["name"]} #{t["abbreviation"]} #{t["league"]}"
            end) ++
            (item["domain_tags"] || [])

        text = text_parts |> Enum.join(" ") |> String.downcase()

        Enum.all?(terms, fn term_group ->
          Enum.any?(term_group, fn t ->
            cond do
              # For league terms, match exactly against team leagues
              t in ["al", "nl"] -> t in leagues
              # For short abbreviations (2-3 chars), match against team abbreviations too
              String.length(t) <= 3 -> t in abbreviations or String.contains?(text, t)
              true -> String.contains?(text, t)
            end
          end)
        end)
      end)
    end
  end

  defp expand_term("hr"), do: [["hr", "home-run", "homer", "home run"]]
  defp expand_term("homers"), do: [["homers", "homer", "home-run", "home run"]]
  defp expand_term("homer"), do: [["homer", "home-run", "homers", "home run"]]
  defp expand_term("streak"), do: [["streak"]]
  defp expand_term("streaks"), do: [["streak", "streaks"]]
  defp expand_term("il"), do: [["il", "injured list", "injury"]]
  defp expand_term("dl"), do: [["dl", "disabled list", "injury"]]
  defp expand_term("tj"), do: [["tj", "tommy john"]]
  defp expand_term("rbi"), do: [["rbi", "runs batted"]]
  defp expand_term("era"), do: [["era", "earned run"]]
  defp expand_term("al"), do: [["al"]]
  defp expand_term("nl"), do: [["nl"]]
  defp expand_term(term), do: [[term]]

  # ── Chat PubSub Handlers ─────────────────────────────────────

  @impl true
  def handle_info({:agent_progress, %{message: message}}, socket) do
    progress_msg = %{
      id: Ecto.UUID.generate(),
      role: "progress",
      content: message,
      inserted_at: DateTime.utc_now()
    }

    chat_messages = socket.assigns.chat_messages ++ [progress_msg]
    {:noreply, assign(socket, :chat_messages, chat_messages)}
  end

  def handle_info({:agent_complete, %{summary: summary, news_item_ids: ids}}, socket) do
    # Store assistant message
    if socket.assigns.chat_session_id do
      ChatBot.create_message(%{
        session_id: socket.assigns.chat_session_id,
        role: "assistant",
        content: summary,
        news_item_ids: ids
      })
    end

    # Remove progress messages, add final assistant message
    chat_messages =
      socket.assigns.chat_messages
      |> Enum.reject(&(&1.role == "progress"))

    assistant_msg = %{
      id: Ecto.UUID.generate(),
      role: "assistant",
      content: summary,
      news_item_ids: ids,
      inserted_at: DateTime.utc_now()
    }

    chat_messages = chat_messages ++ [assistant_msg]

    # Load matched articles from the feed for display
    chat_articles = load_articles_for_ids(ids)

    {:noreply,
     socket
     |> assign(:chat_messages, chat_messages)
     |> assign(:agent_running, false)
     |> assign(:chat_articles, chat_articles)}
  end

  def handle_info({:agent_error, %{error: error}}, socket) do
    error_msg = %{
      id: Ecto.UUID.generate(),
      role: "assistant",
      content: error,
      inserted_at: DateTime.utc_now()
    }

    chat_messages =
      socket.assigns.chat_messages
      |> Enum.reject(&(&1.role == "progress"))
      |> Kernel.++([error_msg])

    {:noreply,
     socket
     |> assign(:chat_messages, chat_messages)
     |> assign(:agent_running, false)}
  end

  # ── Legacy PubSub Handlers ───────────────────────────────────

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
      Date.compare(new_today, old_today) != :eq && socket.assigns.viewing_today ->
        socket =
          socket
          |> assign(:today, new_today)
          |> load_feed(new_today, true)

        {:noreply, socket}

      Date.compare(new_today, old_today) != :eq ->
        next_date = News.nearest_news_date_after(socket.assigns.date)

        next_date =
          if next_date && Date.compare(next_date, new_today) == :gt, do: nil, else: next_date

        {:noreply, assign(socket, today: new_today, next_date: next_date)}

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

  defp format_messages(messages) do
    Enum.map(messages, fn m ->
      %{
        id: m.id,
        role: m.role,
        content: m.content,
        news_item_ids: m.news_item_ids || [],
        inserted_at: m.inserted_at
      }
    end)
  end

  defp load_articles_for_ids([]), do: []

  defp load_articles_for_ids(ids) do
    import Ecto.Query

    ids_list = Enum.take(ids, 20)

    SportsFanatic.Content.NewsItem
    |> where([n], n.id in ^ids_list)
    |> order_by([n], desc: n.inserted_at)
    |> SportsFanatic.Repo.all()
    |> Enum.map(fn item ->
      %{
        "id" => item.id,
        "title" => item.title,
        "ai_summary" => item.ai_summary,
        "category" => item.category,
        "sentiment" => item.sentiment,
        "source_url" => item.source_url,
        "author" => item.author,
        "published_date" => item.published_date
      }
    end)
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

  # Template helper: render markdown and sanitize for safe display
  def render_markdown(content) when is_binary(content) do
    case Earmark.as_html(content, compact_output: true) do
      {:ok, html, _} ->
        html
        |> HtmlSanitizeEx.basic_html()
        |> Phoenix.HTML.raw()

      _ ->
        content |> HtmlSanitizeEx.strip_tags()
    end
  end

  def render_markdown(_), do: ""

  # Plain text sanitize (for user messages and progress)
  def sanitize_chat(content) when is_binary(content) do
    HtmlSanitizeEx.strip_tags(content)
  end

  def sanitize_chat(_), do: ""

  # Template helpers for skills and uploads
  def skill_placeholder(%{skill: :register, step: :await_email}),
    do: "Enter your email address..."

  def skill_placeholder(%{skill: :register, step: :await_password}), do: "Enter a password..."
  def skill_placeholder(%{skill: :login, step: :await_email}), do: "Enter your email address..."
  def skill_placeholder(%{skill: :login, step: :await_password}), do: "Enter your password..."
  def skill_placeholder(%{skill: :add_feed, step: :await_name}), do: "Enter a feed name..."

  def skill_placeholder(%{skill: :add_feed, step: :await_players}),
    do: "Enter player names separated by commas..."

  def skill_placeholder(%{skill: :upload, step: :await_file}), do: "Select a CSV file above..."
  def skill_placeholder(%{skill: :upload, step: :await_name}), do: "Enter a feed name..."
  def skill_placeholder(%{skill: :manage_feeds, step: :await_selection}), do: "Enter a number..."
  def skill_placeholder(%{skill: :manage_feeds, step: :await_action}), do: "Enter 1, 2, or 3..."
  def skill_placeholder(%{skill: :manage_feeds, step: :await_rename}), do: "Enter a new name..."
  def skill_placeholder(_), do: "Type a message..."

  def upload_error_message(:too_large), do: "File is too large (max 1 MB)"
  def upload_error_message(:not_accepted), do: "Only .csv files are accepted"
  def upload_error_message(:too_many_files), do: "Only one file at a time"
  def upload_error_message(_), do: "Upload error"
end
