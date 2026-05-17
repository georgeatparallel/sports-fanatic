defmodule SportsFanaticWeb.Router do
  use SportsFanaticWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SportsFanaticWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug SportsFanaticWeb.Plugs.FetchCurrentUser
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug SportsFanaticWeb.Plugs.RequireAuthenticated
  end

  pipeline :require_subscription do
    plug SportsFanaticWeb.Plugs.RequireAuthenticated
    plug SportsFanaticWeb.Plugs.SubscriptionGate
  end

  pipeline :require_admin do
    plug SportsFanaticWeb.Plugs.RequireAuthenticated
    plug SportsFanaticWeb.Plugs.RequireAdmin
  end

  pipeline :require_joshua do
    plug SportsFanaticWeb.Plugs.RequireJoshua
  end

  pipeline :joshua_rate_limit do
    plug SportsFanaticWeb.Plugs.JoshuaRateLimiter
  end

  pipeline :stripe_webhook do
    plug :accepts, ["json"]
    plug SportsFanaticWeb.Plugs.CacheRawBody
    plug SportsFanaticWeb.Plugs.VerifyStripeWebhook
  end

  # --- Health Check (no pipeline, minimal) ---
  scope "/", SportsFanaticWeb do
    pipe_through :api

    get "/health", PageController, :health
  end

  # --- Public SEO Routes (Phoenix Controllers) ---
  scope "/", SportsFanaticWeb do
    pipe_through :browser

    live "/", ChatLive, :index
    live "/chat", ChatLive, :index

    # Feed management
    live "/feeds", FeedsLive, :index
    live "/feeds/:id", FeedsLive, :show

    # Player pages
    get "/mlb/players", PlayerController, :index
    get "/mlb/players/:team_slug/:player_slug", PlayerController, :show
    get "/mlb/players/:team_slug/:player_slug/sources/:category", PlayerController, :sources

    # Team pages
    get "/mlb/teams", TeamController, :index
    get "/mlb/teams/:team_slug", TeamController, :show

    # Lineup pages
    get "/mlb/lineups/:date", LineupController, :show

    # News pages
    live "/mlb/news", NewsLive, :today
    get "/mlb/news/today", NewsController, :redirect_today
    live "/mlb/news/:date", NewsLive, :index
    get "/mlb/news/:date/:slug", NewsController, :show

    # Scouting preview (truncated, public)
    get "/mlb/scouting/:team_slug/:player_slug", ScoutingController, :show

    # Game Day Magazine preview (public)
    get "/mlb/game-day/:date/:slug", GameDayController, :show

    # Sitemaps
    get "/sitemap.xml", SitemapController, :index
    get "/sitemaps/:type", SitemapController, :show
    get "/robots.txt", SitemapController, :robots
  end

  # --- Auth Routes ---
  scope "/", SportsFanaticWeb do
    pipe_through :browser

    get "/register", AuthController, :register_form
    post "/register", AuthController, :register
    get "/login", AuthController, :login_form
    post "/login", AuthController, :login
    delete "/logout", AuthController, :logout
    get "/auth/session/:token", AuthController, :set_session_from_token
  end

  # --- Subscription Routes ---
  scope "/subscribe", SportsFanaticWeb do
    pipe_through :browser

    get "/", SubscriptionController, :pricing
    get "/success", SubscriptionController, :success
    get "/cancel", SubscriptionController, :cancel
  end

  scope "/subscribe", SportsFanaticWeb do
    pipe_through [:browser, :require_auth]

    post "/checkout", SubscriptionController, :checkout
  end

  # --- Stripe Webhook ---
  scope "/webhooks", SportsFanaticWeb do
    pipe_through :stripe_webhook

    post "/stripe", StripeWebhookController, :handle
  end

  # --- Premium LiveView Routes (subscription-gated) ---
  scope "/premium", SportsFanaticWeb do
    pipe_through [:browser, :require_subscription]

    live "/dashboard", DashboardLive
    live "/scouting/:team_slug/:player_slug", ScoutingLive
    live "/game-day/:date/:slug", GameDayLive
    live "/game-day/:date", GameDayIndexLive
    live "/archive/scouting", ArchiveScoutingLive
    live "/archive/game-day", ArchiveGameDayLive
  end

  # --- Joshua Auth Routes (admin gate) ---
  scope "/joshua", SportsFanaticWeb do
    pipe_through :browser

    get "/", JoshuaController, :login_form
    delete "/logout", JoshuaController, :logout
  end

  scope "/joshua", SportsFanaticWeb do
    pipe_through [:browser, :joshua_rate_limit]

    post "/login", JoshuaController, :login
  end

  # --- Admin Routes (protected by Joshua auth) ---
  scope "/admin", SportsFanaticWeb do
    pipe_through [:browser, :require_joshua]

    live_session :admin do
      live "/", AdminLive
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:sports_fanatic, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SportsFanaticWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
