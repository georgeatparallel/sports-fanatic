defmodule SportsFanaticWeb.LineupControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  describe "GET /mlb/lineups/:date" do
    test "renders 200 for a valid date", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/2026-04-19")
      assert html_response(conn, 200) =~ "Lineups"
    end

    test "renders page title with the formatted date", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/2026-04-19")
      assert html_response(conn, 200) =~ "2026"
    end

    test "returns 500 for an invalid date format" do
      # Date.from_iso8601! raises for invalid dates; controller does not rescue
      conn = Phoenix.ConnTest.build_conn()

      assert_raise ArgumentError, fn ->
        get(conn, "/mlb/lineups/not-a-date")
      end
    end
  end
end
