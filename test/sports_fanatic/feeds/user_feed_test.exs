defmodule SportsFanatic.Feeds.UserFeedTest do
  use ExUnit.Case, async: true

  alias SportsFanatic.Feeds.UserFeed

  @tag :unit

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        name: "My Fantasy Team",
        user_id: Ecto.UUID.generate(),
        player_ids: [Ecto.UUID.generate()],
        team_ids: []
      }

      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      assert changeset.valid?
    end

    test "invalid without name" do
      attrs = %{user_id: Ecto.UUID.generate()}
      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :name)
    end

    test "invalid without user_id" do
      attrs = %{name: "My Team"}
      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :user_id)
    end

    test "invalid with name over 100 characters" do
      attrs = %{
        name: String.duplicate("a", 101),
        user_id: Ecto.UUID.generate()
      }

      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      refute changeset.valid?
    end

    test "invalid with empty name" do
      attrs = %{
        name: "",
        user_id: Ecto.UUID.generate()
      }

      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      refute changeset.valid?
    end

    test "rejects more than 50 players" do
      player_ids = for _ <- 1..51, do: Ecto.UUID.generate()

      attrs = %{
        name: "Too Many Players",
        user_id: Ecto.UUID.generate(),
        player_ids: player_ids
      }

      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      refute changeset.valid?
      assert "cannot exceed 50 players" in errors_on(changeset, :player_ids)
    end

    test "rejects more than 30 teams" do
      team_ids = for _ <- 1..31, do: Ecto.UUID.generate()

      attrs = %{
        name: "Too Many Teams",
        user_id: Ecto.UUID.generate(),
        team_ids: team_ids
      }

      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      refute changeset.valid?
      assert "cannot exceed 30 teams" in errors_on(changeset, :team_ids)
    end

    test "allows exactly 50 players" do
      player_ids = for _ <- 1..50, do: Ecto.UUID.generate()

      attrs = %{
        name: "Max Players",
        user_id: Ecto.UUID.generate(),
        player_ids: player_ids
      }

      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      assert changeset.valid?
    end

    test "default values are applied" do
      attrs = %{name: "Test", user_id: Ecto.UUID.generate()}
      changeset = UserFeed.changeset(%UserFeed{}, attrs)
      assert Ecto.Changeset.get_field(changeset, :display_order) == 0
      assert Ecto.Changeset.get_field(changeset, :is_active) == true
      assert Ecto.Changeset.get_field(changeset, :player_ids) == []
      assert Ecto.Changeset.get_field(changeset, :team_ids) == []
    end
  end

  defp errors_on(changeset, field) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Map.get(field, [])
  end
end
