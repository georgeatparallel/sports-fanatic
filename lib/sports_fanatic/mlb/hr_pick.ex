defmodule SportsFanatic.Mlb.HrPick do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "mlb"

  schema "hr_picks" do
    field :pipeline_run_id, :binary_id
    field :prediction_date, :date
    field :player_id, :binary_id
    field :player_mlb_id, :integer
    field :player_name, :string
    field :player_team, :string
    field :vs_team, :string
    field :probable_pitcher_name, :string
    field :pitcher_hand, :string
    field :venue_id, :integer
    field :venue_name, :string
    field :hr_probability, :float
    field :confidence_tier, :string
    field :temperature, :float
    field :wind_speed, :float
    field :wind_direction, :integer
    field :wind_score, :float
    field :precipitation, :float
    field :park_hr_factor, :float
    field :player_iso_30d, :float
    field :player_hr_rate_season, :float
    field :player_slg_season, :float
    field :pitcher_hr_per_9, :float
    field :pitcher_era, :float
    field :batting_order, :integer
    field :home_away, :string
    field :day_night, :string
    field :top_factors, :map
    field :narrative, :string
    field :actual_result, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(hr_pick, attrs) do
    hr_pick
    |> cast(attrs, [
      :pipeline_run_id, :prediction_date, :player_id, :player_mlb_id,
      :player_name, :player_team, :vs_team, :probable_pitcher_name,
      :pitcher_hand, :venue_id, :venue_name, :hr_probability, :confidence_tier,
      :temperature, :wind_speed, :wind_direction, :wind_score, :precipitation,
      :park_hr_factor, :player_iso_30d, :player_hr_rate_season, :player_slg_season,
      :pitcher_hr_per_9, :pitcher_era, :batting_order, :home_away, :day_night,
      :top_factors, :narrative, :actual_result
    ])
    |> validate_required([:prediction_date, :player_mlb_id])
    |> unique_constraint([:prediction_date, :player_mlb_id])
  end
end
