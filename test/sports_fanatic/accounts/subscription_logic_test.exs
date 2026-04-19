defmodule SportsFanatic.Accounts.SubscriptionLogicTest do
  @moduledoc """
  Unit tests for `Accounts.has_active_subscription?/1`.
  These tests do not require a database connection.
  """
  use ExUnit.Case, async: true

  alias SportsFanatic.Accounts
  alias SportsFanatic.Accounts.User

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

    test "returns false for yearly tier with past expiry" do
      past = DateTime.utc_now() |> DateTime.add(-86_400, :second)
      user = %User{subscription_tier: "yearly", subscription_expires_at: past}
      refute Accounts.has_active_subscription?(user)
    end
  end
end
