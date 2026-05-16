defmodule SportsFanatic.Workers.ConsolidateQueriesWorkerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Workers.ConsolidateQueriesWorker

  describe "Oban.Worker behaviour" do
    test "worker is a valid Oban.Worker" do
      Code.ensure_loaded!(ConsolidateQueriesWorker)
      assert function_exported?(ConsolidateQueriesWorker, :perform, 1)
    end

    test "worker uses the :system queue" do
      job = ConsolidateQueriesWorker.new(%{})
      assert job.changes.queue == "system"
    end

    test "worker has max_attempts of 3" do
      job = ConsolidateQueriesWorker.new(%{})
      assert job.changes.max_attempts == 3
    end
  end

  describe "job args structure" do
    test "can be enqueued with empty args" do
      job = ConsolidateQueriesWorker.new(%{})
      assert job.changes.args == %{}
    end

    test "job changeset is valid" do
      job = ConsolidateQueriesWorker.new(%{})
      assert job.valid?
    end
  end
end
