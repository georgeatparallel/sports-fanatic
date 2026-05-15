defmodule SportsFanatic.Workers.RunNewsAgentsWorkerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Workers.RunNewsAgentsWorker

  describe "Oban.Worker behavior" do
    test "worker is a valid Oban.Worker" do
      Code.ensure_loaded!(RunNewsAgentsWorker)
      assert function_exported?(RunNewsAgentsWorker, :perform, 1)
    end

    test "worker uses content_generation queue" do
      job = RunNewsAgentsWorker.new(%{})
      assert job.changes.queue == "content_generation"
    end

    test "worker has max_attempts of 3" do
      job = RunNewsAgentsWorker.new(%{})
      assert job.changes.max_attempts == 3
    end
  end

  describe "job args structure" do
    test "can be enqueued with empty args" do
      job = RunNewsAgentsWorker.new(%{})
      assert job.changes.args == %{}
    end

    test "job changeset is valid" do
      job = RunNewsAgentsWorker.new(%{})
      assert job.valid?
    end
  end
end
