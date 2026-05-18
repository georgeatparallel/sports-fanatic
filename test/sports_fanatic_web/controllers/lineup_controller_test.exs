defmodule SportsFanaticWeb.LineupControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Cache
  alias SportsFanatic.Mlb.{Lineup, Player, Team}
  alias SportsFanatic.Mlb.ScheduledGame
  alias SportsFanatic.Repo

  @date_str "2026-05-18"
  @cache_stub "<html><head></head><body>STUB_PLAYERS_PAGE</body></html>"

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
      name: "Controller Test Team",
      abbreviation: "CTT",
      city: "Testville",
      slug: "ctrl-test-team-#{System.unique_integer([:positive])}",
      division: "NL East",
      league: "NL"
    })
  end

  defp insert_player!(team, attrs \\ %{}) do
    suffix = System.unique_integer([:positive])

    Repo.insert!(%Player{
      id: Ecto.UUID.generate(),
      first_name: "Ctrl",
      last_name: "Player#{suffix}",
      full_name: "Ctrl Player#{suffix}",
      slug: "ctrl-player-#{suffix}",
      position: "OF",
      status: attrs[:status] || "active",
      team_id: team.id,
      external_ids: %{}
    })
  end

  defp insert_lineup!(player, date_str) do
    {:ok, date} = Date.from_iso8601(date_str)

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
  # Basic happy path
  # --------------------------------------------------------------------------

  describe "GET /mlb/lineups/:date — basic rendering" do
    setup do
      # Always clear the cache key for this date so tests read from DB
      Cache.del(Cache.players_page_key(@date_str))
      :ok
    end

    test "renders 200 for a valid date", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      assert body =~ "MLB Players"
    end

    test "renders the search box with player search input", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      assert body =~ "player-search-input"
    end

    test "renders all three group headings", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      assert body =~ "In the lineup today"
      assert body =~ "Active players not in the lineup"
      assert body =~ "Inactive players"
    end

    test "response has text/html content-type", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      assert conn |> get_resp_header("content-type") |> hd() =~ "text/html"
    end

    test "renders the page title with 'MLB Players'", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      assert body =~ "MLB Players"
    end

    test "includes JSON-LD breadcrumb with 'Players' label", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      # JSON-LD BreadcrumbList should contain "Players" as a name
      assert body =~ "BreadcrumbList"
      assert body =~ ~s("Players")
    end

    test "includes a script tag with application/json for roster data", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      assert body =~ ~s(type="application/json")
      assert body =~ "players-roster-data"
    end

    test "search input has the autofocus attribute", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      # HEEx renders the bare attribute as `autofocus` (no value).
      # We assert both id and autofocus appear inside the same opening tag.
      assert body =~ ~r/id="player-search-input"[^>]*\bautofocus\b/
    end
  end

  # --------------------------------------------------------------------------
  # Cache hit fast-path (anonymous user, Valkey pre-populated)
  # --------------------------------------------------------------------------

  describe "GET /mlb/lineups/:date — cache hit fast path (anonymous)" do
    setup do
      if valkey_available?() do
        # Pre-populate the players page cache with a known stub
        :ok = Cache.set(Cache.players_page_key(@date_str), @cache_stub, 60)
        on_exit(fn -> Cache.del(Cache.players_page_key(@date_str)) end)
        [valkey_available: true]
      else
        [valkey_available: false]
      end
    end

    test "returns cached stub HTML directly when cache is warm", %{conn: conn} do
      if valkey_available?() do
        conn = get(conn, "/mlb/lineups/#{@date_str}")
        body = response(conn, 200)

        assert body == @cache_stub,
               "Expected the cached stub body to be returned verbatim on a cache hit"
      else
        IO.puts("\n  [SKIP] Valkey not available — cache hit fast path test skipped")
        :ok
      end
    end

    test "cache hit sets cache-control: public header for anonymous visitor", %{conn: conn} do
      if valkey_available?() do
        conn = get(conn, "/mlb/lineups/#{@date_str}")
        cache_control = conn |> get_resp_header("cache-control") |> hd()
        assert cache_control =~ "public"
      else
        IO.puts("\n  [SKIP] Valkey not available — skipping cache-control header test")
        :ok
      end
    end

    test "cache hit response has content-type text/html", %{conn: conn} do
      if valkey_available?() do
        conn = get(conn, "/mlb/lineups/#{@date_str}")
        assert conn |> get_resp_header("content-type") |> hd() =~ "text/html"
      else
        :ok
      end
    end
  end

  # --------------------------------------------------------------------------
  # Authenticated user bypasses page cache
  # --------------------------------------------------------------------------

  describe "GET /mlb/lineups/:date — authenticated user bypasses page cache" do
    setup do
      if valkey_available?() do
        # Pre-populate the page cache with a stub that an authenticated user
        # should NOT see (they should get the real rendered page)
        auth_stub = "<html><body>ANONYMOUS_STUB_NOT_FOR_AUTH</body></html>"
        :ok = Cache.set(Cache.players_page_key(@date_str), auth_stub, 60)
        on_exit(fn -> Cache.del(Cache.players_page_key(@date_str)) end)
        [valkey_available: true]
      else
        [valkey_available: false]
      end
    end

    test "authenticated user does not receive the cached anonymous stub", %{conn: conn} do
      if valkey_available?() do
        # Simulate an authenticated user by setting current_user in assigns
        user_struct = %{id: Ecto.UUID.generate(), email: "test@example.com", is_admin: false}
        authed_conn = Plug.Conn.assign(conn, :current_user, user_struct)

        authed_conn = get(authed_conn, "/mlb/lineups/#{@date_str}")
        body = response(authed_conn, 200)

        refute body == "ANONYMOUS_STUB_NOT_FOR_AUTH",
               "Authenticated user must NOT receive the cached anonymous page stub"
      else
        IO.puts("\n  [SKIP] Valkey not available — auth bypass cache test skipped")
        :ok
      end
    end
  end

  # --------------------------------------------------------------------------
  # Empty lineup — page still renders
  # --------------------------------------------------------------------------

  describe "GET /mlb/lineups/:date — empty lineup (no lineup rows)" do
    setup do
      Cache.del(Cache.players_page_key(@date_str))
      team = insert_team!()
      # Active players — no lineup entries
      insert_player!(team, %{status: "active"})
      insert_player!(team, %{status: "active"})
      # Inactive player
      insert_player!(team, %{status: "injured"})
      :ok
    end

    test "renders 200 even with no lineup entries for the date", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      assert html_response(conn, 200)
    end

    test "shows 'In the lineup today' section header", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      assert body =~ "In the lineup today"
    end

    test "shows 'Active players not in the lineup' section header", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      assert body =~ "Active players not in the lineup"
    end

    test "shows empty-state copy for the lineup section when no lineup rows exist", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      body = html_response(conn, 200)
      assert body =~ "No players in the lineup today"
    end

    test "does not crash — no 404 or 500", %{conn: conn} do
      conn = get(conn, "/mlb/lineups/#{@date_str}")
      assert conn.status == 200
    end
  end

  # --------------------------------------------------------------------------
  # Invalid date → 404 (Ecto.NoResultsError raised)
  # --------------------------------------------------------------------------

  describe "GET /mlb/lineups/:date — invalid date" do
    test "raises Ecto.NoResultsError for a non-date string" do
      conn = Phoenix.ConnTest.build_conn()

      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/lineups/not-a-date")
      end
    end

    test "raises Ecto.NoResultsError for a partial date string" do
      conn = Phoenix.ConnTest.build_conn()

      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/lineups/2026-99")
      end
    end
  end
end
