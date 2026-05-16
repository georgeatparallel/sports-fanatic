defmodule SportsFanatic.Feeds.UserFeed do
  @moduledoc """
  Schema for user-created news feeds. Each feed contains arrays of player
  and team UUIDs that are used to filter the news feed via PostgreSQL
  array overlap (`&&`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "accounts"

  @max_players 50
  @max_teams 30

  schema "user_feeds" do
    field :name, :string
    field :player_ids, {:array, :binary_id}, default: []
    field :team_ids, {:array, :binary_id}, default: []
    field :display_order, :integer, default: 0
    field :is_active, :boolean, default: true
    field :last_researched_at, :utc_datetime

    belongs_to :user, SportsFanatic.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [
      :name,
      :player_ids,
      :team_ids,
      :display_order,
      :is_active,
      :last_researched_at,
      :user_id
    ])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_player_count()
    |> validate_team_count()
    |> unique_constraint([:user_id, :name], message: "you already have a feed with this name")
    |> foreign_key_constraint(:user_id)
  end

  defp validate_player_count(changeset) do
    validate_change(changeset, :player_ids, fn :player_ids, ids ->
      if length(ids) > @max_players do
        [player_ids: "cannot exceed #{@max_players} players"]
      else
        []
      end
    end)
  end

  defp validate_team_count(changeset) do
    validate_change(changeset, :team_ids, fn :team_ids, ids ->
      if length(ids) > @max_teams do
        [team_ids: "cannot exceed #{@max_teams} teams"]
      else
        []
      end
    end)
  end
end
