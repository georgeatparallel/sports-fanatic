defmodule SportsFanatic.ChatBot.Skills.UploadSkill do
  @moduledoc """
  Handles CSV roster upload flow. Sets the skill state to show
  the file upload UI, then processes the uploaded CSV to create a feed.
  """

  alias SportsFanatic.Feeds
  alias SportsFanatic.Feeds.CsvParser
  alias SportsFanatic.News.EntityMatcher
  alias SportsFanatic.Repo

  def handle(_text, nil, %{current_user: nil}) do
    {:reply, "You need to be logged in to upload a roster. Use /register or /login first.", nil}
  end

  def handle(_text, nil, _context) do
    {:reply,
     "Select a CSV file to upload. Supported formats: Fantrax, Yahoo, ESPN, CBS, and other fantasy platforms.",
     %{skill: :upload, step: :await_file}}
  end

  def handle(_text, %{skill: :upload, step: :await_name}, %{current_user: nil}) do
    {:reply, "You need to be logged in to save a feed. Use /register or /login first.", nil}
  end

  def handle(text, %{skill: :upload, step: :await_name} = state, %{current_user: user}) do
    name = String.trim(text)

    cond do
      String.length(name) == 0 ->
        {:reply, "Feed name cannot be empty. Please enter a name:", state}

      String.length(name) > 100 ->
        {:reply, "Feed name must be 100 characters or less:", state}

      true ->
        case Feeds.create_feed(user.id, name, %{
               player_ids: state.player_ids,
               team_ids: state.team_ids
             }) do
          {:ok, feed} ->
            # Kick off immediate feed research in the background
            %{"feed_ids" => [feed.id]}
            |> SportsFanatic.Workers.FeedResearchWorker.new()
            |> Oban.insert()

            {:reply,
             "Created feed **\"#{feed.name}\"** with #{state.player_count} players and #{state.team_count} teams. Researching your players now — news will appear shortly!",
             nil, :feeds_changed}

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

  @doc """
  Called after CSV binary is consumed from the upload.
  `csv_binary` is the raw file content.
  """
  def process_csv(csv_binary, %{current_user: _user}) do
    parsed = CsvParser.parse(csv_binary)

    if parsed == [] do
      {:reply,
       "Could not find any player names in the CSV. Please check the file format and try again with /upload.",
       nil}
    else
      # Resolve players against database
      all_players = Repo.all(SportsFanatic.Mlb.Player)

      player_names = Enum.map(parsed, & &1.player_name)

      matched_players = EntityMatcher.match_players(player_names, all_players)
      player_ids = Enum.map(matched_players, & &1.id)

      # Find unmatched players
      matched_player_names = MapSet.new(matched_players, fn p -> String.downcase(p.full_name) end)

      unmatched =
        Enum.reject(player_names, fn name ->
          MapSet.member?(matched_player_names, String.downcase(name))
        end)

      summary = "Found **#{length(parsed)}** players in CSV. Matched **#{length(matched_players)}** of **#{length(player_names)}** against our database."

      summary =
        if unmatched != [] do
          names = Enum.take(unmatched, 10) |> Enum.join(", ")
          more = if length(unmatched) > 10, do: " (+#{length(unmatched) - 10} more)", else: ""

          summary <>
            "\n\nNot in our player database: #{names}#{more}" <>
            "\n*(These players may not be on an active MLB roster yet, or their name may be spelled differently.)*"
        else
          summary
        end

      {:reply, summary <> "\n\nWhat would you like to name this feed?",
       %{
         skill: :upload,
         step: :await_name,
         player_ids: player_ids,
         team_ids: [],
         player_count: length(matched_players),
         team_count: 0
       }}
    end
  end
end
