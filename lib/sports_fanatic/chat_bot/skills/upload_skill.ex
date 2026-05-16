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
            {:reply,
             "Created feed **\"#{feed.name}\"** with #{state.player_count} players and #{state.team_count} teams.",
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
      all_teams = Repo.all(SportsFanatic.Mlb.Team)

      player_names = Enum.map(parsed, & &1.player_name)

      team_abbrs =
        parsed |> Enum.map(& &1.team_abbreviation) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      matched_players = EntityMatcher.match_players(player_names, all_players)
      matched_teams = EntityMatcher.match_teams(team_abbrs, all_teams)

      player_ids = Enum.map(matched_players, & &1.id)
      team_ids = Enum.map(matched_teams, & &1.id)

      # Find unmatched
      matched_player_names = MapSet.new(matched_players, fn p -> String.downcase(p.full_name) end)

      unmatched =
        Enum.reject(player_names, fn name ->
          MapSet.member?(matched_player_names, String.downcase(name))
        end)

      summary =
        "Found **#{length(parsed)}** players in CSV. Matched **#{length(matched_players)}/#{length(player_names)}** players and **#{length(matched_teams)}/#{length(team_abbrs)}** teams."

      summary =
        if unmatched != [] do
          summary <>
            "\n\nCould not find: #{Enum.join(Enum.take(unmatched, 10), ", ")}" <>
            if(length(unmatched) > 10, do: " (+#{length(unmatched) - 10} more)", else: "")
        else
          summary
        end

      {:reply, summary <> "\n\nWhat would you like to name this feed?",
       %{
         skill: :upload,
         step: :await_name,
         player_ids: player_ids,
         team_ids: team_ids,
         player_count: length(matched_players),
         team_count: length(matched_teams)
       }}
    end
  end
end
