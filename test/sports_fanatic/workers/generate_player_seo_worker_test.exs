defmodule SportsFanatic.Workers.GeneratePlayerSeoWorkerTest do
  @moduledoc """
  Unit tests for `GeneratePlayerSeoWorker` module attributes and structure.
  No database required — verifies Oban worker configuration via changeset introspection.
  """
  use ExUnit.Case, async: true

  alias SportsFanatic.Workers.GeneratePlayerSeoWorker

  describe "Oban.Worker configuration" do
    test "worker module exists and exports perform/1" do
      assert function_exported?(GeneratePlayerSeoWorker, :perform, 1)
    end

    test "worker is configured with queue :content_generation" do
      job = GeneratePlayerSeoWorker.new(%{})
      assert job.changes.queue == "content_generation"
    end

    test "worker has max_attempts of 3" do
      job = GeneratePlayerSeoWorker.new(%{})
      assert job.changes.max_attempts == 3
    end

    test "worker has unique constraint with 3600 second period" do
      job = GeneratePlayerSeoWorker.new(%{})
      unique = job.changes.unique
      assert unique[:period] == 3600
    end

    test "new/1 returns a valid Oban job changeset" do
      job = GeneratePlayerSeoWorker.new(%{})
      assert job.valid?
    end

    test "new/1 with empty args produces valid job" do
      job = GeneratePlayerSeoWorker.new(%{})
      assert job.changes.args == %{}
    end
  end
end
