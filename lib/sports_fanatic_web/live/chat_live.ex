defmodule SportsFanaticWeb.ChatLive do
  @moduledoc """
  Dedicated LiveView for the conversational news research agent.

  Supports both authenticated and anonymous users. Authenticated users
  get persistent chat history, rate limiting, and feed management skills.
  Anonymous users get ephemeral sessions with no persistence.
  """

  use SportsFanaticWeb, :live_view

  alias SportsFanatic.Accounts
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
  alias SportsFanaticWeb.SEO

  @impl true
  def mount(_params, session, socket) do
    current_user = load_user_from_session(session)
    today = DateHelper.today()

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:today, today)
      |> assign(:date_str, Date.to_iso8601(today))
      |> assign(:page_title, "Chat")
      |> assign(:og_title, SEO.default_title())
      |> assign(:meta_description, SEO.default_description())
      |> assign(:canonical_url, SEO.absolute_url("/"))
      |> assign(:og_type, "website")
      |> assign(:json_ld, home_json_ld())
      |> assign(:chat_messages, [welcome_message()])
      |> assign(:chat_session_id, nil)
      |> assign(:agent_running, false)
      |> assign(:chat_input, "")
      |> assign(:chat_articles, [])
      |> assign(:anon_id, nil)
      |> assign(:chat_subscribed, false)
      |> assign(:skill_state, nil)
      |> assign(:user_feeds, [])
      |> allow_upload(:roster_csv, accept: ~w(.csv), max_entries: 1, max_file_size: 1_048_576)

    socket =
      if current_user && connected?(socket) do
        user_id = current_user.id

        # Load user feeds
        user_feeds = Feeds.list_feeds(user_id)
        socket = assign(socket, :user_feeds, user_feeds)

        # Subscribe to chat PubSub channel
        Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "chat:#{user_id}")
        socket = assign(socket, :chat_subscribed, true)

        # Load or create chat session
        case ChatBot.get_or_create_session(user_id) do
          {:ok, session_record} ->
            db_messages = ChatBot.list_session_messages(session_record.id)
            formatted = format_messages(db_messages)

            welcome = welcome_message()
            all_messages = if formatted == [], do: [welcome], else: [welcome | formatted]

            socket
            |> assign(:chat_session_id, session_record.id)
            |> assign(:chat_messages, all_messages)

          {:error, _} ->
            socket
        end
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # -- Chat Event Handlers --

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
    if socket.assigns.current_user && socket.assigns.chat_session_id do
      ChatBot.clear_session(socket.assigns.chat_session_id, socket.assigns.current_user.id)
    end

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
     |> assign(:chat_messages, [welcome_message()])
     |> assign(:chat_session_id, new_session_id)
     |> assign(:agent_running, false)
     |> assign(:chat_articles, [])
     |> assign(:chat_input, "")
     |> push_event("focus_input", %{})}
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

  # Auto-process CSV once file upload is complete
  def handle_event("auto_upload_csv", _params, socket) do
    entries = socket.assigns.uploads.roster_csv.entries
    all_done = entries != [] and Enum.all?(entries, & &1.done?)

    if all_done do
      handle_event("upload_csv", %{}, socket)
    else
      {:noreply, socket}
    end
  end

  # -- Chat Submission Logic --

  defp handle_chat_submit(text, socket) do
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

        {:noreply,
         socket
         |> update(:chat_messages, &(&1 ++ [assistant_msg]))
         |> assign(:skill_state, nil)
         |> assign(:chat_input, "")
         |> push_navigate(to: "/auth/session/#{token}?return_to=/chat")}
    end
  end

  defp apply_skill_reply(socket, message, new_skill_state) do
    assistant_msg = %{
      id: Ecto.UUID.generate(),
      role: "assistant",
      content: message,
      inserted_at: DateTime.utc_now()
    }

    is_password_step =
      new_skill_state != nil and
        Map.get(new_skill_state, :step) in [:await_password]

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
    is_password_input =
      socket.assigns.skill_state != nil and
        Map.get(socket.assigns.skill_state, :step) == :await_password

    user_msg = %{
      id: Ecto.UUID.generate(),
      role: "user",
      content: if(is_password_input, do: "********", else: text),
      inserted_at: DateTime.utc_now()
    }

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
      assign(socket, :user_feeds, user_feeds)
    else
      socket
    end
  end

  defp do_agent_submit(text, socket) do
    user_id =
      if socket.assigns.current_user,
        do: socket.assigns.current_user.id,
        else: socket.assigns[:anon_id] || Ecto.UUID.generate()

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
      socket = assign(socket, :anon_id, user_id)
      do_chat_submit(text, user_id, socket)
    end
  end

  defp do_chat_submit(text, user_id, socket) do
    session_id = socket.assigns.chat_session_id

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

    if socket.assigns.current_user && session_id do
      ChatBot.create_message(%{
        session_id: session_id,
        role: "user",
        content: text
      })
    end

    user_msg = %{
      id: Ecto.UUID.generate(),
      role: "user",
      content: text,
      inserted_at: DateTime.utc_now()
    }

    chat_messages = socket.assigns.chat_messages ++ [user_msg]

    if not socket.assigns[:chat_subscribed] do
      Phoenix.PubSub.subscribe(SportsFanatic.PubSub, "chat:#{user_id}")
    end

    context_messages =
      chat_messages
      |> Enum.filter(fn msg ->
        msg.role in ["user", "assistant"] and msg.id != "welcome"
      end)
      |> Enum.take(-10)
      |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)

    date = socket.assigns[:date_str]

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

  # -- PubSub Handlers --

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
    if socket.assigns.chat_session_id do
      ChatBot.create_message(%{
        session_id: socket.assigns.chat_session_id,
        role: "assistant",
        content: summary,
        news_item_ids: ids
      })
    end

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

  # Catch-all for unexpected messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # -- Helpers --

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

  defp welcome_content do
    "How can I help you today? Try one of the suggestions above, or type **/help** for all commands."
  end

  defp welcome_message do
    %{
      id: "welcome",
      role: "assistant",
      content: welcome_content(),
      inserted_at: DateTime.utc_now()
    }
  end

  defp home_json_ld do
    site_url = SEO.site_url()

    Jason.encode!([
      %{
        "@context" => "https://schema.org",
        "@type" => "Organization",
        "name" => "Sports Fan Agent",
        "url" => site_url <> "/",
        "logo" => SEO.absolute_image_url(SEO.default_og_image_path()),
        "description" => SEO.default_description()
      },
      %{
        "@context" => "https://schema.org",
        "@type" => "WebSite",
        "name" => "Sports Fan Agent",
        "url" => site_url <> "/",
        "description" => SEO.default_description()
      }
    ])
  end

  # Template helpers

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

  def sanitize_chat(content) when is_binary(content) do
    HtmlSanitizeEx.strip_tags(content)
  end

  def sanitize_chat(_), do: ""

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
  def skill_placeholder(_), do: "Ask about MLB news, players, or trades..."

  def upload_error_message(:too_large), do: "File is too large (max 1 MB)"
  def upload_error_message(:not_accepted), do: "Only .csv files are accepted"
  def upload_error_message(:too_many_files), do: "Only one file at a time"
  def upload_error_message(_), do: "Upload error"
end
