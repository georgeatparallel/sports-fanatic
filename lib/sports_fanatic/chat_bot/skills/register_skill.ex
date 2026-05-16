defmodule SportsFanatic.ChatBot.Skills.RegisterSkill do
  @moduledoc """
  Multi-turn inline registration skill. Collects email and password
  via chat messages, then creates the user account and session.

  Passwords are NOT stored in chat message history.
  """

  alias SportsFanatic.Accounts

  def handle(_text, nil, _context) do
    {:reply,
     "Let's create your account. Please enter your **email address**:\n\n_Note: your password will be visible in this chat. For a private form, visit [/register](/register)._",
     %{skill: :register, step: :await_email}}
  end

  def handle(text, %{skill: :register, step: :await_email}, _context) do
    email = String.trim(text) |> String.downcase()

    if valid_email?(email) do
      {:reply, "Got it. Now choose a **password** (minimum 8 characters):",
       %{skill: :register, step: :await_password, email: email}}
    else
      {:reply, "That doesn't look like a valid email. Please enter a valid email address:",
       %{skill: :register, step: :await_email}}
    end
  end

  def handle(text, %{skill: :register, step: :await_password, email: email}, _context) do
    password = String.trim(text)

    case Accounts.register_user(%{"email" => email, "password" => password}) do
      {:ok, user} ->
        case Accounts.create_session(user) do
          {:ok, session} ->
            {:reply_with_auth, "Account created! Signing you in...", session.token, user}

          {:error, _} ->
            {:reply,
             "Account created but could not sign in automatically. Please use [/login](/login).",
             nil}
        end

      {:error, changeset} ->
        errors = format_errors(changeset)
        {:reply, "Could not create account: #{errors}\n\nPlease try again with /register.", nil}
    end
  end

  defp valid_email?(email) do
    String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join(", ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end
