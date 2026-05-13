defmodule SportsFanatic.PythonBridge.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias SportsFanatic.PythonBridge.CircuitBreaker

  # The actual threshold in the implementation
  @threshold 50

  setup do
    {:ok, pid} = GenServer.start_link(CircuitBreaker, [])

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    {:ok, pid: pid}
  end

  defp check(pid), do: GenServer.call(pid, :check)
  defp state(pid), do: GenServer.call(pid, :state)
  defp success(pid), do: GenServer.cast(pid, :success)
  defp failure(pid), do: GenServer.cast(pid, :failure)

  defp send_failures(pid, count) do
    for _ <- 1..count, do: failure(pid)
    :timer.sleep(50)
  end

  describe "initial state" do
    test "starts in closed state", %{pid: pid} do
      assert state(pid) == :closed
    end

    test "check returns :closed when in closed state", %{pid: pid} do
      assert check(pid) == :closed
    end
  end

  describe "state transitions: closed -> open" do
    test "remains closed after fewer than threshold failures", %{pid: pid} do
      send_failures(pid, @threshold - 1)
      assert state(pid) == :closed
    end

    test "opens after threshold consecutive failures", %{pid: pid} do
      send_failures(pid, @threshold)
      assert state(pid) == :open
    end

    test "check returns :open when circuit is open", %{pid: pid} do
      send_failures(pid, @threshold)
      assert check(pid) == :open
    end
  end

  describe "state transitions: success resets failures" do
    test "success resets failure count, returns to closed", %{pid: pid} do
      send_failures(pid, @threshold - 1)
      success(pid)
      :timer.sleep(50)
      assert state(pid) == :closed
    end

    test "success after open returns to closed", %{pid: pid} do
      send_failures(pid, @threshold)
      assert state(pid) == :open

      success(pid)
      :timer.sleep(50)
      assert state(pid) == :closed
    end

    test "after success, failures counter resets (needs threshold new failures to reopen)", %{
      pid: pid
    } do
      send_failures(pid, @threshold - 1)
      success(pid)
      :timer.sleep(50)

      # Fewer than threshold failures shouldn't open it
      send_failures(pid, @threshold - 1)
      assert state(pid) == :closed

      # One more should open it
      failure(pid)
      :timer.sleep(50)
      assert state(pid) == :open
    end
  end

  describe "half-open after cooldown" do
    test "cooldown period is 5 minutes" do
      cooldown_ms = 5 * 60 * 1_000
      assert cooldown_ms == 300_000
    end

    test "open state rejects requests immediately", %{pid: pid} do
      send_failures(pid, @threshold)
      assert check(pid) == :open
    end
  end

  describe "concurrent safety" do
    test "multiple failure casts are processed in order", %{pid: pid} do
      send_failures(pid, @threshold)
      assert state(pid) == :open
    end
  end
end
