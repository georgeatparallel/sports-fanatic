defmodule SportsFanaticWeb.JoshuaController do
  use SportsFanaticWeb, :controller

  alias SportsFanatic.JoshuaAuth
  alias SportsFanaticWeb.Plugs.JoshuaRateLimiter

  require Logger

  def login_form(conn, _params) do
    # If already authenticated, redirect to admin
    if get_session(conn, :joshua_authenticated) == true and
         not JoshuaAuth.session_expired?(get_session(conn, :joshua_authenticated_at)) do
      redirect(conn, to: "/admin")
    else
      conn
      |> put_layout(false)
      |> render(:login, error: nil)
    end
  end

  def login(conn, %{"username" => username, "password" => password}) do
    case JoshuaAuth.verify_credentials(username, password) do
      :ok ->
        Logger.info("Joshua auth: successful login from #{client_ip(conn)}")

        conn
        |> configure_session(renew: true)
        |> put_session(:joshua_authenticated, true)
        |> put_session(:joshua_authenticated_at, System.system_time(:second))
        |> redirect(to: "/admin")

      {:error, _reason} ->
        JoshuaRateLimiter.record_attempt(conn)
        Logger.warning("Joshua auth: failed login attempt from #{client_ip(conn)}")

        conn
        |> put_layout(false)
        |> render(:login, error: "Invalid credentials.")
    end
  end

  def login(conn, _params) do
    conn
    |> put_layout(false)
    |> render(:login, error: "Username and password are required.")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/")
  end

  defp client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",") |> List.first() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
