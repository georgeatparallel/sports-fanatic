defmodule SportsFanaticWeb.Plugs.AuthTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Accounts
  alias SportsFanaticWeb.Plugs.{FetchCurrentUser, RequireAuthenticated, SubscriptionGate}

  # --- Helpers ---

  defp unique_email, do: "plug_user_#{System.unique_integer([:positive])}@example.com"

  defp create_user(attrs \\ %{}) do
    defaults = %{email: unique_email(), password: "validpassword123"}
    {:ok, user} = Accounts.register_user(Map.merge(defaults, attrs))
    user
  end

  defp conn_with_session_token(conn, token) do
    conn
    |> init_test_session(%{session_token: token})
  end

  # --- FetchCurrentUser ---

  describe "FetchCurrentUser" do
    test "assigns nil current_user when no session token", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> FetchCurrentUser.call([])

      assert conn.assigns[:current_user] == nil
    end

    test "assigns user when valid session token exists", %{conn: conn} do
      user = create_user()
      {:ok, session} = Accounts.create_session(user)

      conn =
        conn
        |> conn_with_session_token(session.token)
        |> FetchCurrentUser.call([])

      assert conn.assigns[:current_user].id == user.id
    end

    test "assigns nil for invalid session token", %{conn: conn} do
      conn =
        conn
        |> conn_with_session_token("invalid-token")
        |> FetchCurrentUser.call([])

      assert conn.assigns[:current_user] == nil
    end
  end

  # --- RequireAuthenticated ---

  describe "RequireAuthenticated" do
    test "passes through when current_user is set", %{conn: conn} do
      user = create_user()

      conn =
        conn
        |> assign(:current_user, user)
        |> RequireAuthenticated.call([])

      refute conn.halted
    end

    test "halts and redirects to login when no current_user", %{conn: conn} do
      conn =
        conn
        |> assign(:current_user, nil)
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAuthenticated.call([])

      assert conn.halted
      assert redirected_to(conn) =~ "/login"
    end

    test "includes return_to in redirect URL", %{conn: conn} do
      conn =
        %{conn | request_path: "/premium/dashboard"}
        |> assign(:current_user, nil)
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAuthenticated.call([])

      assert redirected_to(conn) =~ "return_to"
      assert redirected_to(conn) =~ "/premium/dashboard"
    end

    test "sets error flash message", %{conn: conn} do
      conn =
        conn
        |> assign(:current_user, nil)
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAuthenticated.call([])

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "log in"
    end
  end

  # --- SubscriptionGate ---

  describe "SubscriptionGate" do
    setup do
      # Ensure the flag exists and is enabled so the gate actually gates
      alias SportsFanatic.FeatureFlags
      alias SportsFanatic.FeatureFlags.FeatureFlag
      alias SportsFanatic.Repo

      flag =
        Repo.get_by(FeatureFlag, key: "subscriptions_enabled") ||
          Repo.insert!(%FeatureFlag{
            key: "subscriptions_enabled",
            enabled: false,
            description: "test"
          })

      Repo.update!(FeatureFlag.update_changeset(flag, %{enabled: true}))
      FeatureFlags.invalidate_cache("subscriptions_enabled")
      on_exit(fn -> FeatureFlags.invalidate_cache("subscriptions_enabled") end)
      :ok
    end

    test "passes through for user with active monthly subscription", %{conn: conn} do
      future = DateTime.utc_now() |> DateTime.add(86_400, :second)

      user = %SportsFanatic.Accounts.User{
        id: Ecto.UUID.generate(),
        subscription_tier: "monthly",
        subscription_expires_at: future
      }

      conn =
        conn
        |> assign(:current_user, user)
        |> init_test_session(%{})
        |> fetch_flash()
        |> SubscriptionGate.call([])

      refute conn.halted
    end

    test "passes through for user with trial subscription", %{conn: conn} do
      user = %SportsFanatic.Accounts.User{
        id: Ecto.UUID.generate(),
        subscription_tier: "trial",
        subscription_expires_at: nil
      }

      result_conn =
        conn
        |> assign(:current_user, user)
        |> init_test_session(%{})
        |> fetch_flash()
        |> SubscriptionGate.call([])

      refute result_conn.halted
    end

    test "halts and redirects to /subscribe for free user", %{conn: conn} do
      user = %SportsFanatic.Accounts.User{
        id: Ecto.UUID.generate(),
        subscription_tier: "free",
        subscription_expires_at: nil
      }

      conn =
        conn
        |> assign(:current_user, user)
        |> init_test_session(%{})
        |> fetch_flash()
        |> SubscriptionGate.call([])

      assert conn.halted
      assert redirected_to(conn) == "/subscribe"
    end

    test "halts and redirects to login when no user", %{conn: conn} do
      conn =
        conn
        |> assign(:current_user, nil)
        |> init_test_session(%{})
        |> fetch_flash()
        |> SubscriptionGate.call([])

      assert conn.halted
      assert redirected_to(conn) =~ "/login"
    end

    test "halts and redirects to /subscribe for expired subscription", %{conn: conn} do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)

      user = %SportsFanatic.Accounts.User{
        id: Ecto.UUID.generate(),
        subscription_tier: "monthly",
        subscription_expires_at: past
      }

      conn =
        conn
        |> assign(:current_user, user)
        |> init_test_session(%{})
        |> fetch_flash()
        |> SubscriptionGate.call([])

      assert conn.halted
      assert redirected_to(conn) == "/subscribe"
    end
  end
end
