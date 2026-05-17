defmodule SportsFanatic.Content.InjuryReport do
  @moduledoc """
  Ecto schema for `content.injury_reports` — one row per (player, run_date).
  Populated by `SportsFanatic.X.InjuryReport.generate_or_fetch/1` via the
  Python Bridge `/injury-report/generate` endpoint.

  All free-text fields stored here have been passed through
  `HtmlSanitizeEx.strip_tags/1` before INSERT (templates use `<%= ... %>`
  only, never `raw/1`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "content"

  @valid_statuses ~w(
    active day-to-day injured-list-10 injured-list-15 injured-list-60
    recovering cleared unknown
  )

  schema "injury_reports" do
    field :player_id, :binary_id
    field :run_date, :date
    field :tldr, :string
    field :current_status, :string
    field :timeline, {:array, :map}, default: []
    field :expected_return, :string
    field :fantasy_impact, :string
    field :sources, {:array, :map}, default: []
    field :model, :string
    field :cost_mills, :integer, default: 0
    field :ai_processed, :boolean, default: true

    field :inserted_at, :utc_datetime
  end

  @cast_fields [
    :player_id,
    :run_date,
    :tldr,
    :current_status,
    :timeline,
    :expected_return,
    :fantasy_impact,
    :sources,
    :model,
    :cost_mills,
    :ai_processed
  ]

  @required_fields [:player_id, :run_date, :tldr, :current_status]

  def changeset(report, attrs) do
    report
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:current_status, @valid_statuses)
    |> validate_length(:current_status, max: 30)
    |> unique_constraint([:player_id, :run_date])
  end

  def valid_statuses, do: @valid_statuses
end
