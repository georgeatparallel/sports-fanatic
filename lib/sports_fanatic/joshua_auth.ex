defmodule SportsFanatic.JoshuaAuth do
  @moduledoc """
  Authentication module for the /joshua admin gate.

  Validates credentials against JOSHUA_USERNAME and JOSHUA_PASSWORD
  environment variables using timing-safe comparison.
  """

  require Logger

  @doc """
  Verifies the provided username and password against configured credentials.

  Uses `Plug.Crypto.secure_compare/2` to prevent timing attacks.
  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec verify_credentials(String.t(), String.t()) ::
          :ok | {:error, :invalid_credentials | :not_configured}
  def verify_credentials(username, password) when is_binary(username) and is_binary(password) do
    expected_username = configured_username()
    expected_password = configured_password()

    if is_nil(expected_username) or is_nil(expected_password) or
         expected_username == "" or expected_password == "" do
      Logger.error("Joshua auth: JOSHUA_USERNAME or JOSHUA_PASSWORD not configured")
      {:error, :not_configured}
    else
      username_match = Plug.Crypto.secure_compare(username, expected_username)
      password_match = Plug.Crypto.secure_compare(password, expected_password)

      if username_match and password_match do
        :ok
      else
        Logger.warning(
          "Joshua auth: failed login attempt for username=#{inspect(String.slice(username, 0, 8))}..."
        )

        {:error, :invalid_credentials}
      end
    end
  end

  def verify_credentials(_, _), do: {:error, :invalid_credentials}

  @doc """
  Checks whether the joshua session has expired (24-hour TTL).
  """
  @spec session_expired?(integer() | nil) :: boolean()
  def session_expired?(nil), do: true

  def session_expired?(authenticated_at) when is_integer(authenticated_at) do
    now = System.system_time(:second)
    elapsed = now - authenticated_at
    elapsed > session_ttl_seconds()
  end

  def session_expired?(_), do: true

  @doc """
  Returns the session TTL in seconds (24 hours).
  """
  @spec session_ttl_seconds() :: integer()
  def session_ttl_seconds, do: 86_400

  defp configured_username do
    Application.get_env(:sports_fanatic, :joshua_username) ||
      System.get_env("JOSHUA_USERNAME")
  end

  defp configured_password do
    Application.get_env(:sports_fanatic, :joshua_password) ||
      System.get_env("JOSHUA_PASSWORD")
  end
end
