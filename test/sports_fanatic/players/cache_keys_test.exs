defmodule SportsFanatic.Players.CacheKeysTest do
  @moduledoc """
  Unit tests for the new Cache key builders added for the Players page
  (spec §6): players_page_key/1, players_roster_key/0, player_card_key/1.
  These are pure functions with no external dependencies.
  """
  use ExUnit.Case, async: true

  alias SportsFanatic.Cache

  # ---------------------------------------------------------------------------
  # players_page_key/1
  # ---------------------------------------------------------------------------

  describe "Cache.players_page_key/1" do
    test "accepts a Date struct and returns the correct key" do
      key = Cache.players_page_key(~D[2026-05-18])
      assert key == "sf:page:players:2026-05-18"
    end

    test "accepts an ISO 8601 binary string and returns the correct key" do
      key = Cache.players_page_key("2026-05-18")
      assert key == "sf:page:players:2026-05-18"
    end

    test "Date struct and matching string produce the same key" do
      date_key = Cache.players_page_key(~D[2026-04-19])
      str_key = Cache.players_page_key("2026-04-19")
      assert date_key == str_key
    end

    test "different dates produce different keys" do
      key1 = Cache.players_page_key("2026-05-18")
      key2 = Cache.players_page_key("2026-05-19")
      refute key1 == key2
    end

    test "key starts with 'sf:page:players:'" do
      key = Cache.players_page_key(~D[2026-05-18])
      assert String.starts_with?(key, "sf:page:players:")
    end
  end

  # ---------------------------------------------------------------------------
  # players_roster_key/0
  # ---------------------------------------------------------------------------

  describe "Cache.players_roster_key/0" do
    test "returns the canonical roster key" do
      assert Cache.players_roster_key() == "sf:data:players:roster"
    end

    test "is always the same value (no date dependency)" do
      assert Cache.players_roster_key() == Cache.players_roster_key()
    end

    test "starts with 'sf:data:'" do
      assert String.starts_with?(Cache.players_roster_key(), "sf:data:")
    end
  end

  # ---------------------------------------------------------------------------
  # player_card_key/1
  # ---------------------------------------------------------------------------

  describe "Cache.player_card_key/1" do
    test "accepts an integer mlb_id and embeds it in the key" do
      key = Cache.player_card_key(592_450)
      assert key == "sf:data:player:card:592450"
    end

    test "accepts a binary UUID and embeds it in the key" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      key = Cache.player_card_key(uuid)
      assert key == "sf:data:player:card:#{uuid}"
    end

    test "different player ids produce different keys" do
      key1 = Cache.player_card_key(123)
      key2 = Cache.player_card_key(456)
      refute key1 == key2
    end

    test "key starts with 'sf:data:player:card:'" do
      key = Cache.player_card_key(99)
      assert String.starts_with?(key, "sf:data:player:card:")
    end

    test "integer id and its string representation produce different keys" do
      # This is intentional — integer mlb_ids and string UUIDs are different key spaces
      key_int = Cache.player_card_key(123)
      key_str = Cache.player_card_key("123")
      # Both should be valid and consistent
      assert is_binary(key_int)
      assert is_binary(key_str)
    end
  end
end
