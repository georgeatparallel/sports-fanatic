defmodule SportsFanaticWeb.XOAuthController do
  @moduledoc """
  OAuth 2.0 PKCE flow for the org X account.

  Both endpoints sit behind the `:require_joshua` admin pipeline:

    * `GET /admin/x/oauth/start` — generates a verifier + state, stores both
      in the session, redirects to X's authorize URL.
    * `GET /admin/x/oauth/callback` — validates state, exchanges code for
      tokens via `SportsFanatic.X.exchange_code/2`, redirects to
      `/admin#x_agent`.

  PKCE manually implemented (no `assent` dep).
  """

  use SportsFanaticWeb, :controller

  require Logger
  alias SportsFanatic.X

  def start(conn, _params) do
    verifier = X.generate_verifier()
    state = X.generate_state()
    url = X.authorize_url(state, verifier)

    conn
    |> put_session(:x_oauth_verifier, verifier)
    |> put_session(:x_oauth_state, state)
    |> redirect(external: url)
  end

  def callback(conn, %{"code" => code, "state" => state})
      when is_binary(code) and is_binary(state) do
    expected = get_session(conn, :x_oauth_state)
    verifier = get_session(conn, :x_oauth_verifier)

    cond do
      not is_binary(expected) or not is_binary(verifier) ->
        Logger.warning("X OAuth callback missing session state")

        conn
        |> put_flash(:error, "X OAuth session expired. Please try connecting again.")
        |> redirect(to: "/admin")

      not secure_compare(expected, state) ->
        Logger.warning("X OAuth callback state mismatch")

        conn
        |> put_flash(:error, "OAuth state validation failed. Please try connecting again.")
        |> redirect(to: "/admin")

      true ->
        case X.exchange_code(code, verifier) do
          {:ok, _creds} ->
            conn
            |> delete_session(:x_oauth_verifier)
            |> delete_session(:x_oauth_state)
            |> put_flash(:info, "X account connected successfully.")
            |> redirect(to: "/admin#x_agent")

          {:error, reason} ->
            Logger.warning("X OAuth exchange_code failed: #{inspect(reason)}")

            conn
            |> put_flash(:error, "Connecting X failed. Please retry.")
            |> redirect(to: "/admin#x_agent")
        end
    end
  end

  def callback(conn, %{"error" => err} = params) do
    Logger.warning(
      "X OAuth callback returned error: #{inspect(err)} params=#{inspect(Map.drop(params, ["error_description"]))}"
    )

    conn
    |> put_flash(:error, "X authorization was cancelled or denied.")
    |> redirect(to: "/admin#x_agent")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Invalid OAuth callback.")
    |> redirect(to: "/admin")
  end

  # Constant-time string compare to avoid timing oracles on the state token.
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) and byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  rescue
    _ -> Plug.Crypto.secure_compare(a, b)
  end

  defp secure_compare(_, _), do: false
end
