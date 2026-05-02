defmodule SportsFanatic.Workers.ScoutingPipelineWorker do
  @moduledoc """
  Oban worker that triggers the agentic scouting pipeline.

  Can be enqueued manually from the Admin UI or scheduled via cron.
  Accepts optional configuration for concurrency settings.
  """

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 1,
    unique: [period: 3600]

  alias SportsFanatic.Scouting.Pipeline

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    config = %{
      "research_concurrency" => Map.get(args, "research_concurrency", 5),
      "classification_concurrency" => Map.get(args, "classification_concurrency", 5)
    }

    Logger.info("Starting scouting pipeline with config: #{inspect(config)}")

    case Pipeline.start_pipeline(config) do
      {:ok, run} ->
        Logger.info("Scouting pipeline started, run_id: #{run.id}")
        :ok

      {:error, :already_running} ->
        Logger.info("Scouting pipeline already running, skipping")
        :ok

      {:error, :no_players} ->
        Logger.info("No active players found, skipping pipeline")
        :ok

      {:error, reason} ->
        Logger.error("Failed to start scouting pipeline: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
