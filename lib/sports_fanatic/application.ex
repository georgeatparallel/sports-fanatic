defmodule SportsFanatic.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    valkey_url = Application.get_env(:sports_fanatic, :valkey_url, "redis://localhost:6379")

    # ETS counter table for SportsFanatic.Predictions.Progress per-run seq.
    # `:public` because progress events may be written from `Task.async_stream`
    # workers across many processes.
    ensure_progress_counter_table()

    children = [
      SportsFanaticWeb.Telemetry,
      SportsFanatic.Repo,
      {Phoenix.PubSub, name: SportsFanatic.PubSub},
      {Finch, name: SportsFanatic.Finch},
      # Valkey (Redis-compatible) connection
      {Redix, {valkey_url, [name: :redix]}},
      # Feature flags (ETS cache — must start before endpoint)
      SportsFanatic.FeatureFlags,
      # Oban background job processor
      {Oban, Application.fetch_env!(:sports_fanatic, Oban)},
      # Scouting pipeline orchestrator
      {SportsFanatic.Scouting.Pipeline, []},
      # Python Bridge health check
      SportsFanatic.PythonBridge.HealthCheck,
      # X (Twitter) agent circuit breaker — separate from python_bridge breaker
      SportsFanatic.X.CircuitBreaker,
      # Agent infrastructure for chatbot
      {Registry, keys: :unique, name: SportsFanatic.AgentRegistry},
      {DynamicSupervisor,
       name: SportsFanatic.AgentDynamicSupervisor, strategy: :one_for_one, max_children: 100},
      # Phoenix Endpoint
      SportsFanaticWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SportsFanatic.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SportsFanaticWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp ensure_progress_counter_table do
    if :ets.whereis(:predictions_progress_seq) == :undefined do
      :ets.new(:predictions_progress_seq, [
        :set,
        :public,
        :named_table,
        write_concurrency: true
      ])
    end

    :ok
  rescue
    ArgumentError -> :ok
  end
end
