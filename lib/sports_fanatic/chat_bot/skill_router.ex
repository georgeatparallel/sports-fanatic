defmodule SportsFanatic.ChatBot.SkillRouter do
  @moduledoc """
  Routes chat messages to skill handlers or falls through to the
  NewsAgent for research queries.

  Handles slash commands and natural language intent detection.
  Multi-turn conversation state is passed in and returned from
  skill handlers.
  """

  @doc """
  Routes a chat message to the appropriate handler.

  Returns:
    - `{:skill, skill_name}` — start a new skill
    - `{:continue, skill_name, text}` — continue an active multi-turn skill
    - `{:agent, text}` — pass through to the NewsAgent
  """
  def route(text, skill_state) do
    text = String.trim(text)

    cond do
      # Cancel active skill
      skill_state != nil and text in ["/cancel", "cancel", "nevermind", "never mind"] ->
        {:skill, :cancel}

      # Continue active multi-turn skill
      skill_state != nil ->
        {:continue, skill_state.skill, text}

      # Slash commands
      slash_command?(text, "/help") ->
        {:skill, :help}

      slash_command?(text, "/register") ->
        {:skill, :register}

      slash_command?(text, "/login") ->
        {:skill, :login}

      slash_command?(text, "/add-new-feed") ->
        {:skill, :add_feed}

      slash_command?(text, "/list-feeds") ->
        {:skill, :list_feeds}

      slash_command?(text, "/manage-feeds") ->
        {:skill, :manage_feeds}

      slash_command?(text, "/upload") ->
        {:skill, :upload}

      # Natural language intents
      matches_intent?(text, ["help", "commands", "what can you do"]) ->
        {:skill, :help}

      matches_intent?(text, ["register", "signup", "sign up", "create account"]) ->
        {:skill, :register}

      matches_intent?(text, ["log in", "login", "sign in"]) ->
        {:skill, :login}

      matches_intent?(text, ["new feed", "add feed", "create feed", "create a feed"]) ->
        {:skill, :add_feed}

      matches_intent?(text, ["list feeds", "show feeds", "my feeds", "show my feeds"]) ->
        {:skill, :list_feeds}

      matches_intent?(text, ["manage feeds", "edit feed", "delete feed", "rename feed"]) ->
        {:skill, :manage_feeds}

      matches_intent?(text, ["upload", "csv", "roster", "import roster", "upload csv"]) ->
        {:skill, :upload}

      # Default: pass to agent
      true ->
        {:agent, text}
    end
  end

  defp slash_command?(text, command) do
    String.starts_with?(text, command)
  end

  defp matches_intent?(text, phrases) do
    lower = String.downcase(text)

    Enum.any?(phrases, fn phrase ->
      String.contains?(lower, phrase)
    end)
  end
end
