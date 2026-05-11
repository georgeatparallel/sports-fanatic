defmodule SportsFanaticWeb.PageController do
  use SportsFanaticWeb, :controller

  def health(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{status: "ok"})
  end

  def home(conn, _params) do
    redirect(conn, to: "/mlb/news")
  end
end
