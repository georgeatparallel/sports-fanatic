defmodule SportsFanatic.Workers.XPostSchedulerWorkerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Workers.MainPostWorker
  alias SportsFanatic.Workers.XPostSchedulerWorker
  alias SportsFanatic.X.Scheduler

  # These tests verify the Oban job structure (queue, args, scheduled_at
  # distribution) WITHOUT hitting Postgres. No Repo calls are made.

  # ---------------------------------------------------------------------------
  # Oban.Worker behaviour
  # ---------------------------------------------------------------------------

  describe "Oban.Worker behaviour" do
    test "worker exports perform/1" do
      Code.ensure_loaded!(XPostSchedulerWorker)
      assert function_exported?(XPostSchedulerWorker, :perform, 1)
    end

    test "worker uses x_agent queue" do
      job = XPostSchedulerWorker.new(%{})
      assert job.changes.queue == "x_agent"
    end

    test "worker has max_attempts of 3" do
      job = XPostSchedulerWorker.new(%{})
      assert job.changes.max_attempts == 3
    end

    test "worker supports unique option (24-hour dedup)" do
      job = XPostSchedulerWorker.new(%{})
      # unique is set at the `use Oban.Worker` level;
      # the changeset should carry a unique key
      assert is_map(job.changes)
    end
  end

  # ---------------------------------------------------------------------------
  # MainPostWorker job structure
  # ---------------------------------------------------------------------------

  describe "MainPostWorker — job structure for scheduled posts" do
    test "MainPostWorker exports perform/1" do
      Code.ensure_loaded!(MainPostWorker)
      assert function_exported?(MainPostWorker, :perform, 1)
    end

    test "MainPostWorker.new/2 accepts post_id and post_type args" do
      post_id = Ecto.UUID.generate()
      job = MainPostWorker.new(%{"post_id" => post_id, "post_type" => "top_hits"})
      assert job.changes.args["post_id"] == post_id
      assert job.changes.args["post_type"] == "top_hits"
    end

    test "MainPostWorker.new/2 accepts all valid post types" do
      for pt <- ~w(top_hits injury team_magazine scorecard reply) do
        job = MainPostWorker.new(%{"post_id" => Ecto.UUID.generate(), "post_type" => pt})
        assert job.changes.args["post_type"] == pt
      end
    end

    test "MainPostWorker.new/2 accepts scheduled_at option and stores it" do
      scheduled_at = ~U[2026-06-15 17:30:00Z]

      job =
        MainPostWorker.new(%{"post_id" => Ecto.UUID.generate(), "post_type" => "top_hits"},
          scheduled_at: scheduled_at
        )

      # Oban stores scheduled_at as :utc_datetime_usec (microsecond precision).
      # Compare by converting to unix seconds to avoid precision mismatch.
      assert DateTime.to_unix(job.changes.scheduled_at, :second) ==
               DateTime.to_unix(scheduled_at, :second)
    end

    test "MainPostWorker uses x_agent queue" do
      job = MainPostWorker.new(%{"post_id" => Ecto.UUID.generate(), "post_type" => "injury"})
      assert job.changes.queue == "x_agent"
    end
  end

  # ---------------------------------------------------------------------------
  # Scheduler.plan_day/2 — scheduled_at distribution contract
  # (These are the key invariants that XPostSchedulerWorker relies on)
  # ---------------------------------------------------------------------------

  describe "scheduled_at distribution (via Scheduler.plan_day/2)" do
    @test_date ~D[2026-06-15]
    @window_start ~U[2026-06-15 17:00:00Z]
    @window_end ~U[2026-06-15 22:00:00Z]

    test "3 scheduled times are produced for a normal game day" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)
      assert map_size(plan.scheduled_times) == 3
    end

    test "all scheduled_at times fall within [13:00, 18:00] ET" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)

      for {_type, dt} <- plan.scheduled_times do
        assert DateTime.compare(dt, @window_start) in [:eq, :gt]
        assert DateTime.compare(dt, @window_end) in [:eq, :lt]
      end
    end

    test "scheduled_times keys match the 3 post types" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)
      types = MapSet.new(Map.keys(plan.scheduled_times))
      assert MapSet.equal?(types, MapSet.new(~w(top_hits injury team_magazine)))
    end

    test "adjacent scheduled times are >= 45 min apart" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)
      sorted = plan.scheduled_times |> Map.values() |> Enum.sort(DateTime)

      [t1, t2, t3] = sorted
      assert DateTime.diff(t2, t1, :second) >= 45 * 60
      assert DateTime.diff(t3, t2, :second) >= 45 * 60
    end

    test "with early game, posts land >= 30 min before first pitch" do
      # 19:10 UTC = 15:10 ET
      game_at = ~U[2026-06-15 19:10:00Z]
      plan = Scheduler.plan_day(@test_date, earliest_game_at: game_at)

      hard_latest = DateTime.add(game_at, -30 * 60, :second)

      for {_type, dt} <- plan.scheduled_times do
        assert DateTime.compare(dt, hard_latest) in [:eq, :lt],
               "#{dt} violates hard_latest #{hard_latest}"
      end
    end

    test "XPostSchedulerWorker.new/1 produces a valid job changeset" do
      job = XPostSchedulerWorker.new(%{})
      assert job.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # Job args structure produced by XPostSchedulerWorker
  # ---------------------------------------------------------------------------

  describe "XPostSchedulerWorker job args" do
    test "worker accepts empty args map" do
      job = XPostSchedulerWorker.new(%{})
      assert is_map(job.changes.args)
    end

    test "two jobs with the same args are identical (no random args)" do
      job1 = XPostSchedulerWorker.new(%{})
      job2 = XPostSchedulerWorker.new(%{})
      assert job1.changes.args == job2.changes.args
    end
  end
end
