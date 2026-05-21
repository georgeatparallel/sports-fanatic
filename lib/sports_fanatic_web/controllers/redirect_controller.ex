defmodule SportsFanaticWeb.RedirectController do
  @moduledoc """
  Permanent (301) redirects for renamed/legacy URLs.

  Currently hosts the legacy `/mlb/lineups/:date` → `/mlb/players/:date`
  rename. The 301 status signals to crawlers that the canonical URL has
  moved permanently; external backlinks and bookmarks continue to work
  via this single hop. Mirrors the pattern of
  `SportsFanaticWeb.PredictionsRedirectController` (which handles the
  0-segment `/mlb/players` → `/predictions` redirect).
  """

  use SportsFanaticWeb, :controller

  @doc """
  301 redirect from the legacy `/mlb/lineups/:date` URL to the renamed
  `/mlb/players/:date` URL. Preserves the `:date` param verbatim.

  Security note: the target is a relative path (`to: "/mlb/players/..."`),
  never a fully-qualified URL, so `Phoenix.Controller.redirect/2` enforces
  same-origin and prevents open-redirect abuse via the `:date` param.
  """
  @spec lineups_to_players(Plug.Conn.t(), %{String.t() => String.t()}) :: Plug.Conn.t()
  def lineups_to_players(conn, %{"date" => date_str}) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: "/mlb/players/#{date_str}")
  end
end
