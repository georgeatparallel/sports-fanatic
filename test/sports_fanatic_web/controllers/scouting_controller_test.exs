defmodule SportsFanaticWeb.ScoutingControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Team, Player}

  defp create_team(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      name: "Scouting Team #{n}",
      city: "City #{n}",
      slug: "scouting-city-#{n}-team-#{n}"
    }

    Repo.insert!(Team.changeset(%Team{}, Map.merge(defaults, attrs)))
  end

  defp create_player(team, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      full_name: "Scout Player #{n}",
      slug: "scout-player-#{n}",
      status: "active",
      team_id: team.id
    }

    Repo.insert!(Player.changeset(%Player{}, Map.merge(defaults, attrs)))
  end

  describe "GET /mlb/scouting/:team_slug/:player_slug" do
    setup do
      team = create_team()
      player = create_player(team)
      {:ok, team: team, player: player}
    end

    test "renders 200 with player name", %{conn: conn, team: team, player: player} do
      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      assert html_response(conn, 200) =~ player.full_name
    end

    test "renders scouting report page title", %{conn: conn, team: team, player: player} do
      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      assert html_response(conn, 200) =~ "Scouting"
    end

    test "returns 404 for non-existent team", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/scouting/nonexistent-team/some-player")
      end
    end

    test "returns 404 for non-existent player on valid team", %{conn: conn, team: team} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/scouting/#{team.slug}/nonexistent-player-slug")
      end
    end
  end
end
