defmodule SportsFanatic.XApiStub do
  @moduledoc """
  Shared `Req.Test` stub plug for X v2 API endpoints used by the X agent.

  Usage:

      setup do
        Req.Test.stub(SportsFanatic.XApiStub, &SportsFanatic.XApiStub.dispatch/1)
        :ok
      end

  Then in tests, configure the X client to use `plug: {Req.Test,
  SportsFanatic.XApiStub}` (or set the option via test config). The stub
  recognises the few endpoint paths the agent calls and returns
  deterministic JSON payloads.

  This is intentionally tiny — extend per-test as needed by stubbing a
  different function on `Req.Test`.
  """

  def dispatch(conn) do
    case Map.get(conn, :request_path, conn.request_path) do
      "/2/tweets" ->
        Req.Test.json(conn, %{
          "data" => %{"id" => "stub-tweet-#{:rand.uniform(1_000_000)}"}
        })

      "/2/oauth2/token" ->
        Req.Test.json(conn, %{
          "access_token" => "stub-access-token",
          "refresh_token" => "stub-refresh-token",
          "expires_in" => 7200,
          "scope" => "tweet.read tweet.write users.read offline.access"
        })

      "/2/users/by/username/" <> _handle ->
        Req.Test.json(conn, %{"data" => %{"id" => "1234567890"}})

      path ->
        cond do
          String.contains?(path, "/replies") ->
            Req.Test.json(conn, %{"data" => []})

          String.starts_with?(path, "/2/tweets/") ->
            Req.Test.json(conn, %{"data" => %{"public_metrics" => %{"like_count" => 0}}})

          String.starts_with?(path, "/2/users/") ->
            Req.Test.json(conn, %{"data" => []})

          true ->
            Req.Test.json(conn, %{"data" => %{}})
        end
    end
  end
end
