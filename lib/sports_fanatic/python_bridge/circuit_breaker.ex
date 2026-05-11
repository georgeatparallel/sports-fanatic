defmodule SportsFanatic.PythonBridge.CircuitBreaker do
  @moduledoc """
  Circuit breaker for Python bridge.

  States:
    :closed  - normal operation
    :open    - failing, reject all requests
    :half_open - testing recovery (allow one request through)

  After 3 consecutive failures: circuit opens for 5 minutes.
  After cooldown: one request allowed. If success, circuit closes.
  """

  use GenServer

  @failure_threshold 50
  @cooldown_ms 30 * 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

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

  # Server

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
    {:noreply, %{state: :closed, failures: 0, opened_at: nil}}
  end

  def handle_cast(:failure, %{failures: failures} = state) do
    new_failures = failures + 1

    if new_failures >= @failure_threshold do
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
end
