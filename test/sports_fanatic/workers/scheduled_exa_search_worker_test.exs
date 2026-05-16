defmodule SportsFanatic.Workers.ScheduledExaSearchWorkerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Workers.ScheduledExaSearchWorker

  describe "Oban.Worker behaviour" do
    test "worker is a valid Oban.Worker" do
      Code.ensure_loaded!(ScheduledExaSearchWorker)
      assert function_exported?(ScheduledExaSearchWorker, :perform, 1)
    end

    test "worker uses the :content_generation queue" do
      job = ScheduledExaSearchWorker.new(%{})
      assert job.changes.queue == "content_generation"
    end

    test "worker has max_attempts of 3" do
      job = ScheduledExaSearchWorker.new(%{})
      assert job.changes.max_attempts == 3
    end
  end

  describe "job args structure" do
    test "can be enqueued with empty args" do
      job = ScheduledExaSearchWorker.new(%{})
      assert job.changes.args == %{}
    end

    test "job changeset is valid" do
      job = ScheduledExaSearchWorker.new(%{})
      assert job.valid?
    end
  end
end
