defmodule SportsFanatic.ChatBot.Skills.ManageFeedsSkill do
  @moduledoc """
  Multi-turn skill for managing existing feeds: rename, delete, or toggle active.
  """

  alias SportsFanatic.Feeds

  def handle(_text, nil, %{current_user: nil}) do
    {:reply, "You need to be logged in to manage feeds. Use /register or /login first.", nil}
  end

  def handle(_text, nil, %{current_user: user}) do
    feeds = Feeds.list_feeds(user.id)

    if feeds == [] do
      {:reply, "You don't have any feeds to manage. Use /add-new-feed to create one.", nil}
    else
      lines =
        feeds
        |> Enum.with_index(1)
        |> Enum.map(fn {feed, idx} ->
          "#{idx}. #{feed.name} (#{length(feed.player_ids)} players)"
        end)

      msg =
        "Which feed would you like to manage? Enter the number:\n\n" <> Enum.join(lines, "\n")

      {:reply, msg, %{skill: :manage_feeds, step: :await_selection, feeds: feeds}}
    end
  end

  def handle(text, %{skill: :manage_feeds, step: :await_selection, feeds: feeds}, _context) do
    case Integer.parse(String.trim(text)) do
      {num, _} when num >= 1 and num <= length(feeds) ->
        feed = Enum.at(feeds, num - 1)

        {:reply,
         "Selected: **#{feed.name}**\n\nWhat would you like to do?\n1. Rename\n2. Delete\n3. Toggle active/inactive",
         %{skill: :manage_feeds, step: :await_action, feed_id: feed.id, feed_name: feed.name}}

      _ ->
        {:reply, "Please enter a number between 1 and #{length(feeds)}.",
         %{skill: :manage_feeds, step: :await_selection, feeds: feeds}}
    end
  end

  def handle(
        text,
        %{skill: :manage_feeds, step: :await_action, feed_id: feed_id, feed_name: feed_name},
        %{current_user: user}
      ) do
    choice = String.trim(text) |> String.downcase()

    cond do
      choice in ["1", "rename"] ->
        {:reply, "Enter a new name for **#{feed_name}**:",
         %{skill: :manage_feeds, step: :await_rename, feed_id: feed_id}}

      choice in ["2", "delete"] ->
        case Feeds.delete_feed(feed_id, user.id) do
          {:ok, _} ->
            {:reply, "Feed **#{feed_name}** deleted.", nil, :feeds_changed}

          {:error, _} ->
            {:reply, "Could not delete feed.", nil}
        end

      choice in ["3", "toggle"] ->
        feed = Feeds.get_feed!(feed_id, user.id)
        new_active = !feed.is_active
        label = if new_active, do: "active", else: "inactive"

        case Feeds.update_feed(feed, user.id, %{is_active: new_active}) do
          {:ok, _} ->
            {:reply, "Feed **#{feed.name}** is now **#{label}**.", nil, :feeds_changed}

          {:error, _} ->
            {:reply, "Could not update feed.", nil}
        end

      true ->
        {:reply, "Please enter 1 (rename), 2 (delete), or 3 (toggle).",
         %{skill: :manage_feeds, step: :await_action, feed_id: feed_id, feed_name: feed_name}}
    end
  end

  def handle(text, %{skill: :manage_feeds, step: :await_rename, feed_id: feed_id}, %{
        current_user: user
      }) do
    new_name = String.trim(text)

    if String.length(new_name) == 0 or String.length(new_name) > 100 do
      {:reply, "Name must be between 1 and 100 characters. Enter a new name:",
       %{skill: :manage_feeds, step: :await_rename, feed_id: feed_id}}
    else
      feed = Feeds.get_feed!(feed_id, user.id)

      case Feeds.update_feed(feed, user.id, %{name: new_name}) do
        {:ok, updated} ->
          {:reply, "Feed renamed to **#{updated.name}**.", nil, :feeds_changed}

        {:error, _} ->
          {:reply, "Could not rename feed. The name may already be in use.", nil}
      end
    end
  end
end
