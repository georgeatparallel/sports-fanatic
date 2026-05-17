defmodule SportsFanatic.ChatBot.Skills.ListFeedsSkill do
  @moduledoc """
  Displays all feeds for the current user.
  """

  alias SportsFanatic.Feeds

  def handle(_text, _skill_state, %{current_user: nil}) do
    {:reply, "You need to be logged in to view your feeds. Use /register or /login first.", nil}
  end

  def handle(_text, _skill_state, %{current_user: user}) do
    feeds = Feeds.list_feeds(user.id)

    if feeds == [] do
      {:reply,
       "You don't have any feeds yet. Use /add-new-feed to create one, or /upload to import a CSV roster.",
       nil}
    else
      lines =
        feeds
        |> Enum.with_index(1)
        |> Enum.map(fn {feed, idx} ->
          status = if feed.is_active, do: "active", else: "inactive"
          player_count = length(feed.player_ids)
          team_count = length(feed.team_ids)

          "#{idx}. **#{feed.name}** -- #{player_count} players, #{team_count} teams (#{status})"
        end)

      msg = "Your feeds:\n\n" <> Enum.join(lines, "\n")
      {:reply, msg, nil}
    end
  end
end
