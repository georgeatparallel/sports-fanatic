defmodule SportsFanaticWeb.Components.GameCardPanelTest do
  @moduledoc """
  Unit tests for `SportsFanaticWeb.PredictionComponents.game_card_panel/1`
  and the additive behaviour of `today_hit_banner/1`. No Postgres required.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SportsFanaticWeb.PredictionComponents

  defp full_card do
    %{
      scheduled_game_id: 823_549,
      is_home: true,
      opponent_team: %SportsFanatic.Mlb.Team{
        name: "Toronto Blue Jays",
        slug: "toronto-blue-jays"
      },
      opponent_name: "Toronto Blue Jays",
      venue_name: "Yankee Stadium",
      venue_id: 3313,
      game_datetime_utc: ~U[2026-05-18 23:05:00Z],
      local_time_label: "7:05 PM ET",
      probable_pitcher_name: "Patrick Corbin",
      pitcher_record_label: "3.93 ERA",
      weather_oneliner: "81°F"
    }
  end

  describe "game_card_panel/1 — nil" do
    test "renders nothing when card is nil" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: nil)
      refute html =~ "Today's Game"
      refute html =~ "No game today"
    end
  end

  describe "game_card_panel/1 — full card (home game)" do
    test "renders Today's Game header" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ "Today's Game"
    end

    test "renders 'vs' prefix for home games" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ "vs"
    end

    test "renders opponent name" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ "Toronto Blue Jays"
    end

    test "renders local time label" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ "7:05 PM ET"
    end

    test "renders venue name" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ "Yankee Stadium"
    end

    test "renders probable pitcher name" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ "Patrick Corbin"
    end

    test "renders pitcher record label when present" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ "3.93 ERA"
    end

    test "renders weather one-liner when present" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ "81°F"
    end

    test "opponent team link points to /mlb/teams/<slug>" do
      html = render_component(&PredictionComponents.game_card_panel/1, card: full_card())
      assert html =~ ~s(href="/mlb/teams/toronto-blue-jays")
    end
  end

  describe "game_card_panel/1 — away game" do
    test "renders '@' prefix for away games" do
      card = %{full_card() | is_home: false}
      html = render_component(&PredictionComponents.game_card_panel/1, card: card)
      assert html =~ "@"
    end
  end

  describe "game_card_panel/1 — graceful degradation" do
    test "omits pitcher line when probable_pitcher_name is nil" do
      card = %{full_card() | probable_pitcher_name: nil, pitcher_record_label: nil}
      html = render_component(&PredictionComponents.game_card_panel/1, card: card)
      refute html =~ "Patrick Corbin"
    end

    test "omits pitcher record label when nil but keeps pitcher name" do
      card = %{full_card() | pitcher_record_label: nil}
      html = render_component(&PredictionComponents.game_card_panel/1, card: card)
      assert html =~ "Patrick Corbin"
      refute html =~ "3.93 ERA"
    end

    test "omits weather line when weather_oneliner is nil" do
      card = %{full_card() | weather_oneliner: nil}
      html = render_component(&PredictionComponents.game_card_panel/1, card: card)
      refute html =~ "81°F"
    end

    test "renders plain opponent name when opponent_team is nil (no team page link)" do
      card = %{full_card() | opponent_team: nil}
      html = render_component(&PredictionComponents.game_card_panel/1, card: card)
      assert html =~ "Toronto Blue Jays"
      refute html =~ "/mlb/teams/toronto-blue-jays"
    end

    test "omits venue separator when venue_name is nil" do
      card = %{full_card() | venue_name: nil}
      html = render_component(&PredictionComponents.game_card_panel/1, card: card)
      refute html =~ "Yankee Stadium"
    end
  end

  describe "today_hit_banner/1 — nil prediction (regression: no 'No game today' copy)" do
    test "renders nothing when prediction is nil" do
      html = render_component(&PredictionComponents.today_hit_banner/1, prediction: nil)
      refute html =~ "No game today"
      refute html =~ "Today's Hit Prediction"
    end
  end

  describe "today_hit_banner/1 — present prediction" do
    test "renders the banner when prediction is present" do
      prediction = %{
        hit_prob: 0.62,
        player_team: "New York Yankees",
        is_home: true,
        vs_team: "Toronto Blue Jays",
        venue_name: "Yankee Stadium",
        game_datetime: nil,
        probable_pitcher_name: "Patrick Corbin",
        batting_order: 2,
        temperature: nil,
        wind_speed: nil,
        precipitation: nil
      }

      html = render_component(&PredictionComponents.today_hit_banner/1, prediction: prediction)
      assert html =~ "Today's Hit Prediction"
      assert html =~ "Patrick Corbin"
      assert html =~ "2nd"
    end
  end
end
