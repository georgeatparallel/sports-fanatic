defmodule SportsFanatic.BillingTest do
  use SportsFanatic.DataCase, async: true

  alias SportsFanatic.Billing
  alias SportsFanatic.Accounts
  alias SportsFanatic.Billing.Subscription

  defp unique_email, do: "billing_test_#{System.unique_integer([:positive])}@example.com"

  defp create_user do
    {:ok, user} = Accounts.register_user(%{email: unique_email(), password: "testpassword123"})
    user
  end

  defp create_subscription(user, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    now = DateTime.utc_now()

    defaults = %{
      user_id: user.id,
      stripe_subscription_id: "sub_#{n}",
      stripe_price_id: "price_monthly",
      plan: "monthly",
      status: "active",
      current_period_start: now,
      current_period_end: now |> DateTime.add(30 * 86_400, :second)
    }

    Repo.insert!(Subscription.changeset(%Subscription{}, Map.merge(defaults, attrs)))
  end

  describe "handle_webhook_event/1" do
    test "ignores unknown event types" do
      event = %{"type" => "unknown.event", "data" => %{"object" => %{}}}
      assert {:ok, :ignored} = Billing.handle_webhook_event(event)
    end

    test "handles checkout.session.completed with valid user" do
      user = create_user()

      event = %{
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "client_reference_id" => user.id,
            "subscription" => "sub_new_#{System.unique_integer([:positive])}",
            "subscription_data" => nil,
            "metadata" => %{"plan" => "monthly", "user_id" => user.id}
          }
        }
      }

      assert {:ok, :processed} = Billing.handle_webhook_event(event)

      # User subscription tier should be updated
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.subscription_tier == "monthly"
    end

    test "handles checkout.session.completed gracefully when user_id is nil" do
      event = %{
        "type" => "checkout.session.completed",
        "data" => %{
          "object" => %{
            "client_reference_id" => nil,
            "subscription" => nil,
            "subscription_data" => nil,
            "metadata" => %{}
          }
        }
      }

      assert {:ok, :processed} = Billing.handle_webhook_event(event)
    end

    test "handles invoice.paid for existing subscription" do
      user = create_user()
      sub = create_subscription(user)
      period_end = DateTime.utc_now() |> DateTime.add(60 * 86_400, :second) |> DateTime.to_unix()

      event = %{
        "type" => "invoice.paid",
        "data" => %{
          "object" => %{
            "subscription" => sub.stripe_subscription_id,
            "period_end" => period_end
          }
        }
      }

      assert {:ok, :processed} = Billing.handle_webhook_event(event)

      updated_sub = Repo.get!(Subscription, sub.id)
      assert updated_sub.status == "active"
    end

    test "handles invoice.paid gracefully for non-existent subscription" do
      event = %{
        "type" => "invoice.paid",
        "data" => %{
          "object" => %{
            "subscription" => "sub_nonexistent",
            "period_end" => DateTime.utc_now() |> DateTime.to_unix()
          }
        }
      }

      assert {:ok, :processed} = Billing.handle_webhook_event(event)
    end

    test "handles invoice.payment_failed sets status to past_due" do
      user = create_user()
      sub = create_subscription(user)

      event = %{
        "type" => "invoice.payment_failed",
        "data" => %{
          "object" => %{
            "subscription" => sub.stripe_subscription_id
          }
        }
      }

      assert {:ok, :processed} = Billing.handle_webhook_event(event)

      updated_sub = Repo.get!(Subscription, sub.id)
      assert updated_sub.status == "past_due"
    end

    test "handles customer.subscription.deleted downgrades to free" do
      user = create_user()
      sub = create_subscription(user)

      event = %{
        "type" => "customer.subscription.deleted",
        "data" => %{
          "object" => %{
            "id" => sub.stripe_subscription_id
          }
        }
      }

      assert {:ok, :processed} = Billing.handle_webhook_event(event)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.subscription_tier == "free"

      updated_sub = Repo.get!(Subscription, sub.id)
      assert updated_sub.status == "canceled"
    end

    test "handles customer.subscription.updated syncs status and period" do
      user = create_user()
      sub = create_subscription(user)

      new_period_end =
        DateTime.utc_now() |> DateTime.add(90 * 86_400, :second) |> DateTime.to_unix()

      event = %{
        "type" => "customer.subscription.updated",
        "data" => %{
          "object" => %{
            "id" => sub.stripe_subscription_id,
            "status" => "active",
            "current_period_end" => new_period_end
          }
        }
      }

      assert {:ok, :processed} = Billing.handle_webhook_event(event)
    end

    test "handles customer.subscription.updated with trialing status" do
      user = create_user()
      sub = create_subscription(user)
      period_end = DateTime.utc_now() |> DateTime.add(7 * 86_400, :second) |> DateTime.to_unix()

      event = %{
        "type" => "customer.subscription.updated",
        "data" => %{
          "object" => %{
            "id" => sub.stripe_subscription_id,
            "status" => "trialing",
            "current_period_end" => period_end
          }
        }
      }

      assert {:ok, :processed} = Billing.handle_webhook_event(event)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.subscription_tier == "trial"
    end
  end

  describe "Subscription.changeset/2" do
    test "valid with all required fields" do
      user = create_user()
      now = DateTime.utc_now()

      attrs = %{
        user_id: user.id,
        stripe_subscription_id: "sub_test123",
        stripe_price_id: "price_monthly",
        plan: "monthly",
        status: "active",
        current_period_start: now,
        current_period_end: now |> DateTime.add(30 * 86_400, :second)
      }

      changeset = Subscription.changeset(%Subscription{}, attrs)
      assert changeset.valid?
    end

    test "invalid without stripe_subscription_id" do
      user = create_user()
      now = DateTime.utc_now()

      attrs = %{
        user_id: user.id,
        stripe_price_id: "price_monthly",
        plan: "monthly",
        status: "active",
        current_period_start: now,
        current_period_end: now |> DateTime.add(30 * 86_400, :second)
      }

      changeset = Subscription.changeset(%Subscription{}, attrs)
      refute changeset.valid?
    end
  end
end
