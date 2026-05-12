defmodule SportsFanaticWeb.PageControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  test "GET / renders homepage with 200 status", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200)
  end
end
