defmodule SportsFanatic.Accounts.UserTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Accounts.User

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  describe "registration_changeset/2" do
    test "valid with email and password" do
      changeset =
        User.registration_changeset(%User{}, %{email: "test@example.com", password: "password123"})

      assert changeset.valid?
    end

    test "invalid without email" do
      changeset = User.registration_changeset(%User{}, %{password: "password123"})
      refute changeset.valid?
      assert %{email: _} = errors_on(changeset)
    end

    test "invalid without password" do
      changeset = User.registration_changeset(%User{}, %{email: "test@example.com"})
      refute changeset.valid?
      assert %{password: _} = errors_on(changeset)
    end

    test "invalid with bad email format" do
      changeset =
        User.registration_changeset(%User{}, %{email: "notanemail", password: "password123"})

      refute changeset.valid?
      assert %{email: ["must be a valid email"]} = errors_on(changeset)
    end

    test "invalid with password too short" do
      changeset =
        User.registration_changeset(%User{}, %{email: "test@example.com", password: "short"})

      refute changeset.valid?
      assert %{password: _} = errors_on(changeset)
    end

    test "invalid with password too long (> 72 chars)" do
      long_password = String.duplicate("a", 73)

      changeset =
        User.registration_changeset(%User{}, %{email: "test@example.com", password: long_password})

      refute changeset.valid?
    end

    test "invalid with email too long (> 320 chars)" do
      long_email = String.duplicate("a", 315) <> "@b.com"

      changeset =
        User.registration_changeset(%User{}, %{email: long_email, password: "password123"})

      refute changeset.valid?
    end

    test "hashes the password" do
      changeset =
        User.registration_changeset(%User{}, %{email: "test@example.com", password: "password123"})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :password_hash) != nil
      refute Ecto.Changeset.get_change(changeset, :password_hash) == "password123"
    end

    test "clears the virtual password field after hashing" do
      changeset =
        User.registration_changeset(%User{}, %{email: "test@example.com", password: "password123"})

      assert Ecto.Changeset.get_change(changeset, :password) == nil
    end

    test "accepts optional display_name" do
      attrs = %{email: "test@example.com", password: "password123", display_name: "Test User"}
      changeset = User.registration_changeset(%User{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :display_name) == "Test User"
    end
  end

  describe "subscription_changeset/2" do
    test "updates stripe_customer_id" do
      user = %User{id: "some-uuid"}
      changeset = User.subscription_changeset(user, %{stripe_customer_id: "cus_123"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :stripe_customer_id) == "cus_123"
    end

    test "updates subscription_tier" do
      user = %User{}
      changeset = User.subscription_changeset(user, %{subscription_tier: "monthly"})
      assert Ecto.Changeset.get_change(changeset, :subscription_tier) == "monthly"
    end

    test "updates subscription_expires_at" do
      # Truncate to seconds to avoid microsecond precision mismatch with :utc_datetime type
      expires =
        DateTime.utc_now()
        |> DateTime.add(30 * 86_400, :second)
        |> DateTime.truncate(:second)

      user = %User{}
      changeset = User.subscription_changeset(user, %{subscription_expires_at: expires})
      assert Ecto.Changeset.get_change(changeset, :subscription_expires_at) == expires
    end
  end

  describe "defaults" do
    test "subscription_tier defaults to free" do
      user = %User{}
      assert user.subscription_tier == "free"
    end

    test "is_admin defaults to false" do
      user = %User{}
      assert user.is_admin == false
    end
  end
end
