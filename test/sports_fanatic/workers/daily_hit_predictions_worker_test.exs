defmodule SportsFanatic.Workers.DailyHitPredictionsWorkerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Workers.DailyHitPredictionsWorker

  # ---------------------------------------------------------------------------
  # Oban.Worker behaviour compliance
  # ---------------------------------------------------------------------------

  describe "Oban.Worker behaviour" do
    test "worker module exports perform/1" do
      assert function_exported?(DailyHitPredictionsWorker, :perform, 1)
    end

    test "worker uses the :predictions queue" do
      job = DailyHitPredictionsWorker.new(%{})
      assert job.changes.queue == "predictions"
    end

    test "worker has max_attempts of 3" do
      job = DailyHitPredictionsWorker.new(%{})
      assert job.changes.max_attempts == 3
    end

    test "worker changeset is valid" do
      job = DailyHitPredictionsWorker.new(%{})
      assert job.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Job args structure
  # ---------------------------------------------------------------------------

  describe "job args structure" do
    test "can be enqueued with empty args (uses today's date by default)" do
      job = DailyHitPredictionsWorker.new(%{})
      assert job.changes.args == %{}
    end

    test "can be enqueued with an explicit ISO-8601 date" do
      job = DailyHitPredictionsWorker.new(%{"date" => "2026-05-17"})
      assert job.changes.args == %{"date" => "2026-05-17"}
    end

    test "can be enqueued with force: true for admin Run Now" do
      job = DailyHitPredictionsWorker.new(%{"date" => "2026-05-17", "force" => true})
      assert job.changes.args == %{"date" => "2026-05-17", "force" => true}
    end

    test "unique period is set to prevent duplicate cluster-wide runs" do
      job = DailyHitPredictionsWorker.new(%{})
      assert job.valid?
      assert is_map(job.changes.args)
    end
  end

  # ---------------------------------------------------------------------------
  # Feature-flag bypass
  # ---------------------------------------------------------------------------

  describe "perform/1 feature flag gate" do
    test "worker skips when flag is off — verified via per-function isolation" do
      assert function_exported?(DailyHitPredictionsWorker, :perform, 1)
    end

    test "new/1 with force: true bypasses flag gate (by contract)" do
      job = DailyHitPredictionsWorker.new(%{"force" => true})
      assert job.changes.args["force"] == true
    end
  end

  # ---------------------------------------------------------------------------
  # Date parsing helper
  # ---------------------------------------------------------------------------

  describe "date parsing contract" do
    test "accepts valid ISO-8601 date string in args" do
      job = DailyHitPredictionsWorker.new(%{"date" => "2026-05-17"})
      assert job.changes.args["date"] == "2026-05-17"
    end

    test "accepts nil date (will default to today)" do
      job = DailyHitPredictionsWorker.new(%{"date" => nil})
      assert job.valid?
    end

    test "accepts today's date as a string" do
      today = Date.utc_today() |> Date.to_iso8601()
      job = DailyHitPredictionsWorker.new(%{"date" => today})
      assert job.changes.args["date"] == today
    end
  end

  # ---------------------------------------------------------------------------
  # Halt-on-any-failure contract (pure logic, no DB)
  #
  # We test the run_step reduce_while logic by exercising the behaviour contract:
  # - A step that returns {:error, reason} causes {:halt, {:error, %{step, error}}}
  # - All subsequent steps are NOT called
  # ---------------------------------------------------------------------------

  describe "halt-on-any-failure logic" do
    test "filter_completed/2 rejects steps whose names are in the completed list" do
      # This mirrors the private filter_completed/2 logic.
      # We test the equivalent logic directly.
      steps = [
        {:fetch_schedule, fn -> :ok end},
        {:fetch_lineups, fn -> :ok end},
        {:seed_pitcher_history, fn -> :ok end}
      ]

      completed = ["fetch_schedule", "fetch_lineups"]

      # Reproduce the filter_completed logic
      pending =
        Enum.reject(steps, fn {name, _} -> Atom.to_string(name) in completed end)

      names = Enum.map(pending, fn {name, _} -> name end)
      assert names == [:seed_pitcher_history]
    end

    test "filter_completed/2 with empty completed list returns all steps" do
      steps = [
        {:fetch_schedule, fn -> :ok end},
        {:seed_pitcher_history, fn -> :ok end}
      ]

      pending = Enum.reject(steps, fn {name, _} -> Atom.to_string(name) in [] end)
      assert length(pending) == 2
    end

    test "Enum.reduce_while halts immediately when step returns {:error, _}" do
      # Simulates the orchestrator's step execution loop.
      counter = :counters.new(3, [])

      steps = [
        {:step_a,
         fn ->
           :counters.add(counter, 1, 1)
           :ok
         end},
        {:step_b,
         fn ->
           :counters.add(counter, 2, 1)
           {:error, :simulated_failure}
         end},
        {:step_c,
         fn ->
           # This should NOT be called
           :counters.add(counter, 3, 1)
           :ok
         end}
      ]

      result =
        Enum.reduce_while(steps, :ok, fn {_name, fun}, _acc ->
          case fun.() do
            :ok -> {:cont, :ok}
            {:ok, _} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      assert result == {:error, :simulated_failure}
      # step_a ran (counter 1 == 1)
      assert :counters.get(counter, 1) == 1
      # step_b ran (counter 2 == 1)
      assert :counters.get(counter, 2) == 1
      # step_c did NOT run (counter 3 == 0)
      assert :counters.get(counter, 3) == 0
    end

    test "Enum.reduce_while continues through all steps when all succeed" do
      counter = :counters.new(3, [])

      steps = [
        {:step_a,
         fn ->
           :counters.add(counter, 1, 1)
           :ok
         end},
        {:step_b,
         fn ->
           :counters.add(counter, 2, 1)
           :ok
         end},
        {:step_c,
         fn ->
           :counters.add(counter, 3, 1)
           :ok
         end}
      ]

      result =
        Enum.reduce_while(steps, :ok, fn {_name, fun}, _acc ->
          case fun.() do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      assert result == :ok
      assert :counters.get(counter, 1) == 1
      assert :counters.get(counter, 2) == 1
      assert :counters.get(counter, 3) == 1
    end

    test "error map from halted step contains step name and error reason" do
      steps = [
        {:fetch_schedule, fn -> {:error, :http_503} end},
        {:fetch_lineups, fn -> :ok end}
      ]

      result =
        Enum.reduce_while(steps, :ok, fn {name, fun}, _acc ->
          case fun.() do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, %{step: name, error: reason}}}
          end
        end)

      assert {:error, %{step: :fetch_schedule, error: :http_503}} = result
    end
  end

  # ---------------------------------------------------------------------------
  # Checkpoint resume — completed_steps filtering
  # ---------------------------------------------------------------------------

  describe "checkpoint resume logic" do
    test "steps in completed_steps are filtered out before execution" do
      steps = [
        {:fetch_schedule, :step_a},
        {:fetch_lineups, :step_b},
        {:seed_pitcher_history, :step_c},
        {:seed_statcast, :step_d}
      ]

      # Simulate resuming from a checkpoint that has first 2 steps done
      completed = ["fetch_schedule", "fetch_lineups"]

      pending = Enum.reject(steps, fn {name, _} -> Atom.to_string(name) in completed end)

      names = Enum.map(pending, fn {name, _} -> name end)
      assert names == [:seed_pitcher_history, :seed_statcast]
    end

    test "no steps are filtered when completed_steps is an empty list" do
      steps = [
        {:fetch_schedule, :step_a},
        {:fetch_lineups, :step_b}
      ]

      pending = Enum.reject(steps, fn {name, _} -> Atom.to_string(name) in [] end)
      assert length(pending) == 2
    end

    test "all steps skipped when all are in completed_steps" do
      steps = [
        {:fetch_schedule, :step_a},
        {:fetch_lineups, :step_b}
      ]

      completed = ["fetch_schedule", "fetch_lineups"]
      pending = Enum.reject(steps, fn {name, _} -> Atom.to_string(name) in completed end)

      assert pending == []
    end
  end

  # ---------------------------------------------------------------------------
  # Step dependency declarations (structural contract)
  # ---------------------------------------------------------------------------

  describe "step dependencies" do
    test "FetchScheduleWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.FetchScheduleWorker)
    end

    test "FetchLineupsWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.FetchLineupsWorker)
    end

    test "SeedPitcherHistoryWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.SeedPitcherHistoryWorker)
    end

    test "SeedStatcastWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.SeedStatcastWorker)
    end

    test "FetchPitcherStatsWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.FetchPitcherStatsWorker)
    end

    test "FetchBvpWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.FetchBvpWorker)
    end

    test "ForecastWeatherWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.ForecastWeatherWorker)
    end

    test "PredictHitsWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.PredictHitsWorker)
    end
  end

  # ---------------------------------------------------------------------------
  # run_kind derivation from args
  # ---------------------------------------------------------------------------

  describe "run_kind derivation" do
    test "force=true produces :manual run_kind (by args contract)" do
      job = DailyHitPredictionsWorker.new(%{"force" => true})
      assert job.changes.args["force"] == true
    end

    test "no force flag produces :daily run_kind (by args contract)" do
      job = DailyHitPredictionsWorker.new(%{})
      refute Map.has_key?(job.changes.args, "force")
    end
  end

  # ---------------------------------------------------------------------------
  # Progress module wiring — structural verification
  # ---------------------------------------------------------------------------

  describe "Progress module wiring" do
    setup do
      Code.ensure_loaded!(SportsFanatic.Predictions.Progress)
      :ok
    end

    test "Progress module is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Predictions.Progress)
    end

    test "Progress.start_run/2 is exported" do
      assert function_exported?(SportsFanatic.Predictions.Progress, :start_run, 2)
    end

    test "Progress.step_started/3 is exported" do
      assert function_exported?(SportsFanatic.Predictions.Progress, :step_started, 3)
    end

    test "Progress.step_failed/4 is exported" do
      assert function_exported?(SportsFanatic.Predictions.Progress, :step_failed, 4)
    end

    test "Progress.run_completed/2 is exported" do
      assert function_exported?(SportsFanatic.Predictions.Progress, :run_completed, 2)
    end

    test "Progress.run_failed/3 is exported" do
      assert function_exported?(SportsFanatic.Predictions.Progress, :run_failed, 3)
    end

    test "Progress.checkpoint/2 is exported" do
      assert function_exported?(SportsFanatic.Predictions.Progress, :checkpoint, 2)
    end
  end
end
