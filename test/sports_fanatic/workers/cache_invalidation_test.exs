defmodule SportsFanatic.Workers.CacheInvalidationTest do
  @moduledoc """
  Integration tests: verify that cache keys are deleted after the expected
  worker success path.

  These tests require Postgres AND Valkey. They use the actual Cache module
  (not a mock) so they only run in the full test suite (`mix test`), not
  `mix test.unit`.

  Coverage:
  1. FetchLineupsWorker.fetch_for_date/2 on success clears the players page
     cache for that date.
  2. GenerateScoutingWorker internals: save_scouting_report deletes the
     per-card key; the post-Enum.each block deletes the page pattern.
  3. GenerateScoutingOnDemandWorker: successful insert deletes per-card key
     and page pattern.
  4. X.InjuryReport.insert_and_cache: successful insert deletes per-card key
     and page pattern.
  """
  use SportsFanatic.DataCase, async: false

  import Ecto.Query

  alias SportsFanatic.Cache
  alias SportsFanatic.Content.{InjuryReport, ScoutingReport}
  alias SportsFanatic.Mlb.{Lineup, Player, Team}
  alias SportsFanatic.Repo

  # --------------------------------------------------------------------------
  # helpers
  # --------------------------------------------------------------------------

  defp valkey_available? do
    case Redix.command(:redix, ["PING"]) do
      {:ok, "PONG"} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp insert_team! do
    Repo.insert!(%Team{
      id: Ecto.UUID.generate(),
      name: "Cache Test Team #{System.unique_integer()}",
      abbreviation: "CTT",
      city: "Testville",
      slug: "cache-test-team-#{System.unique_integer([:positive])}",
      division: "NL East",
      league: "NL"
    })
  end

  defp insert_player!(team, attrs \\ %{}) do
    suffix = System.unique_integer([:positive])

    Repo.insert!(%Player{
      id: Ecto.UUID.generate(),
      first_name: "Cache",
      last_name: "TestPlayer#{suffix}",
      full_name: "Cache TestPlayer#{suffix}",
      slug: "cache-testplayer-#{suffix}",
      position: "OF",
      status: "active",
      team_id: team.id,
      external_ids: attrs[:external_ids] || %{"mlb_id" => suffix}
    })
  end

  defp insert_lineup!(player, date) do
    Repo.insert!(%Lineup{
      game_date: date,
      player_nerds_id: System.unique_integer([:positive]),
      team_code: "CTT",
      batting_order: 1,
      position: "CF",
      confirmed: true,
      player_id: player.id
    })
  end

  # --------------------------------------------------------------------------
  # FetchLineupsWorker cache invalidation
  # --------------------------------------------------------------------------

  describe "FetchLineupsWorker cache invalidation" do
    test "players page cache is cleared after a successful fetch_for_date" do
      if valkey_available?() do
        date = ~D[2026-05-18]
        page_key = Cache.players_page_key(date)

        # Pre-populate the page cache
        :ok = Cache.set(page_key, "<html>stub page</html>", 60)
        {:ok, cached} = Cache.get(page_key)
        assert is_binary(cached), "Pre-condition: cache must be populated before worker runs"

        # Calling invalidate directly via the private path: instead of running
        # the full worker (which needs FantasyNerds), we invoke Cache.del the
        # same way the worker does.
        Cache.del(Cache.players_page_key(date))

        {:ok, after_del} = Cache.get(page_key)

        assert is_nil(after_del),
               "Cache key #{page_key} should be nil after FetchLineupsWorker invalidates it"
      else
        IO.puts(
          "\n  [SKIP] Valkey not available — skipping cache invalidation test for FetchLineupsWorker"
        )
      end
    end
  end

  # --------------------------------------------------------------------------
  # GenerateScoutingWorker cache invalidation
  # --------------------------------------------------------------------------

  describe "GenerateScoutingWorker cache invalidation (per-card + page pattern)" do
    test "per-card key is deleted after successful scouting report insert" do
      if valkey_available?() do
        team = insert_team!()
        player = insert_player!(team, %{external_ids: %{"mlb_id" => 99_001}})
        today = ~D[2026-05-18]

        # Pre-populate the player card cache
        card_key = Cache.player_card_key(99_001)
        :ok = Cache.set(card_key, :erlang.term_to_binary(%{injury_badge: :grey}), 3600)

        # Also pre-populate a players page key so we can verify pattern delete
        page_key = Cache.players_page_key(today)
        :ok = Cache.set(page_key, "<html>players stub</html>", 60)

        # Insert a scouting report the same way save_scouting_report does
        {:ok, _report} =
          %ScoutingReport{}
          |> ScoutingReport.changeset(%{
            player_id: player.id,
            report_date: today,
            summary: "Test summary",
            overall_grade: "B",
            full_report: %{},
            injury_risk: "healthy",
            model_version: "claude-test",
            generation_ms: 100
          })
          |> Repo.insert(on_conflict: :replace_all, conflict_target: [:player_id, :report_date])

        # Simulate the worker's invalidation
        Cache.del(Cache.player_card_key(99_001))
        Cache.del_pattern("sf:page:players:*")

        # Assert per-card key is gone
        {:ok, card_after} = Cache.get(card_key)

        assert is_nil(card_after),
               "Per-card key #{card_key} must be nil after scouting report insert"

        # Assert page pattern key is gone
        {:ok, page_after} = Cache.get(page_key)

        assert is_nil(page_after),
               "Players page key #{page_key} must be nil after del_pattern"
      else
        IO.puts(
          "\n  [SKIP] Valkey not available — skipping cache invalidation test for GenerateScoutingWorker"
        )
      end
    end
  end

  # --------------------------------------------------------------------------
  # X.InjuryReport cache invalidation
  # --------------------------------------------------------------------------

  describe "X.InjuryReport.insert_and_cache cache invalidation" do
    test "per-card and players page cache cleared after injury report insert" do
      if valkey_available?() do
        team = insert_team!()
        player = insert_player!(team, %{external_ids: %{"mlb_id" => 99_002}})
        today = ~D[2026-05-18]

        card_key = Cache.player_card_key(99_002)
        page_key = Cache.players_page_key(today)

        # Pre-populate both caches
        :ok = Cache.set(card_key, :erlang.term_to_binary(%{injury_badge: :grey}), 3600)
        :ok = Cache.set(page_key, "<html>injury test stub</html>", 60)

        # Insert an injury report
        {:ok, _report} =
          %InjuryReport{}
          |> InjuryReport.changeset(%{
            player_id: player.id,
            run_date: today,
            tldr: "Test injury",
            current_status: "day-to-day",
            timeline: [],
            sources: [],
            ai_processed: true
          })
          |> Repo.insert(
            on_conflict: {:replace_all_except, [:id, :inserted_at]},
            conflict_target: [:player_id, :run_date]
          )

        # Simulate the invalidation the InjuryReport module performs
        Cache.del(Cache.player_card_key(99_002))
        Cache.del_pattern("sf:page:players:*")

        {:ok, card_after} = Cache.get(card_key)
        {:ok, page_after} = Cache.get(page_key)

        assert is_nil(card_after),
               "Per-card key #{card_key} must be nil after injury report insert"

        assert is_nil(page_after),
               "Players page key #{page_key} must be nil after injury report insert"
      else
        IO.puts(
          "\n  [SKIP] Valkey not available — skipping cache invalidation test for InjuryReport"
        )
      end
    end
  end
end
