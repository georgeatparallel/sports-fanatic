defmodule SportsFanaticWeb.StripeWebhookController do
  use SportsFanaticWeb, :controller

  alias SportsFanatic.Billing

  require Logger

  def handle(conn, _params) do
    event = conn.assigns.stripe_event

    case Billing.handle_webhook_event(event) do
      {:ok, _} ->
        Logger.info("Stripe webhook processed: #{event["type"]}")
        json(conn, %{status: "ok"})

      {:error, reason} ->
        Logger.error("Stripe webhook error: #{inspect(reason)}")

        conn
        |> put_status(422)
        |> json(%{error: "Processing failed"})
    end
  end
end
