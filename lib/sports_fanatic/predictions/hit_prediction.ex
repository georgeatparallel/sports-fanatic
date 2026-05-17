defmodule SportsFanatic.Predictions.HitPrediction do
  @moduledoc """
  Ecto schema for `mlb.hit_predictions`.

  One row per (prediction_date, player_mlb_id).
  Inserted by `SportsFanatic.Workers.PredictHitsWorker`, read by
  `SportsFanatic.Predictions` context.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "mlb"
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @predictions ["Hit", "No Hit"]
  @confidence_tiers ~w(S A B C D)

  schema "hit_predictions" do
    field :pipeline_run_id, :binary_id
    field :prediction_date, :date
    field :player_id, :binary_id
    field :player_mlb_id, :integer
    field :player_name, :string
    field :player_team, :string
    field :player_team_id, :integer
    field :vs_team, :string
    field :vs_team_id, :integer
    field :game_id, :integer
    field :game_datetime, :utc_datetime
    field :is_home, :boolean
    field :batting_order, :integer
    field :probable_pitcher_name, :string
    field :probable_pitcher_mlb_id, :integer
    field :venue_id, :integer
    field :venue_name, :string
    field :hit_prob, :float
    field :prediction, :string
    field :confidence_tier, :string
    field :temperature, :float
    field :wind_speed, :float
    field :wind_direction, :integer
    field :precipitation, :float
    field :weathercode, :integer
    field :surface_pressure, :float
    field :bvp_avg, :float
    field :bvp_at_bats, :integer
    field :bvp_home_runs, :integer
    field :features, :map, default: %{}
    field :model_version, :string
    field :actual_result, :string
    field :actual_hits, :integer

    timestamps(type: :utc_datetime)
  end

  @castable ~w(
    pipeline_run_id prediction_date player_id player_mlb_id player_name
    player_team player_team_id vs_team vs_team_id game_id game_datetime
    is_home batting_order probable_pitcher_name probable_pitcher_mlb_id
    venue_id venue_name hit_prob prediction confidence_tier
    temperature wind_speed wind_direction precipitation weathercode
    surface_pressure bvp_avg bvp_at_bats bvp_home_runs features
    model_version actual_result actual_hits
  )a

  def changeset(prediction, attrs) do
    prediction
    |> cast(attrs, @castable)
    |> validate_required([:prediction_date, :player_mlb_id, :hit_prob, :prediction])
    |> validate_number(:hit_prob, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_inclusion(:prediction, @predictions)
    |> validate_inclusion(:confidence_tier, @confidence_tiers ++ [nil])
    |> unique_constraint([:prediction_date, :player_mlb_id],
      name: :hit_predictions_date_player_idx
    )
  end

  @doc """
  Derives a confidence tier label from a probability for display only.
  Higher tiers = more extreme predictions (close to 0 or 1).
  """
  @spec tier_for_prob(float) :: String.t()
  def tier_for_prob(p) when is_float(p) do
    distance = abs(p - 0.5)

    cond do
      distance >= 0.35 -> "S"
      distance >= 0.25 -> "A"
      distance >= 0.15 -> "B"
      distance >= 0.05 -> "C"
      true -> "D"
    end
  end

  def tier_for_prob(_), do: nil
end
