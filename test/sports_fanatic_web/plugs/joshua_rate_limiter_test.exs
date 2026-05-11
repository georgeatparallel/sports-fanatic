defmodule SportsFanaticWeb.Plugs.JoshuaRateLimiterTest do
  use SportsFanaticWeb.ConnCase, async: false

  alias SportsFanaticWeb.Plugs.JoshuaRateLimiter

  setup do
    # Clean up ETS table between tests
    if :ets.info(:joshua_rate_limiter) != :undefined do
      :ets.delete_all_objects(:joshua_rate_limiter)
    end

    :ok
  end

  defp set_ip(conn, ip_string) do
    {:ok, ip_tuple} = :inet.parse_address(String.to_charlist(ip_string))
    %{conn | remote_ip: ip_tuple}
  end

  describe "record_attempt/1" do
    test "records attempts for an IP", %{conn: conn} do
      conn = set_ip(conn, "1.2.3.4")

      assert :ok = JoshuaRateLimiter.record_attempt(conn)
      assert :ok = JoshuaRateLimiter.record_attempt(conn)

      [{_ip, count, _ts}] = :ets.lookup(:joshua_rate_limiter, "1.2.3.4")
      assert count == 2
    end
  end

  describe "call/2" do
    test "allows requests under the limit", %{conn: conn} do
      conn = set_ip(conn, "10.0.0.1")

      # Record 4 attempts (under limit of 5)
      for _ <- 1..4, do: JoshuaRateLimiter.record_attempt(conn)

      result = JoshuaRateLimiter.call(conn, [])
      refute result.halted
    end

    test "blocks requests at the limit", %{conn: conn} do
      conn = set_ip(conn, "10.0.0.2")

      # Record 5 attempts (at limit)
      for _ <- 1..5, do: JoshuaRateLimiter.record_attempt(conn)

      result = JoshuaRateLimiter.call(conn, [])
      assert result.halted
      assert result.status == 429
    end
  end
end
