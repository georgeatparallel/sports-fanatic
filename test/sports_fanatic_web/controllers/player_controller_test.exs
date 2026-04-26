defmodule SportsFanaticWeb.PlayerControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

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

    test "renders 200 for valid player", %{conn: conn, team: team, player: player} do
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
  end
end
