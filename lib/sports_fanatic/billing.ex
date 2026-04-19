defmodule SportsFanatic.Billing do
  @moduledoc """
  The Billing context: Stripe subscription management.
  """

  alias SportsFanatic.Repo
  alias SportsFanatic.Accounts
  alias SportsFanatic.Billing.Subscription

  @trial_days 7

  def create_checkout_session(user, plan) do
    price_id = price_id_for_plan(plan)

    params = %{
      customer: ensure_stripe_customer(user),
      mode: "subscription",
      line_items: [%{price: price_id, quantity: 1}],
      subscription_data: %{trial_period_days: @trial_days},
      success_url: success_url(),
      cancel_url: cancel_url(),
      client_reference_id: user.id,
      metadata: %{plan: plan, user_id: user.id}
    }

    Stripe.Checkout.Session.create(params)
  end

  def handle_webhook_event(%{"type" => type, "data" => %{"object" => object}}) do
    case type do
      "checkout.session.completed" ->
        handle_checkout_completed(object)

      "invoice.paid" ->
        handle_invoice_paid(object)

      "invoice.payment_failed" ->
        handle_payment_failed(object)

      "customer.subscription.updated" ->
        handle_subscription_updated(object)

      "customer.subscription.deleted" ->
        handle_subscription_deleted(object)

      _ ->
        {:ok, :ignored}
    end
  end

  defp handle_checkout_completed(session) do
    user_id = session["client_reference_id"]
    stripe_sub_id = session["subscription"]

    if user_id && stripe_sub_id do
      user = Accounts.get_user!(user_id)
      plan = get_in(session, ["metadata", "plan"]) || "monthly"

      # Create subscription record
      %Subscription{}
      |> Subscription.changeset(%{
        user_id: user.id,
        stripe_subscription_id: stripe_sub_id,
        stripe_price_id: price_id_for_plan(plan),
        plan: plan,
        status: "active",
        current_period_start: DateTime.utc_now(),
        current_period_end: DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)
      })
      |> Repo.insert(on_conflict: :replace_all, conflict_target: :stripe_subscription_id)

      # Update user tier with expiry so has_active_subscription? works immediately
      period_end = DateTime.utc_now() |> DateTime.add(@trial_days * 24 * 3600, :second)
      Accounts.update_user_subscription(user, %{
        subscription_tier: "trial",
        subscription_expires_at: period_end
      })
    end

    {:ok, :processed}
  end

  defp handle_invoice_paid(invoice) do
    stripe_sub_id = invoice["subscription"]

    if sub = get_subscription_by_stripe_id(stripe_sub_id) do
      period_end = unix_to_datetime(invoice["period_end"])

      sub
      |> Subscription.changeset(%{status: "active", current_period_end: period_end})
      |> Repo.update()

      user = Accounts.get_user!(sub.user_id)
      Accounts.update_user_subscription(user, %{
        subscription_tier: sub.plan,
        subscription_expires_at: period_end
      })
    end

    {:ok, :processed}
  end

  defp handle_payment_failed(invoice) do
    stripe_sub_id = invoice["subscription"]

    if sub = get_subscription_by_stripe_id(stripe_sub_id) do
      sub
      |> Subscription.changeset(%{status: "past_due"})
      |> Repo.update()
    end

    {:ok, :processed}
  end

  defp handle_subscription_updated(stripe_sub) do
    stripe_sub_id = stripe_sub["id"]

    if sub = get_subscription_by_stripe_id(stripe_sub_id) do
      status = stripe_sub["status"]
      period_end = unix_to_datetime(stripe_sub["current_period_end"])

      sub
      |> Subscription.changeset(%{status: status, current_period_end: period_end})
      |> Repo.update()

      user = Accounts.get_user!(sub.user_id)
      tier = if status == "trialing", do: "trial", else: sub.plan
      Accounts.update_user_subscription(user, %{
        subscription_tier: if(status in ["active", "trialing"], do: tier, else: "free"),
        subscription_expires_at: period_end
      })
    end

    {:ok, :processed}
  end

  defp handle_subscription_deleted(stripe_sub) do
    stripe_sub_id = stripe_sub["id"]

    if sub = get_subscription_by_stripe_id(stripe_sub_id) do
      sub
      |> Subscription.changeset(%{status: "canceled", canceled_at: DateTime.utc_now()})
      |> Repo.update()

      user = Accounts.get_user!(sub.user_id)
      Accounts.update_user_subscription(user, %{subscription_tier: "free", subscription_expires_at: nil})
    end

    {:ok, :processed}
  end

  defp get_subscription_by_stripe_id(stripe_sub_id) do
    Repo.get_by(Subscription, stripe_subscription_id: stripe_sub_id)
  end

  defp ensure_stripe_customer(user) do
    if user.stripe_customer_id do
      user.stripe_customer_id
    else
      {:ok, customer} = Stripe.Customer.create(%{email: user.email, metadata: %{user_id: user.id}})
      Accounts.update_user_subscription(user, %{stripe_customer_id: customer.id})
      customer.id
    end
  end

  defp price_id_for_plan("yearly"), do: Application.get_env(:sports_fanatic, :stripe_price_yearly)
  defp price_id_for_plan(_), do: Application.get_env(:sports_fanatic, :stripe_price_monthly)

  defp success_url do
    SportsFanaticWeb.Endpoint.url() <> "/subscribe/success"
  end

  defp cancel_url do
    SportsFanaticWeb.Endpoint.url() <> "/subscribe/cancel"
  end

  defp unix_to_datetime(nil), do: nil
  defp unix_to_datetime(unix) when is_integer(unix) do
    DateTime.from_unix!(unix)
  end
  defp unix_to_datetime(_), do: nil
end
