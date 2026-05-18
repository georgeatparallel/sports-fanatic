defmodule SportsFanaticWeb.ScoutingControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Content.ScoutingReport
  alias SportsFanatic.Mlb.{Player, ScheduledGame, Team}
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

  defp create_scheduled_game(home_team_name, away_team_name, game_date, attrs \\ %{}) do
    n = System.unique_integer([:positive])

    defaults = %{
      game_id: n,
      game_date: game_date,
      game_datetime: DateTime.new!(game_date, ~T[23:05:00], "Etc/UTC"),
      home_name: home_team_name,
      away_name: away_team_name,
      home_probable_pitcher: "Home Pitcher #{n}",
      away_probable_pitcher: "Away Pitcher #{n}",
      venue_name: "Test Stadium #{n}",
      status: "scheduled"
    }

    Repo.insert!(ScheduledGame.changeset(%ScheduledGame{}, Map.merge(defaults, attrs)))
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

  # --------------------------------------------------------------------------
  # Game card integration — regression for the "No game today" bug
  # --------------------------------------------------------------------------

  describe "GET /mlb/scouting/:team_slug/:player_slug — game card" do
    setup do
      team = create_team()
      player = create_player(team)
      {:ok, team: team, player: player}
    end

    # REGRESSION: before the fix the controller looked up mlb.hit_predictions
    # (always nil in prod because no player has an mlb_id) and rendered
    # "No game today for this player." when the lookup returned nil. The new
    # template never contains that literal string — both game_card_panel/1 and
    # today_hit_banner/1 render nothing when their assigns are nil.
    test "does NOT render 'No game today' copy when no scheduled game exists (off-day)", %{
      conn: conn,
      team: team,
      player: player
    } do
      # No scheduled game inserted for the player's team today.
      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      assert body =~ player.full_name
      refute body =~ "No game today"
    end

    test "does NOT render 'No game today' copy when no scheduled game exists and no report", %{
      conn: conn,
      team: team,
      player: player
    } do
      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      refute body =~ "No game today"
      # The empty-state scouting report message IS shown
      assert body =~ "No scouting report available yet"
    end

    test "renders game card when a home scheduled game exists for today", %{
      conn: conn,
      team: team,
      player: player
    } do
      today = SportsFanatic.DateHelper.today()
      away_team = create_team(%{name: "Visiting Team"})

      create_scheduled_game(team.name, away_team.name, today, %{
        home_probable_pitcher: "Home Starter",
        away_probable_pitcher: "Away Starter",
        venue_name: "Home Park"
      })

      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      assert body =~ "Today&#39;s Game" or body =~ "Today's Game"
      assert body =~ "vs"
      assert body =~ "Away Starter"
      assert body =~ "Home Park"
      refute body =~ "No game today"
    end

    test "renders game card with '@' prefix for an away scheduled game", %{
      conn: conn,
      team: team,
      player: player
    } do
      today = SportsFanatic.DateHelper.today()
      home_team = create_team(%{name: "Home Side Team"})

      create_scheduled_game(home_team.name, team.name, today, %{
        home_probable_pitcher: "Home Starter",
        away_probable_pitcher: "Away Starter",
        venue_name: "Away Stadium"
      })

      conn = get(conn, "/mlb/scouting/#{team.slug}/#{player.slug}")
      body = html_response(conn, 200)

      assert body =~ "Today&#39;s Game" or body =~ "Today's Game"
      assert body =~ "@"
      assert body =~ "Home Starter"
      assert body =~ "Away Stadium"
      refute body =~ "No game today"
    end
  end
end
