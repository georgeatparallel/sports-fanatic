defmodule SportsFanatic.ChatBot.Skills.LoginSkill do
  @moduledoc """
  Multi-turn inline login skill. Collects email and password
  via chat messages, then authenticates and creates a session.

  Passwords are NOT stored in chat message history.
  """

  alias SportsFanatic.Accounts

  def handle(_text, nil, _context) do
    {:reply,
     "Please enter your **email address**:\n\n_Note: your password will be visible in this chat. For a private form, visit [/login](/login)._",
     %{skill: :login, step: :await_email}}
  end

  def handle(text, %{skill: :login, step: :await_email}, _context) do
    email = String.trim(text) |> String.downcase()

    {:reply, "Enter your **password**:", %{skill: :login, step: :await_password, email: email}}
  end

  def handle(text, %{skill: :login, step: :await_password, email: email}, _context) do
    password = String.trim(text)

    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        case Accounts.create_session(user) do
          {:ok, session} ->
            {:reply_with_auth, "Welcome back! Signing you in...", session.token, user}

          {:error, _} ->
            {:reply, "Authentication succeeded but session creation failed. Please try again.",
             nil}
        end

      {:error, :invalid_credentials} ->
        {:reply, "Invalid email or password. Please try again with /login.", nil}
    end
  end
end
