defmodule SportsFanatic.Content.ScoutingReport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "content"

  schema "scouting_reports" do
    field :report_date, :date
    field :summary, :string
    field :overall_grade, :string
    field :full_report, :map
    field :hit_probability, :float
    field :hr_probability, :float
    field :strengths, {:array, :string}
    field :weaknesses, {:array, :string}
    field :injury_risk, :string
    field :injury_detail, :string
    field :category_impact, :map
    field :confidence_modifier, :float
    field :sources_count, :integer, default: 0
    field :model_version, :string
    field :generation_ms, :integer

    belongs_to :player, SportsFanatic.Mlb.Player

    timestamps(type: :utc_datetime)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :player_id,
      :report_date,
      :summary,
      :overall_grade,
      :full_report,
      :hit_probability,
      :hr_probability,
      :strengths,
      :weaknesses,
      :injury_risk,
      :injury_detail,
      :category_impact,
      :confidence_modifier,
      :sources_count,
      :model_version,
      :generation_ms
    ])
    |> validate_required([:player_id, :report_date, :summary, :full_report])
    |> unique_constraint([:player_id, :report_date])
  end
end
