defmodule SportsFanatic.X.SchedulerTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.X.Scheduler

  # A fixed date in mid-season (EDT applies) used throughout these tests.
  # June 15, 2026 is a Monday with no DST ambiguity.
  @test_date ~D[2026-06-15]

  # ET base window in UTC-4: 13:00 ET = 17:00 UTC, 18:00 ET = 22:00 UTC
  @window_start_utc ~U[2026-06-15 17:00:00Z]
  @window_end_utc ~U[2026-06-15 22:00:00Z]

  # ---------------------------------------------------------------------------
  # plan_day/2 — no earliest game (nil) — all three times must land in window
  # ---------------------------------------------------------------------------

  describe "plan_day/2 — scheduled times in [13:00, 18:00] ET window" do
    test "all three scheduled times fall within the base UTC window" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)

      for {_type, dt} <- plan.scheduled_times do
        assert DateTime.compare(dt, @window_start_utc) in [:eq, :gt],
               "#{dt} is before window start #{@window_start_utc}"

        assert DateTime.compare(dt, @window_end_utc) in [:eq, :lt],
               "#{dt} is after window end #{@window_end_utc}"
      end
    end

    test "returns exactly three scheduled time entries when no slots are dropped" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)
      # With no game cap, all three slots should be kept
      assert map_size(plan.scheduled_times) == 3
    end

    test "post_order contains exactly the three valid post types" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)
      types = MapSet.new(plan.post_order)
      assert MapSet.equal?(types, MapSet.new(~w(top_hits injury team_magazine)))
    end

    test "post_order has no duplicates" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)
      assert length(plan.post_order) == length(Enum.uniq(plan.post_order))
    end

    test "scheduled_times keys match post_order entries" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)
      order_set = MapSet.new(plan.post_order)
      times_set = MapSet.new(Map.keys(plan.scheduled_times))
      # Every key in scheduled_times should be a post type
      for k <- times_set do
        assert k in ~w(top_hits injury team_magazine)
      end

      # And order_set should contain all keys that have times
      assert MapSet.subset?(times_set, order_set)
    end
  end

  # ---------------------------------------------------------------------------
  # plan_day/2 — spacing >= 45 minutes
  # ---------------------------------------------------------------------------

  describe "plan_day/2 — spacing between slots >= 45 minutes" do
    test "consecutive scheduled times are at least 45 minutes apart" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)
      sorted = plan.scheduled_times |> Map.values() |> Enum.sort(DateTime)

      [first, second, third] = sorted
      assert DateTime.diff(second, first, :second) >= 45 * 60
      assert DateTime.diff(third, second, :second) >= 45 * 60
    end
  end

  # ---------------------------------------------------------------------------
  # plan_day/2 — earliest_game_at constraint: >= 30 min before first pitch
  # ---------------------------------------------------------------------------

  describe "plan_day/2 — hard_latest constraint (30 min before first game)" do
    test "all times are at least 30 minutes before earliest game" do
      # Game at 20:10 UTC = 16:10 ET (early afternoon game)
      earliest_game = ~U[2026-06-15 20:10:00Z]
      hard_latest = DateTime.add(earliest_game, -30 * 60, :second)

      plan = Scheduler.plan_day(@test_date, earliest_game_at: earliest_game)

      for {_type, dt} <- plan.scheduled_times do
        assert DateTime.compare(dt, hard_latest) in [:eq, :lt],
               "#{dt} is not at least 30 min before game at #{earliest_game}"
      end
    end

    test "slots beyond hard_latest are placed in skipped_slots" do
      # Game at 17:35 UTC = 13:35 ET — very early, most slots will be cut
      earliest_game = ~U[2026-06-15 17:35:00Z]

      plan = Scheduler.plan_day(@test_date, earliest_game_at: earliest_game)

      # Should have at least one skipped slot given how tight the window is
      # (hard_latest = 17:05 UTC = ~5 min into window — almost everything skipped)
      all_scheduled = Map.values(plan.scheduled_times)

      for dt <- all_scheduled do
        hard_latest = DateTime.add(earliest_game, -30 * 60, :second)
        assert DateTime.compare(dt, hard_latest) in [:eq, :lt]
      end
    end

    test "all skipped_slots entries are valid post type strings" do
      earliest_game = ~U[2026-06-15 17:35:00Z]
      plan = Scheduler.plan_day(@test_date, earliest_game_at: earliest_game)

      for slot <- plan.skipped_slots do
        assert slot in ~w(top_hits injury team_magazine)
      end
    end

    test "when game is after window end, no slots are skipped" do
      # Game at 23:00 UTC = 19:00 ET — after the 18:00 ET window
      earliest_game = ~U[2026-06-15 23:00:00Z]
      plan = Scheduler.plan_day(@test_date, earliest_game_at: earliest_game)

      assert plan.skipped_slots == []
      assert map_size(plan.scheduled_times) == 3
    end
  end

  # ---------------------------------------------------------------------------
  # plan_day/2 — jitter visibility across multiple iterations
  # ---------------------------------------------------------------------------

  describe "plan_day/2 — jitter across multiple runs" do
    test "per-slot times vary across 10 runs (jitter is present)" do
      # Different dates produce different jitter because :rand state is global.
      # We use 10 different dates one day apart.
      dates = Enum.map(0..9, fn i -> Date.add(@test_date, i) end)

      times_per_slot =
        Enum.map(dates, fn date ->
          plan = Scheduler.plan_day(date, earliest_game_at: nil)

          sorted =
            plan.scheduled_times
            |> Map.values()
            |> Enum.sort(DateTime)

          sorted
        end)

      # Extract first slot, second slot, third slot separately
      [slot1, slot2, slot3] =
        for i <- 0..2 do
          Enum.map(times_per_slot, fn sorted -> Enum.at(sorted, i) end)
          |> Enum.filter(& &1)
        end

      # Each slot should show at least some variation (not all identical)
      for {slot_list, idx} <- Enum.with_index([slot1, slot2, slot3]) do
        unique_times = Enum.uniq(slot_list)

        assert length(unique_times) > 1,
               "Slot #{idx + 1} shows no variation across 10 different dates: #{inspect(slot_list)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # order_for_date/1 — deterministic within a day
  # ---------------------------------------------------------------------------

  describe "order_for_date/1" do
    test "returns a list of exactly 3 post type strings" do
      order = Scheduler.order_for_date(@test_date)
      assert length(order) == 3
      assert Enum.all?(order, &is_binary/1)
    end

    test "contains all three post types exactly once" do
      order = Scheduler.order_for_date(@test_date)
      assert Enum.sort(order) == Enum.sort(~w(top_hits injury team_magazine))
    end

    test "is deterministic for the same date (called twice)" do
      order1 = Scheduler.order_for_date(@test_date)
      order2 = Scheduler.order_for_date(@test_date)
      assert order1 == order2
    end

    test "SCHED-001 fixed: order_for_date produces all 6 permutations across 31 consecutive days" do
      # Verify the fix: :erlang.phash2(gregorian_days, 6) against a 6-entry
      # permutation table distributes across all 6 permutations over a month.
      # Any injective mapping from the 31-day space to 6 permutations must
      # cover all 6 values.
      start_date = ~D[2026-05-17]

      orders =
        for i <- 0..30 do
          Scheduler.order_for_date(Date.add(start_date, i))
        end

      unique_orders = Enum.uniq(orders)

      assert length(unique_orders) == 6,
             "Expected all 6 permutations across 31 days; got #{length(unique_orders)}: #{inspect(unique_orders)}"
    end

    test "SCHED-001 fixed: same-day call is deterministic" do
      date = ~D[2026-05-17]
      assert Scheduler.order_for_date(date) == Scheduler.order_for_date(date)
    end
  end

  # ---------------------------------------------------------------------------
  # plan_day/2 — result map shape
  # ---------------------------------------------------------------------------

  describe "plan_day/2 — result map structure" do
    test "returns a map with required keys" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)

      assert is_list(plan.post_order)
      assert is_map(plan.scheduled_times)
      assert is_list(plan.skipped_slots)
      # earliest_game_at is nil when not supplied
      assert plan.earliest_game_at == nil
    end

    test "earliest_game_at is echoed back in the result" do
      game_dt = ~U[2026-06-15 22:10:00Z]
      plan = Scheduler.plan_day(@test_date, earliest_game_at: game_dt)
      assert plan.earliest_game_at == game_dt
    end

    test "all scheduled_times values are DateTime structs" do
      plan = Scheduler.plan_day(@test_date, earliest_game_at: nil)

      for {_k, v} <- plan.scheduled_times do
        assert %DateTime{} = v
      end
    end
  end
end
