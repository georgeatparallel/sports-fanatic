defmodule SportsFanatic.MixProject do
  use Mix.Project

  def project do
    [
      app: :sports_fanatic,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def cli do
    [preferred_envs: ["test.unit": :test]]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {SportsFanatic.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.7.22"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.19.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.8.1"},
      # Background jobs
      {:oban, "~> 2.18"},
      # Valkey/Redis
      {:redix, "~> 1.5"},
      # HTTP client
      {:req, "~> 0.5"},
      # Stripe
      {:stripity_stripe, "~> 3.2"},
      # Password hashing
      {:bcrypt_elixir, "~> 3.0"},
      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # Dependency security audit
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      # AWS S3
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:sweet_xml, "~> 0.7"},
      # HTML sanitization for chat output
      {:html_sanitize_ex, "~> 1.4"},
      {:earmark, "~> 1.4"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    unit_test_files = ~w(
      test/sports_fanatic/mlb
      test/sports_fanatic/accounts/user_test.exs
      test/sports_fanatic/cache_test.exs
      test/sports_fanatic/python_bridge
      test/sports_fanatic/news/entity_matcher_test.exs
      test/sports_fanatic/content/news_item_test.exs
      test/sports_fanatic/content/news_item_domain_tags_test.exs
      test/sports_fanatic/storage_test.exs
      test/sports_fanatic/feature_flags_test.exs
      test/sports_fanatic/agents/news_agent_setting_test.exs
      test/sports_fanatic/agents/news_agent_result_test.exs
      test/sports_fanatic/agents/action_test.exs
      test/sports_fanatic/chat_bot/chat_session_test.exs
      test/sports_fanatic/chat_bot/chat_message_test.exs
      test/sports_fanatic/chat_bot/query_cluster_test.exs
      test/sports_fanatic/external_apis/exa_test.exs
      test/sports_fanatic/workers/parse_setting_worker_test.exs
      test/sports_fanatic/workers/run_news_agents_worker_test.exs
      test/sports_fanatic/workers/consolidate_queries_worker_test.exs
      test/sports_fanatic/workers/scheduled_exa_search_worker_test.exs
      test/sports_fanatic_web/controllers/lineup_html_test.exs
      test/sports_fanatic_web/controllers/news_html_test.exs
      test/sports_fanatic_web/components/seo_components_test.exs
      test/sports_fanatic/feeds/csv_parser_test.exs
      test/sports_fanatic/feeds/user_feed_test.exs
      test/sports_fanatic/chat_bot/skill_router_test.exs
      test/sports_fanatic/x/scheduler_test.exs
      test/sports_fanatic/x/spend_ledger_test.exs
      test/sports_fanatic/x/token_vault_test.exs
      test/sports_fanatic/x/post_changeset_test.exs
      test/sports_fanatic/x/sanitizer_test.exs
      test/sports_fanatic/x/exa_dedup_test.exs
      test/sports_fanatic/x/injury_classification_flattener_test.exs
      test/sports_fanatic/x/credentials_test.exs
      test/sports_fanatic/content/injury_report_test.exs
      test/sports_fanatic/content/team_magazine_test.exs
      test/sports_fanatic/workers/x_post_scheduler_worker_test.exs
      test/sports_fanatic/predictions/hit_prediction_test.exs
      test/sports_fanatic/predictions/park_factors_test.exs
      test/sports_fanatic/predictions/stadiums_test.exs
      test/sports_fanatic/predictions/features_test.exs
      test/sports_fanatic/external_apis/open_meteo_test.exs
      test/sports_fanatic/external_apis/mlb_stats_test.exs
      test/sports_fanatic/workers/daily_hit_predictions_worker_test.exs
    )

    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # Run only unit tests that do not require a database connection.
      # Uses a function alias to call Mix.Tasks.Test directly, bypassing the
      # "test" alias above which would trigger ecto.create.
      "test.unit": fn _args -> Mix.Tasks.Test.run(unit_test_files) end,
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end
end
