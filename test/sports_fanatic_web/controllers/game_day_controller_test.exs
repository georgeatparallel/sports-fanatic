defmodule SportsFanaticWeb.GameDayControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.Team
  alias SportsFanatic.Content.GameDayMagazine

  defp create_team(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      name: "GD Team #{n}",
      city: "GD City #{n}",
      slug: "gd-city-#{n}-team-#{n}"
    }

    Repo.insert!(Team.changeset(%Team{}, Map.merge(defaults, attrs)))
  end

  defp create_magazine(away_team, home_team, attrs \\ %{}) do
    n = System.unique_integer([:positive])
    today = Date.utc_today()

    defaults = %{
      game_date: today,
      away_team_id: away_team.id,
      home_team_id: home_team.id,
      slug: "#{away_team.slug}-vs-#{home_team.slug}-#{n}",
      headline: "#{away_team.name} vs #{home_team.name} Preview",
      matchup_analysis: "This is the matchup analysis for this game.",
      away_lineup: %{players: []},
      home_lineup: %{players: []},
      away_pitcher: %{name: "Pitcher A"},
      home_pitcher: %{name: "Pitcher B"},
      status: "published"
    }

    Repo.insert!(GameDayMagazine.changeset(%GameDayMagazine{}, Map.merge(defaults, attrs)))
  end

  describe "GET /mlb/game-day/:date/:slug" do
    setup do
      away_team = create_team()
      home_team = create_team()
      today_str = Date.to_iso8601(Date.utc_today())
      magazine = create_magazine(away_team, home_team)
      {:ok, away_team: away_team, home_team: home_team, magazine: magazine, today_str: today_str}
    end

    test "renders 200 with magazine headline", %{conn: conn, magazine: magazine, today_str: today_str} do
      conn = get(conn, "/mlb/game-day/#{today_str}/#{magazine.slug}")
      assert html_response(conn, 200) =~ magazine.headline
    end

    test "renders team names in the response", %{conn: conn, magazine: magazine, away_team: away_team, home_team: home_team, today_str: today_str} do
      conn = get(conn, "/mlb/game-day/#{today_str}/#{magazine.slug}")
      body = html_response(conn, 200)
      assert body =~ away_team.name
      assert body =~ home_team.name
    end

    test "returns 404 for non-existent slug", %{conn: conn, today_str: today_str} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, "/mlb/game-day/#{today_str}/nonexistent-slug-here")
      end
    end
  end
end
