defmodule SportsFanatic.Mlb.Pick do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "mlb"

  schema "picks" do
    field :pipeline_run_id, :binary_id
    field :prediction_date, :date
    field :player_id, :binary_id
    field :player_mlb_id, :integer
    field :player_name, :string
    field :player_team, :string
    field :vs_team, :string
    field :probable_pitcher_name, :string
    field :venue_id, :integer
    field :venue_name, :string
    field :prediction, :string
    field :confidence, :float
    field :temperature, :float
    field :wind_speed, :float
    field :wind_direction, :integer
    field :precipitation, :float
    field :weathercode, :integer
    field :surface_pressure, :float
    field :vs_avg, :string
    field :vs_plate_appearances, :integer
    field :vs_home_runs, :integer
    field :vs_season_score, :float
    field :actual_result, :string
    field :actual_hits, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(pick, attrs) do
    pick
    |> cast(attrs, [
      :pipeline_run_id,
      :prediction_date,
      :player_id,
      :player_mlb_id,
      :player_name,
      :player_team,
      :vs_team,
      :probable_pitcher_name,
      :venue_id,
      :venue_name,
      :prediction,
      :confidence,
      :temperature,
      :wind_speed,
      :wind_direction,
      :precipitation,
      :weathercode,
      :surface_pressure,
      :vs_avg,
      :vs_plate_appearances,
      :vs_home_runs,
      :vs_season_score,
      :actual_result,
      :actual_hits
    ])
    |> validate_required([:prediction_date, :player_mlb_id])
    |> unique_constraint([:prediction_date, :player_mlb_id])
  end
end
