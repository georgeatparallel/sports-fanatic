defmodule SportsFanaticWeb.Plugs.RequireAdminTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanaticWeb.Plugs.RequireAdmin
  alias SportsFanatic.Accounts.User

  describe "RequireAdmin.call/2" do
    test "passes through when current_user has is_admin true", %{conn: conn} do
      user = %User{id: Ecto.UUID.generate(), is_admin: true}

      conn =
        conn
        |> assign(:current_user, user)
        |> RequireAdmin.call([])

      refute conn.halted
    end

    test "halts and redirects to / when current_user is nil", %{conn: conn} do
      conn =
        conn
        |> assign(:current_user, nil)
        |> fetch_session()
        |> fetch_flash()
        |> RequireAdmin.call([])

      assert conn.halted
      assert redirected_to(conn) == "/"
    end

    test "halts and redirects to / when current_user has is_admin false", %{conn: conn} do
      user = %User{id: Ecto.UUID.generate(), is_admin: false}

      conn =
        conn
        |> assign(:current_user, user)
        |> fetch_session()
        |> fetch_flash()
        |> RequireAdmin.call([])

      assert conn.halted
      assert redirected_to(conn) == "/"
    end

    test "sets Unauthorized error flash when is_admin is false", %{conn: conn} do
      user = %User{id: Ecto.UUID.generate(), is_admin: false}

      conn =
        conn
        |> assign(:current_user, user)
        |> fetch_session()
        |> fetch_flash()
        |> RequireAdmin.call([])

      assert get_flash(conn, :error) == "Unauthorized."
    end

    test "sets Unauthorized error flash when current_user is nil", %{conn: conn} do
      conn =
        conn
        |> assign(:current_user, nil)
        |> fetch_session()
        |> fetch_flash()
        |> RequireAdmin.call([])

      assert get_flash(conn, :error) == "Unauthorized."
    end

    test "does not set flash when admin user passes through", %{conn: conn} do
      user = %User{id: Ecto.UUID.generate(), is_admin: true}

      conn =
        conn
        |> assign(:current_user, user)
        |> fetch_session()
        |> fetch_flash()
        |> RequireAdmin.call([])

      assert get_flash(conn, :error) == nil
    end
  end
end
