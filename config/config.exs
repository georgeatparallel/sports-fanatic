# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sports_fanatic,
  ecto_repos: [SportsFanatic.Repo]

# Configures the endpoint
config :sports_fanatic, SportsFanaticWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: SportsFanaticWeb.ErrorHTML, json: SportsFanaticWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SportsFanatic.PubSub,
  live_view: [signing_salt: "awSo+wzg"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sports_fanatic, SportsFanatic.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.3.2",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban configuration
config :sports_fanatic, Oban,
  repo: SportsFanatic.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 6 * * *", SportsFanatic.Workers.FetchScheduleWorker},
       {"*/30 8-20 * * *", SportsFanatic.Workers.FetchLineupsWorker},
       {"0 */2 * * *", SportsFanatic.Workers.FetchNewsWorker},
       {"0 7 * * *", SportsFanatic.Workers.GenerateScoutingWorker},
       {"0 9 * * *", SportsFanatic.Workers.GenerateGameDayWorker},
       {"0 */6 * * *", SportsFanatic.Workers.GenerateSitemapWorker},
       {"0 3 * * *", SportsFanatic.Workers.CleanupWorker},
       {"0 4 * * *", SportsFanatic.Workers.GeneratePlayerSeoWorker},
       {"30 9 * * *", SportsFanatic.Workers.GeneratePredictionsWorker},
       {"*/15 * * * *", SportsFanatic.Workers.WarmCacheWorker}
     ]}
  ],
  queues: [data_fetch: 5, content_generation: 3, cache: 2, system: 1]

# Stripe configuration
config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY") || "sk_test_placeholder",
  signing_secret: System.get_env("STRIPE_WEBHOOK_SECRET") || "whsec_placeholder"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
