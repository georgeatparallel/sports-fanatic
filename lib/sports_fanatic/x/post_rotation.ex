defmodule SportsFanatic.X.PostRotation do
  @moduledoc """
  Ecto schema for `system.x_post_rotation` — one row per `run_date` capturing
  the day's post plan (order + scheduled times + rotation team).

  The DB column is `post_order` (not `order`) because `order` is a reserved
  SQL keyword.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"
  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "x_post_rotation" do
    field :run_date, :date
    field :post_order, {:array, :string}
    field :scheduled_times, :map
    field :selected_team_slug, :string
    field :skipped_slots, {:array, :string}, default: []
    field :earliest_game_at, :utc_datetime

    timestamps()
  end

  @cast_fields [
    :run_date,
    :post_order,
    :scheduled_times,
    :selected_team_slug,
    :skipped_slots,
    :earliest_game_at
  ]

  def changeset(rotation, attrs) do
    rotation
    |> cast(attrs, @cast_fields)
    |> validate_required([:run_date, :post_order, :scheduled_times])
    |> validate_length(:selected_team_slug, max: 100)
    |> unique_constraint(:run_date)
  end
end
