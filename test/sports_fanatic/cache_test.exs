defmodule SportsFanatic.CacheTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Cache

  # These tests verify key builder functions and TTL logic without needing Valkey.
  # The Redix-dependent functions (get/set/del) require a live Valkey connection
  # and are tagged as integration tests.

  describe "key builders" do
    test "player_page_key/2 returns correct key" do
      key = Cache.player_page_key("new-york-yankees", "aaron-judge")
      assert key == "sf:page:player:new-york-yankees:aaron-judge"
    end

    test "team_page_key/1 returns correct key" do
      key = Cache.team_page_key("los-angeles-dodgers")
      assert key == "sf:page:team:los-angeles-dodgers"
    end

    test "lineup_page_key/1 returns correct key" do
      key = Cache.lineup_page_key("2026-04-19")
      assert key == "sf:page:lineup:2026-04-19"
    end

    test "news_page_key/2 with slug returns correct key" do
      key = Cache.news_page_key("2026-04-19", "judge-hits-home-run")
      assert key == "sf:page:news:2026-04-19:judge-hits-home-run"
    end

    test "news_page_key/1 without slug returns date key" do
      key = Cache.news_page_key("2026-04-19")
      assert key == "sf:page:news:2026-04-19"
    end

    test "scouting_page_key/2 returns correct key" do
      key = Cache.scouting_page_key("new-york-yankees", "aaron-judge")
      assert key == "sf:page:scouting:new-york-yankees:aaron-judge"
    end

    test "gameday_page_key/2 returns correct key" do
      key = Cache.gameday_page_key("2026-04-19", "new-york-yankees-vs-boston-red-sox")
      assert key == "sf:page:gameday:2026-04-19:new-york-yankees-vs-boston-red-sox"
    end

    test "sitemap_key/1 returns correct key" do
      key = Cache.sitemap_key("players")
      assert key == "sf:sitemap:players"
    end
  end

  describe "key namespace conventions" do
    test "all player page keys start with sf:page:player:" do
      key = Cache.player_page_key("team", "player")
      assert String.starts_with?(key, "sf:page:player:")
    end

    test "all team page keys start with sf:page:team:" do
      key = Cache.team_page_key("team")
      assert String.starts_with?(key, "sf:page:team:")
    end

    test "all sitemap keys start with sf:sitemap:" do
      key = Cache.sitemap_key("players")
      assert String.starts_with?(key, "sf:sitemap:")
    end

    test "all news feed data keys start with sf:data:news:feed:" do
      key = Cache.news_feed_key("2026-05-01")
      assert String.starts_with?(key, "sf:data:news:feed:")
    end
  end

  describe "news_feed_key/1" do
    test "accepts an ISO 8601 date string and returns correct key" do
      key = Cache.news_feed_key("2026-05-01")
      assert key == "sf:data:news:feed:2026-05-01"
    end

    test "accepts a Date struct and returns correct key" do
      key = Cache.news_feed_key(~D[2026-05-01])
      assert key == "sf:data:news:feed:2026-05-01"
    end

    test "Date struct and string yield the same key" do
      string_key = Cache.news_feed_key("2026-05-01")
      date_key = Cache.news_feed_key(~D[2026-05-01])
      assert string_key == date_key
    end

    test "different dates produce different keys" do
      key1 = Cache.news_feed_key("2026-05-01")
      key2 = Cache.news_feed_key("2026-05-02")
      refute key1 == key2
    end
  end
end
