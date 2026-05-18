defmodule SportsFanatic.Workers.CleanupWorker do
  @moduledoc """
  Purges expired sessions, old cache entries, and old streaming progress
  events. Runs at 3 AM ET daily.

  Steps:
  - `delete_expired_sessions` — accounts cleanup
  - `prune_pipeline_run_events` — drops `system.pipeline_run_events` rows
    older than 7 days (see `SportsFanatic.Predictions.Progress` retention)
  """

  use Oban.Worker,
    queue: :system,
    max_attempts: 2,
    unique: [period: 3600]

  alias SportsFanatic.Accounts
  alias SportsFanatic.Repo
  require Logger

  @retention_days 7

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {count, _} = Accounts.delete_expired_sessions()
    Logger.info("Cleaned up #{count} expired sessions")

    pruned = prune_pipeline_run_events()
    Logger.info("Pruned #{pruned} pipeline_run_events older than #{@retention_days} days")

    :ok
  end

  defp prune_pipeline_run_events do
    sql = """
    DELETE FROM system.pipeline_run_events
     WHERE inserted_at < NOW() - INTERVAL '#{@retention_days} days'
    """

    case Repo.query(sql, []) do
      {:ok, %{num_rows: n}} -> n
      _ -> 0
    end
  rescue
    e ->
      # Table may not exist yet on a pre-migration deploy — log and continue.
      Logger.warning("prune_pipeline_run_events skipped: #{inspect(e)}")
      0
  end
end
