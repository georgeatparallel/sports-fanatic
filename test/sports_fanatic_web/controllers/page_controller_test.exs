defmodule SportsFanaticWeb.PageControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "AI-Powered MLB Intelligence"
  end
end
