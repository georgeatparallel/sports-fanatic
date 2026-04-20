defmodule SportsFanaticWeb.Plugs.FetchCurrentUser do
  @moduledoc "Fetches the current user from session token and assigns to conn."

  import Plug.Conn
  alias SportsFanatic.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    token = get_session(conn, :session_token)

    cond do
      user = token && Accounts.get_user_by_session_token(token) ->
        assign(conn, :current_user, user)

      true ->
        assign(conn, :current_user, nil)
    end
  end
end

defmodule SportsFanaticWeb.Plugs.RequireAuthenticated do
  @moduledoc "Redirects to login if user is not authenticated."

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/login?return_to=#{conn.request_path}")
      |> halt()
    end
  end
end

defmodule SportsFanaticWeb.Plugs.SubscriptionGate do
  @moduledoc """
  Requires an active subscription to access premium content.
  Redirects free users to the pricing page.
  """

  import Plug.Conn
  import Phoenix.Controller
  alias SportsFanatic.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, "Please log in to access premium content.")
        |> redirect(to: "/login?return_to=#{conn.request_path}")
        |> halt()

      Accounts.has_active_subscription?(user) ->
        conn

      true ->
        conn
        |> put_flash(:info, "Subscribe to access premium content.")
        |> redirect(to: "/subscribe")
        |> halt()
    end
  end
end

defmodule SportsFanaticWeb.Plugs.VerifyStripeWebhook do
  @moduledoc "Verifies Stripe webhook signatures."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    signing_secret = Application.get_env(:stripity_stripe, :signing_secret)
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case Stripe.Webhook.construct_event(conn.assigns[:raw_body], signature, signing_secret) do
      {:ok, event} ->
        assign(conn, :stripe_event, event)

      {:error, _reason} ->
        conn
        |> send_resp(400, "Invalid signature")
        |> halt()
    end
  end
end

defmodule SportsFanaticWeb.Plugs.CacheRawBody do
  @moduledoc "Caches the raw request body for webhook signature verification."

  def init(opts), do: opts

  def call(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Plug.Conn.assign(conn, :raw_body, body)
  end
end
