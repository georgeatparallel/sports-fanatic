defmodule SportsFanatic.Mlb.GameCardUnitTest do
  @moduledoc """
  Pure-unit coverage for the helpers behind
  `SportsFanatic.Mlb.todays_game_for_player/2`. No Postgres, no Valkey —
  just the in-process formatters and the cache key builder.
  """
  use ExUnit.Case, async: true

  alias SportsFanatic.Cache
  alias SportsFanatic.Mlb

  describe "format_et_time/1" do
    test "formats a UTC %DateTime{} as ET wall-clock" do
      # 23:05 UTC on 2026-05-18 = 19:05 ET (EDT, UTC-4)
      {:ok, dt, _} = DateTime.from_iso8601("2026-05-18T23:05:00Z")
      assert Mlb.format_et_time(dt) == "7:05 PM ET"
    end

    test "formats an afternoon UTC datetime as ET wall-clock" do
      {:ok, dt, _} = DateTime.from_iso8601("2026-05-18T17:35:00Z")
      assert Mlb.format_et_time(dt) == "1:35 PM ET"
    end

    test "accepts a %NaiveDateTime{}" do
      ndt = ~N[2026-05-18 23:05:00]
      assert Mlb.format_et_time(ndt) == "7:05 PM ET"
    end

    test "returns nil for nil input" do
      assert Mlb.format_et_time(nil) == nil
    end

    test "returns nil for arbitrary garbage" do
      assert Mlb.format_et_time("not a datetime") == nil
      assert Mlb.format_et_time(:atom) == nil
    end
  end

  describe "Cache.game_card_key/2" do
    test "builds the canonical key with a binary UUID and a Date struct" do
      key = Cache.game_card_key("11111111-2222-3333-4444-555555555555", ~D[2026-05-18])
      assert key == "sf:data:game_card:player:11111111-2222-3333-4444-555555555555:2026-05-18"
    end

    test "builds the canonical key with a binary UUID and an ISO date string" do
      key = Cache.game_card_key("11111111-2222-3333-4444-555555555555", "2026-05-18")
      assert key == "sf:data:game_card:player:11111111-2222-3333-4444-555555555555:2026-05-18"
    end

    test "key starts with the expected namespace prefix" do
      key = Cache.game_card_key("p1", ~D[2026-05-18])
      assert String.starts_with?(key, "sf:data:game_card:player:")
    end

    test "different dates produce different keys" do
      k1 = Cache.game_card_key("p1", ~D[2026-05-18])
      k2 = Cache.game_card_key("p1", ~D[2026-05-19])
      refute k1 == k2
    end

    test "different player ids produce different keys" do
      k1 = Cache.game_card_key("p1", ~D[2026-05-18])
      k2 = Cache.game_card_key("p2", ~D[2026-05-18])
      refute k1 == k2
    end
  end

  describe "todays_game_for_player/2 — no team" do
    alias SportsFanatic.Mlb.Player

    test "returns nil immediately for a player with no team_id (no cache hit, no DB)" do
      player = %Player{id: "00000000-0000-0000-0000-000000000000", team_id: nil}
      assert Mlb.todays_game_for_player(player, ~D[2026-05-18]) == nil
    end

    test "returns nil for nil/garbage input" do
      assert Mlb.todays_game_for_player(nil, ~D[2026-05-18]) == nil
      assert Mlb.todays_game_for_player(42, ~D[2026-05-18]) == nil
    end
  end
end
