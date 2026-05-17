defmodule SportsFanatic.X.CircuitBreaker do
  @moduledoc """
  Circuit breaker for X (Twitter) API calls.

  Modeled on `SportsFanatic.PythonBridge.CircuitBreaker` but tuned for an
  external paid API: tighter thresholds (3 failures, 5 minute cooldown)
  because each failure can cost real money.

  States:
    :closed   — normal operation
    :open     — failing, reject all writes
    :half_open — testing recovery (one request allowed through)
  """

  use GenServer

  @failure_threshold 3
  @cooldown_ms 5 * 60 * 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec check() :: :closed | :open | :half_open
  def check do
    GenServer.call(__MODULE__, :check)
  end

  def record_success do
    GenServer.cast(__MODULE__, :success)
  end

  def record_failure do
    GenServer.cast(__MODULE__, :failure)
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  # ── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{state: :closed, failures: 0, opened_at: nil}}
  end

  @impl true
  def handle_call(:check, _from, %{state: :open, opened_at: opened_at} = state) do
    if System.monotonic_time(:millisecond) - opened_at >= @cooldown_ms do
      {:reply, :half_open, %{state | state: :half_open}}
    else
      {:reply, :open, state}
    end
  end

  def handle_call(:check, _from, state) do
    {:reply, state.state, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state.state, state}
  end

  @impl true
  def handle_cast(:success, _state) do
    broadcast_change(:closed)
    {:noreply, %{state: :closed, failures: 0, opened_at: nil}}
  end

  def handle_cast(:failure, %{failures: failures} = state) do
    new_failures = failures + 1

    if new_failures >= @failure_threshold do
      broadcast_change(:open)

      {:noreply,
       %{
         state
         | state: :open,
           failures: new_failures,
           opened_at: System.monotonic_time(:millisecond)
       }}
    else
      {:noreply, %{state | failures: new_failures}}
    end
  end

  defp broadcast_change(new_state) do
    # Best-effort PubSub broadcast; ignored if PubSub not running (tests).
    if Process.whereis(SportsFanatic.PubSub) do
      Phoenix.PubSub.broadcast(
        SportsFanatic.PubSub,
        "admin:x_agent",
        {:circuit_state_change, new_state}
      )
    end
  rescue
    _ -> :ok
  end
end
