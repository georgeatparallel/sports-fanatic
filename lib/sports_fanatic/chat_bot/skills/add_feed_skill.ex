defmodule SportsFanatic.ChatBot.Skills.AddFeedSkill do
  @moduledoc """
  Multi-turn skill for creating a new feed. Prompts for a feed name
  then accepts comma-separated player names.
  """

  alias SportsFanatic.Feeds
  alias SportsFanatic.News.EntityMatcher
  alias SportsFanatic.Repo

  def handle(_text, nil, %{current_user: nil}) do
    {:reply, "You need to be logged in to create a feed. Use /register or /login first.", nil}
  end

  def handle(_text, nil, _context) do
    {:reply, "What would you like to name this feed?", %{skill: :add_feed, step: :await_name}}
  end

  def handle(text, %{skill: :add_feed, step: :await_name}, _context) do
    name = String.trim(text)

    cond do
      String.length(name) == 0 ->
        {:reply, "Feed name cannot be empty. Please enter a name:",
         %{skill: :add_feed, step: :await_name}}

      String.length(name) > 100 ->
        {:reply, "Feed name must be 100 characters or less. Please enter a shorter name:",
         %{skill: :add_feed, step: :await_name}}

      true ->
        {:reply,
         "Great! Now enter player names separated by commas (e.g., \"Aaron Judge, Shohei Ohtani, Mookie Betts\"):\n\nOr type /upload to upload a CSV roster instead.",
         %{skill: :add_feed, step: :await_players, name: name}}
    end
  end

  def handle(_text, %{skill: :add_feed, step: :await_players}, %{current_user: nil}) do
    {:reply, "You need to be logged in to create a feed. Use /register or /login first.", nil}
  end

  def handle(text, %{skill: :add_feed, step: :await_players, name: name}, %{
        current_user: user
      }) do
    player_names =
      text
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if player_names == [] do
      {:reply, "No player names found. Please enter comma-separated player names:",
       %{skill: :add_feed, step: :await_players, name: name}}
    else
      all_players = Repo.all(SportsFanatic.Mlb.Player)
      matched = EntityMatcher.match_players(player_names, all_players)
      player_ids = Enum.map(matched, & &1.id)

      # Detect unmatched
      matched_names = MapSet.new(matched, fn p -> String.downcase(p.full_name) end)

      unmatched =
        Enum.reject(player_names, fn name ->
          MapSet.member?(matched_names, String.downcase(name))
        end)

      case Feeds.create_feed(user.id, name, %{player_ids: player_ids}) do
        {:ok, feed} ->
          msg =
            "Created feed **\"#{feed.name}\"** with #{length(matched)}/#{length(player_names)} players matched."

          msg =
            if unmatched != [] do
              msg <> "\n\nCould not find: #{Enum.join(unmatched, ", ")}"
            else
              msg
            end

          {:reply, msg, nil, :feeds_changed}

        {:error, :max_feeds_reached} ->
          {:reply,
           "You have reached the maximum of 10 feeds. Delete a feed first with /manage-feeds.",
           nil}

        {:error, changeset} ->
          error_msg =
            changeset
            |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
            |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)

          {:reply, "Could not create feed: #{error_msg}", nil}
      end
    end
  end
end
