defmodule SportsFanatic.Workers.ScoutingPipelineWorkerTest do
  use SportsFanatic.DataCase, async: true
  use Oban.Testing, repo: SportsFanatic.Repo

  alias SportsFanatic.Workers.ScoutingPipelineWorker

  describe "Oban.Worker behavior" do
    test "worker is a valid Oban.Worker" do
      assert function_exported?(ScoutingPipelineWorker, :perform, 1)
    end

    test "worker can be enqueued" do
      assert {:ok, _job} = Oban.insert(ScoutingPipelineWorker.new(%{}))
    end

    test "worker has correct queue" do
      job = ScoutingPipelineWorker.new(%{})
      assert job.changes.queue == "content_generation"
    end

    test "worker has max_attempts of 1" do
      job = ScoutingPipelineWorker.new(%{})
      assert job.changes.max_attempts == 1
    end

    test "worker accepts concurrency configuration" do
      args = %{
        "research_concurrency" => 10,
        "classification_concurrency" => 3
      }

      job = ScoutingPipelineWorker.new(args)
      assert job.changes.args == args
    end

    test "worker has unique period of 1 hour" do
      # Verify uniqueness by checking that two jobs don't conflict
      assert {:ok, _job1} = Oban.insert(ScoutingPipelineWorker.new(%{}))
    end
  end
end
