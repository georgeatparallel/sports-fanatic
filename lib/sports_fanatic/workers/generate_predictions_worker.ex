defmodule SportsFanatic.Workers.GeneratePredictionsWorker do
  @moduledoc """
  Legacy entry point preserved for the existing `/admin` "Generate Predictions"
  button and any external cron entries. Delegates to the new
  `DailyHitPredictionsWorker` orchestrator.
  """

  use Oban.Worker,
    queue: :predictions,
    max_attempts: 3,
    unique: [period: 300]

  alias SportsFanatic.Workers.DailyHitPredictionsWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.info("GeneratePredictionsWorker → delegating to DailyHitPredictionsWorker")
    date = args["date"] || SportsFanatic.DateHelper.today() |> Date.to_iso8601()

    %{"date" => date, "force" => true}
    |> DailyHitPredictionsWorker.new()
    |> Oban.insert()

    :ok
  end
end
