defmodule SportsFanatic.Content.PlayerDailyContent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "content"

  schema "player_daily_content" do
    field :content_date, :date
    field :headline, :string
    field :lead_paragraph, :string
    field :tldr, :string
    field :matchup_analysis, :string
    field :opposing_pitcher, :map
    field :park_factors, :map
    field :recent_form, :string
    field :trends, {:array, :map}
    field :projections, :map
    field :faq_items, {:array, :map}
    field :meta_description, :string
    field :keywords, {:array, :string}
    field :json_ld, :map
    field :status, :string, default: "published"
    field :model_version, :string
    field :generation_ms, :integer
    field :source_data, :map

    belongs_to :player, SportsFanatic.Mlb.Player
    belongs_to :team, SportsFanatic.Mlb.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(content, attrs) do
    content
    |> cast(attrs, [
      :player_id,
      :team_id,
      :content_date,
      :headline,
      :lead_paragraph,
      :tldr,
      :matchup_analysis,
      :opposing_pitcher,
      :park_factors,
      :recent_form,
      :trends,
      :projections,
      :faq_items,
      :meta_description,
      :keywords,
      :json_ld,
      :status,
      :model_version,
      :generation_ms,
      :source_data
    ])
    |> validate_required([
      :player_id,
      :team_id,
      :content_date,
      :headline,
      :lead_paragraph,
      :tldr,
      :faq_items,
      :meta_description,
      :keywords,
      :json_ld
    ])
    |> validate_length(:meta_description, max: 160)
    |> unique_constraint([:player_id, :content_date])
  end
end
