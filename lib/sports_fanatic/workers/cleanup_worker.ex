defmodule SportsFanatic.Workers.CleanupWorker do
  @moduledoc "Purges expired sessions and old cache entries. Runs at 3 AM ET daily."

  use Oban.Worker,
    queue: :system,
    max_attempts: 2,
    unique: [period: 3600]

  alias SportsFanatic.Accounts
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {count, _} = Accounts.delete_expired_sessions()
    Logger.info("Cleaned up #{count} expired sessions")
    :ok
  end
end
