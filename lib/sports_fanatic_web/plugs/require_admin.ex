defmodule SportsFanaticWeb.Plugs.RequireAdmin do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{is_admin: true} -> conn
      _ ->
        conn
        |> put_flash(:error, "Unauthorized.")
        |> redirect(to: "/")
        |> halt()
    end
  end
end
