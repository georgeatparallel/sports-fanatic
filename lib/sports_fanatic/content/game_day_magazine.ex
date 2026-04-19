defmodule SportsFanatic.Content.GameDayMagazine do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "content"

  schema "game_day_magazines" do
    field :game_date, :date
    field :game_id, :integer
    field :slug, :string
    field :headline, :string
    field :subheadline, :string
    field :matchup_analysis, :string
    field :weather_impact, :map
    field :away_lineup, :map
    field :home_lineup, :map
    field :away_pitcher, :map
    field :home_pitcher, :map
    field :batter_matchups, :map
    field :key_storylines, {:array, :string}
    field :historical_data, :map
    field :prediction, :map
    field :status, :string, default: "draft"
    field :model_version, :string
    field :generation_ms, :integer
    field :published_at, :utc_datetime

    belongs_to :away_team, SportsFanatic.Mlb.Team
    belongs_to :home_team, SportsFanatic.Mlb.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(magazine, attrs) do
    magazine
    |> cast(attrs, [
      :game_date, :away_team_id, :home_team_id, :game_id, :slug,
      :headline, :subheadline, :matchup_analysis, :weather_impact,
      :away_lineup, :home_lineup, :away_pitcher, :home_pitcher,
      :batter_matchups, :key_storylines, :historical_data, :prediction,
      :status, :model_version, :generation_ms, :published_at
    ])
    |> validate_required([:game_date, :away_team_id, :home_team_id, :slug, :headline, :matchup_analysis, :away_lineup, :home_lineup, :away_pitcher, :home_pitcher])
    |> unique_constraint([:game_date, :slug])
  end
end
