defmodule SportsFanatic.Workers.GeneratePredictionsWorker do
  @moduledoc "Calls Python bridge for hit/HR predictions after lineups confirmed."

  use Oban.Worker,
    queue: :content_generation,
    max_attempts: 3,
    unique: [period: 300]

  alias SportsFanatic.PythonBridge
  alias SportsFanatic.Workers.WarmCacheWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"date" => _date}}) do
    # Call Python bridge for hit predictions
    case PythonBridge.predict_hits(%{}) do
      {:ok, _results} ->
        Logger.info("Hit predictions generated")

      {:error, reason} ->
        Logger.warning("Hit predictions failed: #{inspect(reason)}")
    end

    # Call Python bridge for HR predictions
    case PythonBridge.predict_hrs(%{}) do
      {:ok, _results} ->
        Logger.info("HR predictions generated")

      {:error, reason} ->
        Logger.warning("HR predictions failed: #{inspect(reason)}")
    end

    # Trigger cache warming
    %{}
    |> WarmCacheWorker.new()
    |> Oban.insert()

    :ok
  end
end
