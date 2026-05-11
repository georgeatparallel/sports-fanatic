defmodule SportsFanaticWeb.Plugs.RequireJoshua do
  @moduledoc """
  Plug that enforces Joshua authentication for admin routes.

  Checks the session for `:joshua_authenticated` flag and
  `:joshua_authenticated_at` timestamp. Sessions expire after 24 hours.

  Unauthenticated requests are redirected to `/joshua`.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias SportsFanatic.JoshuaAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    authenticated = get_session(conn, :joshua_authenticated)
    authenticated_at = get_session(conn, :joshua_authenticated_at)

    if authenticated == true and not JoshuaAuth.session_expired?(authenticated_at) do
      conn
    else
      conn
      |> clear_session()
      |> put_flash(:error, "Admin access requires authentication.")
      |> redirect(to: "/joshua")
      |> halt()
    end
  end
end
