defmodule SportsFanaticWeb.PlayerControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Content.PlayerSourceUrl
  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.Repo

  # --- Helpers ---

  defp create_team(attrs \\ %{}) do
    defaults = %{
      name: "Test Team #{System.unique_integer([:positive])}",
      city: "Test City",
      slug: "test-team-#{System.unique_integer([:positive])}"
    }

    Repo.insert!(Team.changeset(%Team{}, Map.merge(defaults, attrs)))
  end

  defp create_player(team, attrs \\ %{}) do
    defaults = %{
      full_name: "Test Player #{System.unique_integer([:positive])}",
      slug: "test-player-#{System.unique_integer([:positive])}",
      status: "active",
      team_id: team.id
    }

    Repo.insert!(Player.changeset(%Player{}, Map.merge(defaults, attrs)))
  end

  defp create_source_url(player, attrs \\ %{}) do
    defaults = %{
      player_id: player.id,
      url: "https://example.com/article-#{System.unique_integer([:positive])}",
      source_type: "news",
      classification: "general_news",
      content_summary: "Test summary content",
      key_facts: %{"facts" => ["Fact one", "Fact two"]},
      processed_at: DateTime.utc_now()
    }

    Repo.insert!(PlayerSourceUrl.changeset(%PlayerSourceUrl{}, Map.merge(defaults, attrs)))
  end

  describe "GET /mlb/players" do
    test "renders 200 with player listing", %{conn: conn} do
      conn = get(conn, "/mlb/players")
      assert html_response(conn, 200) =~ "MLB Players"
    end

    test "renders page with pagination params", %{conn: conn} do
      conn = get(conn, "/mlb/players?page=1")
      assert html_response(conn, 200) =~ "MLB Players"
    end
  end

  describe "GET /mlb/players/:team_slug/:player_slug" do
    setup do
      team = create_team(%{name: "Yankees", city: "New York", slug: "new-york-yankees"})
      player = create_player(team, %{full_name: "Aaron Judge", slug: "aaron-judge"})
      {:ok, team: team, player: player}
    end

    test "renders 200 for valid active player", %{conn: conn, team: team, player: player} do
      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}")
      assert html_response(conn, 200) =~ player.full_name
    end

    test "includes player name in page title", %{conn: conn, team: team, player: player} do
      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}")
      response = html_response(conn, 200)
      assert response =~ player.full_name
    end

    test "includes team name in response", %{conn: conn, team: team, player: player} do
      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}")
      response = html_response(conn, 200)
      assert response =~ team.name
    end

    test "does not render AI Scouting Intelligence section", %{
      conn: conn,
      team: team,
      player: player
    } do
      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}")
      response = html_response(conn, 200)
      refute response =~ "AI Scouting Intelligence"
    end

    test "renders Quick Links with category links when sources exist", %{
      conn: conn,
      team: team,
      player: player
    } do
      create_source_url(player, %{classification: "fantasy_value"})
      create_source_url(player, %{classification: "prospect_evaluation"})

      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}")
      response = html_response(conn, 200)
      assert response =~ "Quick Links"
      assert response =~ "Fantasy Value"
      assert response =~ "Prospect Evaluation"
      assert response =~ "/sources/fantasy_value"
      assert response =~ "/sources/prospect_evaluation"
    end

    test "returns 404 for non-existent team slug", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/players/nonexistent-team/some-player")
      end
    end

    test "returns 404 for non-existent player slug", %{conn: conn, team: team} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/players/#{team.slug}/nonexistent-player")
      end
    end

    test "shows inactive player page (IL players are still viewable)", %{conn: conn, team: team} do
      _inactive_player =
        create_player(team, %{
          full_name: "Inactive Player",
          slug: "inactive-player",
          status: "inactive"
        })

      conn = get(conn, "/mlb/players/#{team.slug}/inactive-player")
      assert html_response(conn, 200) =~ "Inactive Player"
    end

    test "shows retired player page", %{conn: conn, team: team} do
      _retired_player =
        create_player(team, %{
          full_name: "Retired Player",
          slug: "retired-player",
          status: "retired"
        })

      conn = get(conn, "/mlb/players/#{team.slug}/retired-player")
      assert html_response(conn, 200) =~ "Retired Player"
    end

    test "renders player overview section", %{conn: conn, team: team, player: player} do
      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}")
      response = html_response(conn, 200)
      assert response =~ "Player Overview"
    end
  end

  describe "GET /mlb/players/:team_slug/:player_slug/sources/:category" do
    setup do
      team = create_team(%{name: "Red Sox", city: "Boston", slug: "boston-red-sox"})
      player = create_player(team, %{full_name: "Rafael Devers", slug: "rafael-devers"})
      {:ok, team: team, player: player}
    end

    test "renders 200 for valid category with sources", %{
      conn: conn,
      team: team,
      player: player
    } do
      create_source_url(player, %{
        classification: "fantasy_value",
        content_summary: "Devers fantasy analysis"
      })

      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}/sources/fantasy_value")
      response = html_response(conn, 200)
      assert response =~ "Fantasy Value"
      assert response =~ "Devers fantasy analysis"
      assert response =~ player.full_name
    end

    test "renders 200 with empty state when no sources", %{
      conn: conn,
      team: team,
      player: player
    } do
      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}/sources/injury_report")
      response = html_response(conn, 200)
      assert response =~ "No injury report sources available"
    end

    test "renders source with digest", %{conn: conn, team: team, player: player} do
      create_source_url(player, %{
        classification: "performance_analysis",
        content_summary: "Performance breakdown",
        digest: "Devers has been on a tear this season, batting well above league average."
      })

      conn =
        get(conn, "/mlb/players/#{team.slug}/#{player.slug}/sources/performance_analysis")

      response = html_response(conn, 200)
      assert response =~ "Devers has been on a tear this season"
    end

    test "renders content_summary when no digest available", %{
      conn: conn,
      team: team,
      player: player
    } do
      create_source_url(player, %{
        classification: "general_news",
        content_summary: "News about Devers trade rumors"
      })

      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}/sources/general_news")
      response = html_response(conn, 200)
      assert response =~ "News about Devers trade rumors"
    end

    test "returns 404 for invalid category", %{conn: conn, team: team, player: player} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/players/#{team.slug}/#{player.slug}/sources/invalid_category")
      end
    end

    test "returns 404 for non-existent player", %{conn: conn, team: team} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/players/#{team.slug}/nonexistent/sources/general_news")
      end
    end

    test "includes breadcrumbs with player link", %{conn: conn, team: team, player: player} do
      conn = get(conn, "/mlb/players/#{team.slug}/#{player.slug}/sources/general_news")
      response = html_response(conn, 200)
      assert response =~ player.full_name
      assert response =~ "/mlb/players/#{team.slug}/#{player.slug}"
    end
  end

  describe "GET /mlb/players (index active filter)" do
    test "does not include inactive players in listing", %{conn: conn} do
      team = create_team(%{slug: "boston-red-sox"})

      _active =
        create_player(team, %{full_name: "Active Star", slug: "active-star", status: "active"})

      _inactive =
        create_player(team, %{full_name: "Bench Warmer", slug: "bench-warmer", status: "inactive"})

      conn = get(conn, "/mlb/players")
      response = html_response(conn, 200)

      assert response =~ "Active Star"
      refute response =~ "Bench Warmer"
    end
  end
end
