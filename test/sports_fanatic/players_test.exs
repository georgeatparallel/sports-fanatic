defmodule SportsFanatic.PlayersTest do
  @moduledoc """
  Integration tests for SportsFanatic.Players context.

  Requires PostgreSQL. Run with `mix test`.

  Covers:
  - Three-group ordering (groups_for_date/1)
  - Empty lineup case
  - Active-not-in-lineup never overlaps lineup
  - Inactive group contains only non-"active" players
  """
  use SportsFanatic.DataCase, async: true

  import Ecto.Query

  alias SportsFanatic.Mlb.{Lineup, Player, Team}
  alias SportsFanatic.Players
  alias SportsFanatic.Repo

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp insert_team!(attrs \\ %{}) do
    team_id = Ecto.UUID.generate()

    Repo.insert!(%Team{
      id: team_id,
      name: attrs[:name] || "Test Team #{System.unique_integer()}",
      abbreviation: attrs[:abbreviation] || "TT",
      city: attrs[:city] || "Testville",
      slug: attrs[:slug] || "test-team-#{System.unique_integer([:positive])}",
      division: "NL East",
      league: "NL"
    })
  end

  defp insert_player!(team, attrs \\ %{}) do
    suffix = System.unique_integer([:positive])
    last = attrs[:last_name] || "LastName#{suffix}"
    first = attrs[:first_name] || "First"
    name = attrs[:full_name] || "#{first} #{last}"

    Repo.insert!(%Player{
      id: Ecto.UUID.generate(),
      first_name: first,
      last_name: last,
      full_name: name,
      slug: attrs[:slug] || "#{String.downcase(first)}-#{String.downcase(last)}",
      position: attrs[:position] || "OF",
      status: attrs[:status] || "active",
      team_id: team.id,
      external_ids: attrs[:external_ids] || %{}
    })
  end

  defp insert_lineup!(player, date, attrs \\ %{}) do
    Repo.insert!(%Lineup{
      game_date: date,
      player_nerds_id: System.unique_integer([:positive]),
      team_code: "TST",
      batting_order: attrs[:batting_order] || 1,
      position: attrs[:position] || "CF",
      confirmed: true,
      player_id: player.id
    })
  end

  # ── three-group ordering ─────────────────────────────────────────────────────

  describe "groups_for_date/1 — three-group ordering" do
    setup do
      team = insert_team!()
      date = ~D[2026-05-18]

      # 5 players in lineup — seeded in reverse alpha order intentionally
      lineup_players =
        for last <- ~w(Zebra Apple Mango Bravo Niner) do
          p = insert_player!(team, %{last_name: last})
          insert_lineup!(p, date)
          p
        end

      # 10 active non-lineup players
      active_players =
        for i <- 1..10 do
          insert_player!(team, %{last_name: "Active#{String.pad_leading(to_string(i), 3, "0")}"})
        end

      # 3 inactive players
      inactive_players =
        for i <- 1..3 do
          insert_player!(team, %{last_name: "Inactive#{i}", status: "injured"})
        end

      %{
        date: date,
        team: team,
        lineup_players: lineup_players,
        active_players: active_players,
        inactive_players: inactive_players
      }
    end

    test "groups_for_date returns a map with :lineup, :active_not_in_lineup, :inactive", %{
      date: date
    } do
      result = Players.groups_for_date(date)
      assert Map.has_key?(result, :lineup)
      assert Map.has_key?(result, :active_not_in_lineup)
      assert Map.has_key?(result, :inactive)
    end

    test "lineup group contains exactly the seeded lineup players", %{
      date: date,
      lineup_players: lineup_players
    } do
      %{lineup: lineup} = Players.groups_for_date(date)
      lineup_ids = Enum.map(lineup, & &1.player.id) |> MapSet.new()
      expected_ids = Enum.map(lineup_players, & &1.id) |> MapSet.new()
      assert MapSet.equal?(lineup_ids, expected_ids)
    end

    test "lineup group is sorted by last_name ascending", %{date: date} do
      %{lineup: lineup} = Players.groups_for_date(date)
      last_names = Enum.map(lineup, & &1.player.last_name)
      assert last_names == Enum.sort(last_names)
    end

    test "active_not_in_lineup group does not overlap with lineup", %{date: date} do
      %{lineup: lineup, active_not_in_lineup: active} = Players.groups_for_date(date)
      lineup_ids = Enum.map(lineup, & &1.player.id) |> MapSet.new()
      active_ids = Enum.map(active, & &1.player.id) |> MapSet.new()

      overlap = MapSet.intersection(lineup_ids, active_ids)
      assert MapSet.size(overlap) == 0, "Lineup and active groups must not overlap"
    end

    test "active_not_in_lineup is sorted by last_name ascending", %{date: date} do
      %{active_not_in_lineup: active} = Players.groups_for_date(date)
      last_names = Enum.map(active, & &1.player.last_name)
      assert last_names == Enum.sort(last_names)
    end

    test "inactive group contains only non-active players", %{date: date} do
      %{inactive: inactive} = Players.groups_for_date(date)

      for row <- inactive do
        refute row.player.status == "active",
               "Inactive group must not contain a player with status='active', found: #{inspect(row.player)}"
      end
    end

    test "inactive group is sorted by last_name ascending", %{date: date} do
      %{inactive: inactive} = Players.groups_for_date(date)
      last_names = Enum.map(inactive, & &1.player.last_name)
      assert last_names == Enum.sort(last_names)
    end

    test "active_not_in_lineup count is at least 10 (the seeded non-lineup active players)", %{
      date: date
    } do
      %{active_not_in_lineup: active} = Players.groups_for_date(date)
      assert length(active) >= 10
    end
  end

  # ── empty lineup case ────────────────────────────────────────────────────────

  describe "groups_for_date/1 — empty lineup (no lineup rows for date)" do
    setup do
      team = insert_team!()

      # Active players only — no lineup rows for the date
      active_players =
        for i <- 1..5 do
          insert_player!(team, %{last_name: "ActiveNoLineup#{i}"})
        end

      # Inactive players
      inactive_players =
        for i <- 1..2 do
          insert_player!(team, %{last_name: "InactiveNoLineup#{i}", status: "day-to-day"})
        end

      %{
        date: ~D[2025-01-01],
        team: team,
        active_players: active_players,
        inactive_players: inactive_players
      }
    end

    test "lineup group is empty when no lineup rows exist for the date", %{date: date} do
      %{lineup: lineup} = Players.groups_for_date(date)
      assert lineup == []
    end

    test "active_not_in_lineup is non-empty even when no lineup exists", %{date: date} do
      %{active_not_in_lineup: active} = Players.groups_for_date(date)
      assert length(active) >= 5
    end

    test "inactive group is non-empty", %{date: date} do
      %{inactive: inactive} = Players.groups_for_date(date)
      assert length(inactive) >= 2
    end

    test "no crash occurs — returns a valid groups map", %{date: date} do
      result = Players.groups_for_date(date)
      assert is_map(result)
    end
  end

  # ── groups_with_cards_for_date/1 ────────────────────────────────────────────

  describe "groups_with_cards_for_date/1" do
    setup do
      team = insert_team!()
      date = ~D[2026-05-18]

      player = insert_player!(team, %{last_name: "CardPlayer"})
      insert_lineup!(player, date)

      %{date: date, player: player}
    end

    test "returns a map with :groups and :cards keys", %{date: date} do
      result = Players.groups_with_cards_for_date(date)
      assert Map.has_key?(result, :groups)
      assert Map.has_key?(result, :cards)
    end

    test ":cards is a map keyed by player UUID", %{date: date, player: player} do
      %{cards: cards} = Players.groups_with_cards_for_date(date)
      assert is_map(cards)
      assert Map.has_key?(cards, player.id)
    end

    test "each card entry has :injury_badge, :link_target, :has_scouting_report", %{
      date: date,
      player: player
    } do
      %{cards: cards} = Players.groups_with_cards_for_date(date)
      card = Map.fetch!(cards, player.id)
      assert Map.has_key?(card, :injury_badge)
      assert Map.has_key?(card, :link_target)
      assert Map.has_key?(card, :has_scouting_report)
    end

    test "card injury_badge is one of the valid atoms when no scouting/injury data exists", %{
      date: date,
      player: player
    } do
      %{cards: cards} = Players.groups_with_cards_for_date(date)
      badge = cards[player.id].injury_badge
      assert badge in [:green, :yellow, :red, :grey]
    end

    test "card link_target defaults to player page when no scouting report exists", %{
      date: date,
      player: player
    } do
      %{cards: cards} = Players.groups_with_cards_for_date(date)
      target = cards[player.id].link_target
      assert String.contains?(target, "/mlb/players/")
    end
  end
end
