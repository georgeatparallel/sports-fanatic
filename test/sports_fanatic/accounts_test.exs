defmodule SportsFanatic.AccountsTest do
  use SportsFanatic.DataCase, async: true

  alias SportsFanatic.Accounts
  alias SportsFanatic.Accounts.{User, Session}

  # --- Helpers ---

  defp unique_email, do: "user_#{System.unique_integer([:positive])}@example.com"

  defp register_user(attrs \\ %{}) do
    defaults = %{email: unique_email(), password: "validpassword123"}
    {:ok, user} = Accounts.register_user(Map.merge(defaults, attrs))
    user
  end

  # --- Registration ---

  describe "register_user/1" do
    test "creates a user with hashed password" do
      email = unique_email()
      assert {:ok, user} = Accounts.register_user(%{email: email, password: "mypassword99"})
      assert user.email == email
      assert user.password_hash != nil
      assert user.password_hash != "mypassword99"
    end

    test "returns error changeset for duplicate email" do
      email = unique_email()
      {:ok, _user} = Accounts.register_user(%{email: email, password: "password123"})

      assert {:error, changeset} = Accounts.register_user(%{email: email, password: "otherpass1"})
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end

    test "returns error changeset for invalid email" do
      assert {:error, changeset} = Accounts.register_user(%{email: "bademail", password: "password123"})
      assert %{email: _} = errors_on(changeset)
    end

    test "returns error changeset for short password" do
      assert {:error, changeset} = Accounts.register_user(%{email: unique_email(), password: "short"})
      assert %{password: _} = errors_on(changeset)
    end

    test "normalizes email to lowercase on lookup" do
      email = unique_email()
      {:ok, user} = Accounts.register_user(%{email: email, password: "password123"})
      assert Accounts.get_user_by_email(String.upcase(email)) == user
    end

    test "defaults subscription_tier to free" do
      {:ok, user} = Accounts.register_user(%{email: unique_email(), password: "password123"})
      assert user.subscription_tier == "free"
    end
  end

  # --- Authentication ---

  describe "authenticate_user/2" do
    test "returns user for correct credentials" do
      email = unique_email()
      _user = register_user(%{email: email, password: "correctpassword"})

      assert {:ok, authed_user} = Accounts.authenticate_user(email, "correctpassword")
      assert authed_user.email == email
    end

    test "returns error for wrong password" do
      email = unique_email()
      register_user(%{email: email, password: "correctpassword"})

      assert {:error, :invalid_credentials} = Accounts.authenticate_user(email, "wrongpassword")
    end

    test "returns error for non-existent user" do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("nobody@example.com", "password")
    end

    test "returns error for empty email" do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("", "password")
    end
  end

  # --- Session Management ---

  describe "create_session/2" do
    test "creates a session with a token" do
      user = register_user()
      assert {:ok, session} = Accounts.create_session(user)
      assert session.token != nil
      assert session.user_id == user.id
    end

    test "session expires 30 days in the future" do
      user = register_user()
      {:ok, session} = Accounts.create_session(user)
      diff = DateTime.diff(session.expires_at, DateTime.utc_now(), :second)
      # Should be approximately 30 days in seconds (allowing 5s variance)
      assert diff > 30 * 24 * 3600 - 5
      assert diff <= 30 * 24 * 3600 + 5
    end

    test "stores conn_info when provided" do
      user = register_user()
      conn_info = %{ip_address: "127.0.0.1", user_agent: "Mozilla/5.0"}
      {:ok, session} = Accounts.create_session(user, conn_info)
      assert session.ip_address == "127.0.0.1"
    end
  end

  describe "get_user_by_session_token/1" do
    test "returns user for valid non-expired token" do
      user = register_user()
      {:ok, session} = Accounts.create_session(user)
      found_user = Accounts.get_user_by_session_token(session.token)
      assert found_user.id == user.id
    end

    test "returns nil for invalid token" do
      assert Accounts.get_user_by_session_token("invalid-token") == nil
    end

    test "returns nil for expired session" do
      user = register_user()

      # Manually insert an expired session
      expired_at = DateTime.utc_now() |> DateTime.add(-1, :second)
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()

      Repo.insert!(%Session{
        user_id: user.id,
        token: token,
        expires_at: expired_at
      })

      assert Accounts.get_user_by_session_token(token) == nil
    end
  end

  describe "delete_session/1" do
    test "removes the session from the database" do
      user = register_user()
      {:ok, session} = Accounts.create_session(user)
      assert {1, nil} = Accounts.delete_session(session.token)
      assert Accounts.get_user_by_session_token(session.token) == nil
    end

    test "is idempotent for non-existent token" do
      assert {0, nil} = Accounts.delete_session("nonexistent-token")
    end
  end

  describe "delete_expired_sessions/0" do
    test "deletes expired sessions" do
      user = register_user()
      expired_at = DateTime.utc_now() |> DateTime.add(-3600, :second)

      expired_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()

      Repo.insert!(%Session{
        user_id: user.id,
        token: expired_token,
        expires_at: expired_at
      })

      {:ok, active_session} = Accounts.create_session(user)

      Accounts.delete_expired_sessions()

      assert Accounts.get_user_by_session_token(expired_token) == nil
      assert Accounts.get_user_by_session_token(active_session.token) != nil
    end
  end

  # --- has_active_subscription? ---

  describe "has_active_subscription?/1" do
    test "returns false for free tier" do
      user = %User{subscription_tier: "free", subscription_expires_at: nil}
      refute Accounts.has_active_subscription?(user)
    end

    test "returns true for monthly tier without expiry" do
      user = %User{subscription_tier: "monthly", subscription_expires_at: nil}
      assert Accounts.has_active_subscription?(user)
    end

    test "returns true for yearly tier with future expiry" do
      future = DateTime.utc_now() |> DateTime.add(3600, :second)
      user = %User{subscription_tier: "yearly", subscription_expires_at: future}
      assert Accounts.has_active_subscription?(user)
    end

    test "returns false for monthly tier with past expiry" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)
      user = %User{subscription_tier: "monthly", subscription_expires_at: past}
      refute Accounts.has_active_subscription?(user)
    end

    test "returns true for trial tier" do
      user = %User{subscription_tier: "trial", subscription_expires_at: nil}
      assert Accounts.has_active_subscription?(user)
    end
  end

  # --- update_user_subscription ---

  describe "update_user_subscription/2" do
    test "updates subscription tier" do
      user = register_user()
      {:ok, updated} = Accounts.update_user_subscription(user, %{subscription_tier: "monthly"})
      assert updated.subscription_tier == "monthly"
    end

    test "sets stripe_customer_id" do
      user = register_user()
      {:ok, updated} = Accounts.update_user_subscription(user, %{stripe_customer_id: "cus_abc123"})
      assert updated.stripe_customer_id == "cus_abc123"
    end
  end
end
