defmodule SportsFanaticWeb.Plugs.RequireAdminTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Accounts.User
  alias SportsFanaticWeb.Plugs.RequireAdmin

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
        |> init_test_session(%{})
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
        |> init_test_session(%{})
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
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAdmin.call([])

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Unauthorized."
    end

    test "sets Unauthorized error flash when current_user is nil", %{conn: conn} do
      conn =
        conn
        |> assign(:current_user, nil)
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAdmin.call([])

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Unauthorized."
    end

    test "does not set flash when admin user passes through", %{conn: conn} do
      user = %User{id: Ecto.UUID.generate(), is_admin: true}

      conn =
        conn
        |> assign(:current_user, user)
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAdmin.call([])

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == nil
    end
  end
end
