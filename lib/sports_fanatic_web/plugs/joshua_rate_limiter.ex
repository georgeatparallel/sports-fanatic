defmodule SportsFanaticWeb.Plugs.JoshuaRateLimiter do
  @moduledoc """
  ETS-based rate limiter for Joshua login attempts.

  Limits to 5 attempts per IP address per 5-minute window.
  Returns 429 Too Many Requests when exceeded.
  """

  import Plug.Conn

  require Logger

  @table :joshua_rate_limiter
  @max_attempts 5
  @window_seconds 300

  def init(opts), do: opts

  def call(conn, _opts) do
    ensure_table_exists()

    ip = client_ip(conn)
    now = System.system_time(:second)

    case check_rate(ip, now) do
      :ok ->
        conn

      :rate_limited ->
        Logger.warning("Joshua rate limiter: IP #{ip} exceeded login rate limit")

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(429, "Too Many Requests. Please try again later.")
        |> halt()
    end
  end

  @doc """
  Records a login attempt for the given IP address.
  Called from JoshuaController on failed login.
  """
  @spec record_attempt(Plug.Conn.t()) :: :ok
  def record_attempt(conn) do
    ensure_table_exists()
    ip = client_ip(conn)
    now = System.system_time(:second)

    case :ets.lookup(@table, ip) do
      [{^ip, attempts, window_start}] ->
        if now - window_start > @window_seconds do
          :ets.insert(@table, {ip, 1, now})
        else
          :ets.insert(@table, {ip, attempts + 1, window_start})
        end

      [] ->
        :ets.insert(@table, {ip, 1, now})
    end

    :ok
  end

  defp check_rate(ip, now) do
    case :ets.lookup(@table, ip) do
      [{^ip, _attempts, window_start}] when now - window_start > @window_seconds ->
        :ets.delete(@table, ip)
        :ok

      [{^ip, attempts, _window_start}] when attempts >= @max_attempts ->
        :rate_limited

      _ ->
        :ok
    end
  end

  defp ensure_table_exists do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set])

      _ ->
        :ok
    end
  end

  defp client_ip(conn) do
    # Check X-Forwarded-For header first (for reverse proxy setups)
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end
end
