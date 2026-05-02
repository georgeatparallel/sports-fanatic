defmodule SportsFanaticWeb.LineupHTMLTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @endpoint SportsFanaticWeb.Endpoint

  # Minimal structs that mirror what the controller passes to the template.
  # Using plain maps so these tests have zero database dependency.

  defp team_struct(attrs \\ %{}) do
    Map.merge(
      %{
        __struct__: SportsFanatic.Mlb.Team,
        id: "00000000-0000-0000-0000-000000000001",
        name: "New York Yankees",
        slug: "new-york-yankees",
        abbreviation: "NYY"
      },
      attrs
    )
  end

  defp player_struct(team, attrs \\ %{}) do
    Map.merge(
      %{
        __struct__: SportsFanatic.Mlb.Player,
        id: "00000000-0000-0000-0000-000000000002",
        full_name: "Aaron Judge",
        slug: "aaron-judge",
        team: team,
        external_ids: %{"nerds_id" => "12345"}
      },
      attrs
    )
  end

  defp lineup_struct(attrs \\ %{}) do
    team = Map.get(attrs, :_team)
    player = if team, do: player_struct(team, Map.get(attrs, :_player_attrs, %{})), else: nil

    base = %{
      __struct__: SportsFanatic.Mlb.Lineup,
      id: 1,
      player_nerds_id: 12_345,
      player_id: if(player, do: player.id),
      player: player,
      batting_order: 1,
      position: "RF",
      team_code: "NYY",
      game_date: ~D[2026-05-01]
    }

    base
    |> Map.merge(Map.drop(attrs, [:_team, :_player_attrs]))
  end

  # ---------------------------------------------------------------------------
  # team_link/1
  # ---------------------------------------------------------------------------

  describe "team_link/1 when team record is present" do
    test "renders an anchor tag pointing to the team page" do
      team = team_struct()

      html =
        render_component(&SportsFanaticWeb.LineupHTML.team_link/1,
          team: team,
          name: "New York Yankees"
        )

      assert html =~ ~s(<a href="/mlb/teams/new-york-yankees")
      assert html =~ "New York Yankees"
    end

    test "applies hover styling class to the link" do
      team = team_struct()

      html =
        render_component(&SportsFanaticWeb.LineupHTML.team_link/1,
          team: team,
          name: "New York Yankees"
        )

      assert html =~ "hover:text-blue-600"
    end

    test "renders name text inside the anchor" do
      team = team_struct(%{slug: "boston-red-sox"})

      html =
        render_component(&SportsFanaticWeb.LineupHTML.team_link/1,
          team: team,
          name: "Boston Red Sox"
        )

      assert html =~ "Boston Red Sox"
    end

    test "uses the team slug (not name) to build the URL" do
      team = team_struct(%{name: "Los Angeles Dodgers", slug: "los-angeles-dodgers"})

      html =
        render_component(&SportsFanaticWeb.LineupHTML.team_link/1,
          team: team,
          name: "Los Angeles Dodgers"
        )

      assert html =~ ~s(href="/mlb/teams/los-angeles-dodgers")
      refute html =~ ~s(href="/mlb/teams/Los Angeles Dodgers")
    end
  end

  describe "team_link/1 when team is nil" do
    test "renders a span (not an anchor) with the provided name" do
      html =
        render_component(&SportsFanaticWeb.LineupHTML.team_link/1,
          team: nil,
          name: "Unknown Team"
        )

      assert html =~ "<span>"
      assert html =~ "Unknown Team"
      refute html =~ "<a "
    end

    test "does not raise when name is an empty string" do
      html =
        render_component(&SportsFanaticWeb.LineupHTML.team_link/1,
          team: nil,
          name: ""
        )

      assert html =~ "<span>"
    end
  end

  # ---------------------------------------------------------------------------
  # player_link/1
  # ---------------------------------------------------------------------------

  describe "player_link/1 when player is preloaded on the lineup" do
    test "renders an anchor to the player page under the team slug" do
      team = team_struct()
      lineup = lineup_struct(%{_team: team})

      html =
        render_component(&SportsFanaticWeb.LineupHTML.player_link/1,
          lineup: lineup
        )

      assert html =~ ~s(href="/mlb/players/new-york-yankees/aaron-judge")
      assert html =~ "Aaron Judge"
    end

    test "applies hover styling class to the link" do
      team = team_struct()
      lineup = lineup_struct(%{_team: team})

      html =
        render_component(&SportsFanaticWeb.LineupHTML.player_link/1,
          lineup: lineup
        )

      assert html =~ "hover:text-blue-600"
    end

    test "uses the player's full_name as link text" do
      team = team_struct()

      lineup =
        lineup_struct(%{
          _team: team,
          _player_attrs: %{full_name: "Shohei Ohtani", slug: "shohei-ohtani"},
          player_nerds_id: 99_999
        })

      html =
        render_component(&SportsFanaticWeb.LineupHTML.player_link/1,
          lineup: lineup
        )

      assert html =~ "Shohei Ohtani"
      assert html =~ ~s(href="/mlb/players/new-york-yankees/shohei-ohtani")
    end
  end

  describe "player_link/1 when player is nil on the lineup" do
    test "renders a span with a fallback Player #ID label" do
      lineup = lineup_struct(%{player: nil, player_nerds_id: 99_999})

      html =
        render_component(&SportsFanaticWeb.LineupHTML.player_link/1,
          lineup: lineup
        )

      assert html =~ "<span>"
      assert html =~ "Player #99999"
      refute html =~ "<a "
    end

    test "does not raise when player is nil" do
      lineup = lineup_struct(%{player: nil})

      html =
        render_component(&SportsFanaticWeb.LineupHTML.player_link/1,
          lineup: lineup
        )

      assert html =~ "<span>"
    end
  end

  describe "player_link/1 when player has no associated team" do
    test "renders fallback span when player.team is nil" do
      player = player_struct(nil, %{team: nil})
      lineup = lineup_struct(%{player: player})

      html =
        render_component(&SportsFanaticWeb.LineupHTML.player_link/1,
          lineup: lineup
        )

      assert html =~ "<span>"
      assert html =~ "Player #12345"
      refute html =~ "<a "
    end
  end
end
