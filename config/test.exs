import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :sports_fanatic, SportsFanatic.Repo,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: "sports_fanatic_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Oban test mode: :manual starts Oban but does not auto-drain.
# Use Oban.drain_queue/1 in tests that need to process jobs.
config :sports_fanatic, Oban, testing: :manual

# Point Valkey to a non-existent host so tests that don't exercise cache
# don't fail on connection; the Cache module gracefully handles errors.
config :sports_fanatic, :valkey_url, "redis://localhost:6399"

# Disable Python bridge health check in tests
config :sports_fanatic, :python_bridge_url, "http://localhost:18000"

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :sports_fanatic, SportsFanaticWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "WBpBF6kmlR15Q2FFKkI+PpyfHQwKfz2LTWg3QTO2vCIsems3LSDVKszLTzDKpk+2",
  server: false

# In test we don't send emails.
config :sports_fanatic, SportsFanatic.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
