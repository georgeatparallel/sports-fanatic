defmodule SportsFanatic.ChatBot.Skills.HelpSkill do
  @moduledoc """
  Displays available chatbot commands and features.
  """

  @help_text """
  Here are the commands I understand:

  **/help** -- Show this help message
  **/register** -- Create a new account (inline)
  **/login** -- Sign in to your account (inline)
  **/add-new-feed** -- Create a personalized news feed
  **/list-feeds** -- Show your saved feeds
  **/manage-feeds** -- Rename, delete, or reorder feeds
  **/upload** -- Upload a CSV roster to create a feed
  **/cancel** -- Cancel the current operation

  You can also ask me anything about MLB news, players, or teams and I will research it for you.

  **Tips:**
  - Create a feed to see personalized news above the general feed
  - Upload a CSV from any fantasy platform (Fantrax, Yahoo, ESPN, CBS, etc.)
  - Switch between feeds using the dropdown above the news
  """

  def handle(_text, _skill_state, _context) do
    {:reply, @help_text, nil}
  end
end
