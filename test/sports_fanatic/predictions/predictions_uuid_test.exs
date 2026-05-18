defmodule SportsFanatic.PredictionsUuidTest do
  @moduledoc """
  Regression: ensure the raw-SQL helpers in `SportsFanatic.Predictions`
  stringify the `pipeline_runs.id` (a `uuid` column) before it reaches
  LiveView assigns. Postgres returns `uuid` columns from `Repo.query!/2`
  as a 16-byte binary, which is NOT valid UTF-8 and crashes Jason when
  LiveView ships the diff over the WebSocket.

  Bug observed on `on-loop/predictions-pipeline-stream-seed` when
  switching to the admin Predictions tab — `Jason.EncodeError`:
  "invalid byte 0xF7 in <<247, 46, 184, 144, ...>>".
  """

  use SportsFanatic.DataCase, async: false

  alias SportsFanatic.Predictions

  describe "current_running_run/0" do
    test "returns id as a canonical 36-char UUID string (not a 16-byte binary)" do
      {:ok, _} =
        Repo.query(
          """
          INSERT INTO system.pipeline_runs
            (id, pipeline_name, status, started_at, run_kind,
             metadata, checkpoint, inserted_at, updated_at)
          VALUES
            (gen_random_uuid(), 'hit_predict_daily', 'running', NOW(), 'daily',
             '{}'::jsonb, '{}'::jsonb, NOW(), NOW())
          """,
          []
        )

      result = Predictions.current_running_run()

      assert is_map(result)
      assert is_binary(result.id)
      assert byte_size(result.id) == 36

      assert String.match?(
               result.id,
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
             )

      assert String.valid?(result.id)
    end

    test "result is JSON-encodable (the regression check that matches the production crash)" do
      {:ok, _} =
        Repo.query(
          """
          INSERT INTO system.pipeline_runs
            (id, pipeline_name, status, started_at, run_kind,
             metadata, checkpoint, inserted_at, updated_at)
          VALUES
            (gen_random_uuid(), 'hit_predict_daily', 'running', NOW(), 'daily',
             '{}'::jsonb, '{}'::jsonb, NOW(), NOW())
          """,
          []
        )

      result = Predictions.current_running_run()

      # This is exactly the encode path Phoenix uses to serialize LiveView
      # diffs. It blows up with `Jason.EncodeError: invalid byte 0xF7` if
      # `result.id` is a raw 16-byte binary UUID.
      assert {:ok, _json} = Jason.encode(result)
    end

    test "returns nil when no row is in 'running' status" do
      assert Predictions.current_running_run() == nil
    end
  end

  describe "list_runs/1" do
    test "stringifies the id on every row and the list is JSON-encodable" do
      {:ok, _} =
        Repo.query(
          """
          INSERT INTO system.pipeline_runs
            (id, pipeline_name, status, started_at, completed_at, run_kind,
             metadata, checkpoint, inserted_at, updated_at)
          VALUES
            (gen_random_uuid(), 'hit_predict_daily', 'completed',
             NOW() - interval '1 day', NOW() - interval '23 hour', 'daily',
             '{}'::jsonb, '{}'::jsonb, NOW(), NOW()),
            (gen_random_uuid(), 'hit_predict_daily', 'failed',
             NOW() - interval '2 day', NOW() - interval '47 hour', 'daily',
             '{}'::jsonb, '{}'::jsonb, NOW(), NOW())
          """,
          []
        )

      rows = Predictions.list_runs(10)

      assert length(rows) >= 2

      for row <- rows do
        assert is_binary(row.id)
        assert byte_size(row.id) == 36
        assert String.valid?(row.id)
      end

      # The full list must round-trip through Jason — this is what the
      # LiveView template push to the browser does.
      assert {:ok, _json} = Jason.encode(rows)
    end
  end
end
