defmodule SportsFanatic.PythonBridge.HealthCheck do
  @moduledoc "Polls Python bridge health endpoint every 30 seconds."

  use GenServer

  alias SportsFanatic.PythonBridge
  alias SportsFanatic.PythonBridge.CircuitBreaker

  require Logger

  @check_interval 30_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def healthy? do
    GenServer.call(__MODULE__, :healthy?)
  end

  @impl true
  def init(_opts) do
    # Start circuit breaker
    CircuitBreaker.start_link()
    # Schedule first check after a short delay
    Process.send_after(self(), :check, 5_000)
    {:ok, %{healthy: false, last_check: nil}}
  end

  @impl true
  def handle_info(:check, state) do
    healthy =
      case PythonBridge.health_check() do
        {:ok, %{"status" => "ok"}} ->
          true

        _ ->
          Logger.warning("Python bridge health check failed")
          false
      end

    Process.send_after(self(), :check, @check_interval)
    {:noreply, %{state | healthy: healthy, last_check: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:healthy?, _from, state) do
    {:reply, state.healthy, state}
  end
end
