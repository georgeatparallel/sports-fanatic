ExUnit.start()

# Configure the Ecto sandbox only if the Repo is available.
# This allows unit tests to run without a live PostgreSQL connection.
if pid = Process.whereis(SportsFanatic.Repo) do
  Ecto.Adapters.SQL.Sandbox.mode(SportsFanatic.Repo, :manual)
  _ = pid
end
