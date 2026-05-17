defmodule SportsFanatic.Content.TeamMagazine do
  @moduledoc """
  Ecto schema for `content.team_magazines` — one row per (team, run_date).
  Populated by `SportsFanatic.X.TeamMagazine.generate_or_fetch/1`.

  Free-text fields are HTML-sanitized at the storage boundary; templates use
  `<%= ... %>` only.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "content"

  schema "team_magazines" do
    field :team_id, :binary_id
    field :run_date, :date
    field :state_of_the_team, :string
    field :today_at_a_glance, {:array, :string}, default: []
    field :game_summary_prose, :string
    field :sources, {:array, :map}, default: []
    field :model, :string
    field :cost_mills, :integer, default: 0
    field :ai_processed, :boolean, default: true

    field :inserted_at, :utc_datetime
  end

  @cast_fields [
    :team_id,
    :run_date,
    :state_of_the_team,
    :today_at_a_glance,
    :game_summary_prose,
    :sources,
    :model,
    :cost_mills,
    :ai_processed
  ]

  @required_fields [:team_id, :run_date, :state_of_the_team]

  def changeset(magazine, attrs) do
    magazine
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:team_id, :run_date])
  end
end
