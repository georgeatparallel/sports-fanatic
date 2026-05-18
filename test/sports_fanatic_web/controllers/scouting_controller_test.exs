defmodule SportsFanaticWeb.ScoutingControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.Repo

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

  defp create_report(player, attrs \\ %{}) do
    today = SportsFanatic.DateHelper.today()

    defaults = %{
      player_id: player.id,
      report_date: today,
      summary: "Summary for #{player.full_name}.",
      overall_grade: "B",
      full_report: %{},
      strengths: [],
      weaknesses: [],
      injury_risk: "healthy",
      sources_count: 0
    }

    Repo.insert!(ScoutingReport.changeset(%ScoutingReport{}, Map.merge(defaults, attrs)))
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

    test "renders the full report when one exists", %{conn: conn, team: team, player: player} do
      create_report(player, %{
        summary: "Detailed scouting analysis.",
        overall_grade: "A",
        strengths: ["s1", "s2", "s3", "s4"],
        weaknesses: ["w1", "w2", "w3"],
        hit_probability: 0.40,
        hr_probability: 0.07,
        injury_risk: "healthy",
        sources_count: 10,
        full_report: %{}
      })

      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      # Section headers
      assert body =~ "Summary"
      assert body =~ "Strengths"
      assert body =~ "Weaknesses"
      assert body =~ "Predictions"
      assert body =~ "Injury Status"

      # Grade rendered
      assert body =~ ">A<"

      # All strengths and weaknesses rendered (not truncated to 2)
      assert body =~ "s1"
      assert body =~ "s2"
      assert body =~ "s3"
      assert body =~ "s4"
      assert body =~ "w1"
      assert body =~ "w2"
      assert body =~ "w3"

      # Hit / HR probability rendered as percentages
      assert body =~ "40.0%"
      assert body =~ "7.0%"
    end

    test "does not render the legacy 'Unlock Full Report' gate", %{
      conn: conn,
      team: team,
      player: player
    } do
      create_report(player, %{
        summary: "Detailed scouting analysis.",
        strengths: ["s1", "s2", "s3", "s4"],
        weaknesses: ["w1", "w2", "w3"],
        full_report: %{}
      })

      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      refute body =~ "Unlock Full Report"
      refute body =~ "This is a preview of the full scouting report"
    end

    test "renders 'no report yet' empty state when no report exists", %{
      conn: conn,
      team: team,
      player: player
    } do
      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      assert body =~ "No scouting report available yet"
      assert body =~ "Reports are generated daily"

      refute body =~ "Unlock Full Report"
      refute body =~ "Subscribe for complete analysis"
    end

    test "renders the empty-state probability line when both probs are nil", %{
      conn: conn,
      team: team,
      player: player
    } do
      create_report(player, %{
        summary: "Detailed scouting analysis.",
        hit_probability: nil,
        hr_probability: nil,
        full_report: %{}
      })

      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      assert body =~ "No probability data available for this report"
    end

    test "renders without crashing when optional fields are nil", %{
      conn: conn,
      team: team,
      player: player
    } do
      # Inserts a report with all optional array/value fields nil so the
      # nil-guard branches in the template are exercised.
      create_report(player, %{
        summary: "Nil-field guard test.",
        weaknesses: nil,
        strengths: nil,
        hit_probability: nil,
        hr_probability: nil,
        injury_risk: nil,
        injury_detail: nil,
        confidence_modifier: nil,
        sources_count: nil,
        full_report: %{}
      })

      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      # Page must render successfully and show the Summary section
      assert body =~ "Summary"
      assert body =~ "Nil-field guard test."

      # Sections gated on nil should be absent
      refute body =~ "Strengths"
      refute body =~ "Weaknesses"
      refute body =~ "Unlock Full Report"
    end
  end
end
