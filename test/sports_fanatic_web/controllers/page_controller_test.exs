defmodule SportsFanaticWeb.PageControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  test "GET / redirects to /mlb/news", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/mlb/news"
  end
end
