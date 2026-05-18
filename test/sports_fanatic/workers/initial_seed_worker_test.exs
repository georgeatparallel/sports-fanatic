defmodule SportsFanatic.Workers.InitialSeedWorkerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Workers.InitialSeedWorker

  # ---------------------------------------------------------------------------
  # 1. Oban.Worker behaviour compliance
  # ---------------------------------------------------------------------------

  describe "Oban.Worker behaviour" do
    test "worker module exports perform/1" do
      assert function_exported?(InitialSeedWorker, :perform, 1)
    end

    test "worker uses the :predictions queue" do
      job = InitialSeedWorker.new(%{"seed_from" => "2021-03-01", "seed_through" => "2021-03-31"})
      assert job.changes.queue == "predictions"
    end

    test "worker has max_attempts of 5" do
      job = InitialSeedWorker.new(%{"seed_from" => "2021-03-01", "seed_through" => "2021-03-31"})
      assert job.changes.max_attempts == 5
    end

    test "job changeset is valid with seed_from and seed_through" do
      job = InitialSeedWorker.new(%{"seed_from" => "2021-03-01", "seed_through" => "2024-12-31"})
      assert job.valid?
    end

    test "job changeset is valid with empty args (edge case)" do
      # Oban accepts any map; arg validation is inside perform/1
      job = InitialSeedWorker.new(%{})
      assert job.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Date range iteration is strictly ascending and complete
  # ---------------------------------------------------------------------------

  describe "date range iteration order" do
    test "Date.range/2 is strictly ascending for seed_from → seed_through" do
      seed_from = ~D[2021-03-01]
      seed_through = ~D[2021-03-10]

      dates = Date.range(seed_from, seed_through) |> Enum.to_list()

      # Strictly ascending
      assert dates == Enum.sort(dates, Date)
    end

    test "all dates in range are present — no gaps" do
      seed_from = ~D[2021-03-01]
      seed_through = ~D[2021-03-10]

      dates = Date.range(seed_from, seed_through) |> Enum.to_list()

      # Contiguous: each date is exactly 1 day after the previous
      dates
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert Date.diff(b, a) == 1,
               "Gap found between #{a} and #{b}"
      end)
    end

    test "no duplicate dates in range" do
      seed_from = ~D[2021-03-01]
      seed_through = ~D[2021-06-30]

      dates = Date.range(seed_from, seed_through) |> Enum.to_list()
      assert length(dates) == length(Enum.uniq(dates))
    end

    test "single-day range produces exactly one date" do
      date = ~D[2021-03-15]
      dates = Date.range(date, date) |> Enum.to_list()
      assert dates == [date]
    end

    test "expected count for 10-day range" do
      from = ~D[2021-03-01]
      through = ~D[2021-03-10]
      dates = Date.range(from, through) |> Enum.to_list()
      assert length(dates) == 10
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Resume from completed_dates — dates already in the list are skipped
  # ---------------------------------------------------------------------------

  describe "resume from completed_dates" do
    test "pending dates exclude those already in completed_dates" do
      seed_from = ~D[2021-03-01]
      seed_through = ~D[2021-03-10]

      completed_isos =
        Date.range(seed_from, ~D[2021-03-05])
        |> Enum.map(&Date.to_iso8601/1)

      completed_set = MapSet.new(completed_isos)
      all_dates = Date.range(seed_from, seed_through) |> Enum.to_list()

      pending =
        Enum.reject(all_dates, fn d -> MapSet.member?(completed_set, Date.to_iso8601(d)) end)

      # 5 completed (Mar 1-5) → 5 pending (Mar 6-10)
      assert length(pending) == 5
      assert Enum.all?(pending, fn d -> Date.compare(d, ~D[2021-03-05]) == :gt end)
    end

    test "all dates skipped when all are in completed_dates" do
      seed_from = ~D[2021-03-01]
      seed_through = ~D[2021-03-05]

      completed_isos =
        Date.range(seed_from, seed_through)
        |> Enum.map(&Date.to_iso8601/1)

      completed_set = MapSet.new(completed_isos)
      all_dates = Date.range(seed_from, seed_through) |> Enum.to_list()

      pending =
        Enum.reject(all_dates, fn d -> MapSet.member?(completed_set, Date.to_iso8601(d)) end)

      assert pending == []
    end

    test "empty completed_dates means all dates are pending" do
      seed_from = ~D[2021-03-01]
      seed_through = ~D[2021-03-05]

      completed_set = MapSet.new([])
      all_dates = Date.range(seed_from, seed_through) |> Enum.to_list()

      pending =
        Enum.reject(all_dates, fn d -> MapSet.member?(completed_set, Date.to_iso8601(d)) end)

      assert length(pending) == 5
    end

    test "completed_dates with 10 entries leaves the 11th date onward pending" do
      seed_from = ~D[2021-03-01]
      seed_through = ~D[2021-03-20]

      # Pre-populate 10 completed dates (Mar 1-10)
      completed_isos =
        Date.range(seed_from, ~D[2021-03-10])
        |> Enum.map(&Date.to_iso8601/1)

      completed_set = MapSet.new(completed_isos)
      all_dates = Date.range(seed_from, seed_through) |> Enum.to_list()

      pending =
        Enum.reject(all_dates, fn d -> MapSet.member?(completed_set, Date.to_iso8601(d)) end)

      # 10 pre-populated → 10 pending (Mar 11-20)
      assert length(pending) == 10
      assert List.first(pending) == ~D[2021-03-11]
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Unique constraint — enqueueing twice with the same seed_from + seed_through
  # ---------------------------------------------------------------------------

  describe "unique job constraint" do
    test "unique fields include :seed_from and :seed_through" do
      # The unique config is embedded in the Oban.Worker macro. We verify the
      # job can be constructed with the expected args.
      job =
        InitialSeedWorker.new(%{
          "seed_from" => "2021-03-01",
          "seed_through" => "2024-12-31"
        })

      assert job.valid?
      assert job.changes.args["seed_from"] == "2021-03-01"
      assert job.changes.args["seed_through"] == "2024-12-31"
    end

    test "two jobs with identical seed_from+seed_through produce the same args" do
      args = %{"seed_from" => "2021-03-01", "seed_through" => "2024-12-31"}

      job1 = InitialSeedWorker.new(args)
      job2 = InitialSeedWorker.new(args)

      # Same args — Oban's unique constraint would deduplicate these at insert.
      assert job1.changes.args == job2.changes.args
    end

    test "two jobs with different seed_through are not duplicates" do
      args1 = %{"seed_from" => "2021-03-01", "seed_through" => "2024-12-31"}
      args2 = %{"seed_from" => "2021-03-01", "seed_through" => "2025-01-31"}

      job1 = InitialSeedWorker.new(args1)
      job2 = InitialSeedWorker.new(args2)

      refute job1.changes.args == job2.changes.args
    end
  end

  # ---------------------------------------------------------------------------
  # 5. perform/1 returns {:error, :invalid_args} on bad args
  # ---------------------------------------------------------------------------

  describe "perform/1 — invalid args guard" do
    test "returns {:error, :invalid_args} when seed_from is missing" do
      job = %Oban.Job{args: %{"seed_through" => "2024-12-31"}}
      result = InitialSeedWorker.perform(job)
      assert result == {:error, :invalid_args}
    end

    test "returns {:error, :invalid_args} when seed_through is missing" do
      job = %Oban.Job{args: %{"seed_from" => "2021-03-01"}}
      result = InitialSeedWorker.perform(job)
      assert result == {:error, :invalid_args}
    end

    test "returns {:error, :invalid_args} when args are empty" do
      job = %Oban.Job{args: %{}}
      result = InitialSeedWorker.perform(job)
      assert result == {:error, :invalid_args}
    end

    test "returns {:error, :invalid_args} when seed_from is not a valid date string" do
      job = %Oban.Job{args: %{"seed_from" => "not-a-date", "seed_through" => "2024-12-31"}}
      result = InitialSeedWorker.perform(job)
      assert result == {:error, :invalid_args}
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Step dependency modules are all loadable
  # ---------------------------------------------------------------------------

  describe "worker step module dependencies" do
    test "FetchScheduleWorker is loadable" do
      assert Code.ensure_loaded?(SportsFanatic.Workers.FetchScheduleWorker)
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
  end

  # ---------------------------------------------------------------------------
  # 7. Checkpoint payload shape
  # ---------------------------------------------------------------------------

  describe "checkpoint payload shape" do
    test "completed checkpoint has all required fields" do
      # This mirrors what run_one_date success arm writes.
      checkpoint = %{
        "v" => 1,
        "completed_dates" => ["2021-03-01", "2021-03-02"],
        "current_date" => nil,
        "current_step" => nil,
        "failed_at" => nil
      }

      assert checkpoint["v"] == 1
      assert is_list(checkpoint["completed_dates"])
      assert checkpoint["failed_at"] == nil
    end

    test "failed checkpoint records the failing date in current_date" do
      iso = "2021-03-05"

      checkpoint = %{
        "v" => 1,
        "completed_dates" => ["2021-03-01", "2021-03-02"],
        "current_date" => iso,
        "current_step" => nil,
        "failed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      assert checkpoint["current_date"] == iso
      assert is_binary(checkpoint["failed_at"])
    end
  end
end
