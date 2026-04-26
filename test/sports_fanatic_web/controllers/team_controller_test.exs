defmodule SportsFanaticWeb.TeamControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.Team

  defp create_team(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      name: "Team #{n}",
      city: "City #{n}",
      slug: "city-#{n}-team-#{n}"
    }

    Repo.insert!(Team.changeset(%Team{}, Map.merge(defaults, attrs)))
  end

  describe "GET /mlb/teams" do
    test "renders 200 with team listing", %{conn: conn} do
      conn = get(conn, "/mlb/teams")
      assert html_response(conn, 200) =~ "MLB Teams"
    end

    test "renders teams that exist in the database", %{conn: conn} do
      team =
        create_team(%{name: "Visible Team", city: "Some City", slug: "some-city-visible-team"})

      conn = get(conn, "/mlb/teams")
      assert html_response(conn, 200) =~ team.name
    end
  end

  describe "GET /mlb/teams/:team_slug" do
    setup do
      team = create_team(%{name: "Red Sox", city: "Boston", slug: "boston-red-sox"})
      {:ok, team: team}
    end

    test "renders 200 for valid team", %{conn: conn, team: team} do
      conn = get(conn, "/mlb/teams/#{team.slug}")
      assert html_response(conn, 200) =~ team.name
    end

    test "renders team city in response", %{conn: conn, team: team} do
      conn = get(conn, "/mlb/teams/#{team.slug}")
      assert html_response(conn, 200) =~ team.city
    end

    test "returns 404 for non-existent team slug", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/teams/nonexistent-team-slug")
      end
    end
  end
end
