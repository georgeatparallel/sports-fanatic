defmodule SportsFanaticWeb.SubscriptionController do
  use SportsFanaticWeb, :controller

  alias SportsFanatic.Billing

  def pricing(conn, _params) do
    conn
    |> assign(:page_title, "Subscribe to Sports Fan Agent Premium")
    |> assign(:meta_description, "Get full scouting reports, Game Day Magazines, and real-time predictions. Start your 7-day free trial.")
    |> render(:pricing)
  end

  def checkout(conn, %{"plan" => plan}) when plan in ["monthly", "yearly"] do
    user = conn.assigns.current_user

    case Billing.create_checkout_session(user, plan) do
      {:ok, session} ->
        redirect(conn, external: session.url)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not start checkout. Please try again.")
        |> redirect(to: "/subscribe")
    end
  end

  def checkout(conn, _params) do
    conn
    |> put_flash(:error, "Please select a plan.")
    |> redirect(to: "/subscribe")
  end

  def success(conn, _params) do
    conn
    |> assign(:page_title, "Welcome to Premium! | Sports Fan Agent")
    |> render(:success)
  end

  def cancel(conn, _params) do
    conn
    |> assign(:page_title, "Checkout Cancelled | Sports Fan Agent")
    |> render(:cancel)
  end
end
