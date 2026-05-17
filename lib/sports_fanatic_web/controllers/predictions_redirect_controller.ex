defmodule SportsFanaticWeb.PredictionsRedirectController do
  @moduledoc "301-redirect controller for old /mlb/players index."

  use SportsFanaticWeb, :controller

  def redirect_to_predictions(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: "/predictions")
  end
end
