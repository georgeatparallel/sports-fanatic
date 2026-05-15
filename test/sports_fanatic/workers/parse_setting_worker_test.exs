defmodule SportsFanatic.Workers.ParseSettingWorkerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Workers.ParseSettingWorker

  describe "Oban.Worker behavior" do
    test "worker is a valid Oban.Worker" do
      Code.ensure_loaded!(ParseSettingWorker)
      assert function_exported?(ParseSettingWorker, :perform, 1)
    end

    test "worker uses content_generation queue" do
      job = ParseSettingWorker.new(%{"setting_id" => Ecto.UUID.generate()})
      assert job.changes.queue == "content_generation"
    end

    test "worker has max_attempts of 3" do
      job = ParseSettingWorker.new(%{"setting_id" => Ecto.UUID.generate()})
      assert job.changes.max_attempts == 3
    end
  end

  describe "job args structure" do
    test "accepts setting_id as a UUID string" do
      setting_id = Ecto.UUID.generate()
      job = ParseSettingWorker.new(%{"setting_id" => setting_id})
      assert job.changes.args == %{"setting_id" => setting_id}
    end

    test "stores setting_id exactly as provided" do
      setting_id = "123e4567-e89b-12d3-a456-426614174000"
      job = ParseSettingWorker.new(%{"setting_id" => setting_id})
      assert job.changes.args["setting_id"] == setting_id
    end
  end
end
