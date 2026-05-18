defmodule SportsFanaticWeb.Components.PlayerCardTest do
  @moduledoc """
  Unit tests for CoreComponents.player_card/1.
  Uses Phoenix.LiveViewTest.render_component/2 — no Postgres required.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  # A minimal player map that satisfies the component's reads.
  defp build_player(overrides \\ %{}) do
    Map.merge(
      %{
        full_name: "Aaron Judge",
        first_name: "Aaron",
        last_name: "Judge",
        position: "RF",
        headshot_url: nil,
        team: %{name: "New York Yankees", slug: "new-york-yankees"}
      },
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # Basic rendering
  # ---------------------------------------------------------------------------

  describe "player_card/1 — basic rendering" do
    test "renders the player's full name" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge"
        )

      assert html =~ "Aaron Judge"
    end

    test "renders the team name" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge"
        )

      assert html =~ "New York Yankees"
    end

    test "renders the player position" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge"
        )

      assert html =~ "RF"
    end

    test "renders an anchor tag pointing to link_target" do
      target = "/mlb/scouting/new-york-yankees/aaron-judge"

      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: target
        )

      assert html =~ ~s(href="#{target}")
    end

    test "renders initials fallback when headshot_url is nil" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(%{headshot_url: nil}),
          link_target: "/mlb/players/new-york-yankees/aaron-judge"
        )

      # No <img> tag when headshot is nil
      refute html =~ "<img"
    end

    test "renders img tag when headshot_url is present" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(%{headshot_url: "https://example.com/judge.png"}),
          link_target: "/mlb/players/new-york-yankees/aaron-judge"
        )

      assert html =~ ~s(src="https://example.com/judge.png")
      assert html =~ ~s(loading="lazy")
    end
  end

  # ---------------------------------------------------------------------------
  # Status badge rendering
  # ---------------------------------------------------------------------------

  describe "player_card/1 — status badge (injury_badge attr)" do
    test "injury_badge :green renders a green dot" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          injury_badge: :green
        )

      assert html =~ "bg-green-500"
    end

    test "injury_badge :yellow renders a yellow dot" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          injury_badge: :yellow
        )

      assert html =~ "bg-yellow-400"
    end

    test "injury_badge :red renders a red dot" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          injury_badge: :red
        )

      assert html =~ "bg-red-500"
    end

    test "injury_badge :grey renders no colored dot" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          injury_badge: :grey
        )

      refute html =~ "bg-green-500"
      refute html =~ "bg-yellow-400"
      refute html =~ "bg-red-500"
    end

    test "injury_badge nil renders no colored dot" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          injury_badge: nil
        )

      refute html =~ "bg-green-500"
      refute html =~ "bg-yellow-400"
      refute html =~ "bg-red-500"
    end

    test "injury_badge :green has aria-label 'Healthy'" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          injury_badge: :green
        )

      assert html =~ "Healthy"
    end

    test "injury_badge :red has aria-label containing 'Injured'" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          injury_badge: :red
        )

      assert html =~ "Injured"
    end
  end

  # ---------------------------------------------------------------------------
  # position_override and batting_order
  # ---------------------------------------------------------------------------

  describe "player_card/1 — position_override" do
    test "position_override takes precedence over player.position" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(%{position: "RF"}),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          position_override: "DH"
        )

      assert html =~ "DH"
    end
  end

  describe "player_card/1 — batting_order" do
    test "batting_order is rendered when set" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          batting_order: 3
        )

      assert html =~ "3"
    end
  end

  # ---------------------------------------------------------------------------
  # Variant
  # ---------------------------------------------------------------------------

  describe "player_card/1 — :lineup variant" do
    test "variant :lineup renders a green border class" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          variant: :lineup
        )

      assert html =~ "border-green-200"
    end

    test "default variant renders a neutral border (no green border)" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(),
          link_target: "/mlb/players/new-york-yankees/aaron-judge"
        )

      refute html =~ "border-green-200"
    end
  end

  # ---------------------------------------------------------------------------
  # Team override
  # ---------------------------------------------------------------------------

  describe "player_card/1 — team override" do
    test "team override renders the override team name, not player.team.name" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(%{team: %{name: "Wrong Team", slug: "wrong-team"}}),
          link_target: "/mlb/players/new-york-yankees/aaron-judge",
          team: %{name: "Override Team", slug: "override-team"}
        )

      assert html =~ "Override Team"
      refute html =~ "Wrong Team"
    end

    test "no team set renders 'Free Agent'" do
      html =
        render_component(&SportsFanaticWeb.CoreComponents.player_card/1,
          player: build_player(%{team: nil}),
          link_target: "/mlb/players/new-york-yankees/aaron-judge"
        )

      assert html =~ "Free Agent"
    end
  end
end
