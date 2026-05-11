defmodule SportsFanaticWeb.Plugs.RequireJoshuaTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanaticWeb.Plugs.RequireJoshua

  describe "call/2" do
    test "redirects to /joshua when not authenticated", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireJoshua.call([])

      assert redirected_to(conn) == "/joshua"
      assert conn.halted
    end

    test "redirects when session flag is false", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{joshua_authenticated: false})
        |> fetch_flash()
        |> RequireJoshua.call([])

      assert redirected_to(conn) == "/joshua"
      assert conn.halted
    end

    test "redirects when session is expired", %{conn: conn} do
      expired_at = System.system_time(:second) - 86_500

      conn =
        conn
        |> init_test_session(%{joshua_authenticated: true, joshua_authenticated_at: expired_at})
        |> fetch_flash()
        |> RequireJoshua.call([])

      assert redirected_to(conn) == "/joshua"
      assert conn.halted
    end

    test "allows access when authenticated and not expired", %{conn: conn} do
      recent = System.system_time(:second) - 100

      conn =
        conn
        |> init_test_session(%{joshua_authenticated: true, joshua_authenticated_at: recent})
        |> fetch_flash()
        |> RequireJoshua.call([])

      refute conn.halted
    end
  end
end
