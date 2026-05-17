defmodule SportsFanatic.Repo.Migrations.CreateHitPredictionsTable do
  use Ecto.Migration

  def up do
    create table(:hit_predictions, prefix: "mlb", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :pipeline_run_id, :binary_id
      add :prediction_date, :date, null: false
      add :player_id, :binary_id
      add :player_mlb_id, :integer, null: false
      add :player_name, :string, size: 200
      add :player_team, :string, size: 100
      add :player_team_id, :integer
      add :vs_team, :string, size: 100
      add :vs_team_id, :integer
      add :game_id, :integer
      add :game_datetime, :utc_datetime
      add :is_home, :boolean
      add :batting_order, :integer
      add :probable_pitcher_name, :string, size: 100
      add :probable_pitcher_mlb_id, :integer
      add :venue_id, :integer
      add :venue_name, :string, size: 200
      add :hit_prob, :float, null: false
      add :prediction, :string, size: 10, null: false
      add :confidence_tier, :string, size: 5
      add :temperature, :float
      add :wind_speed, :float
      add :wind_direction, :integer
      add :precipitation, :float
      add :weathercode, :integer
      add :surface_pressure, :float
      add :bvp_avg, :float
      add :bvp_at_bats, :integer
      add :bvp_home_runs, :integer
      add :features, :map, default: %{}
      add :model_version, :string, size: 40
      add :actual_result, :string, size: 10
      add :actual_hits, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:hit_predictions, [:prediction_date, :player_mlb_id],
             prefix: "mlb",
             name: :hit_predictions_date_player_idx
           )

    # Direction-aware index: sort by prob desc within a date
    execute """
    CREATE INDEX IF NOT EXISTS hit_predictions_date_prob_idx
      ON mlb.hit_predictions (prediction_date, hit_prob DESC)
    """

    create index(:hit_predictions, [:player_mlb_id],
             prefix: "mlb",
             name: :hit_predictions_player_idx
           )

    create index(:hit_predictions, [:pipeline_run_id],
             prefix: "mlb",
             name: :hit_predictions_run_idx
           )

    # Small key/value config table for admin overrides (cron, concurrency, flag)
    execute """
    CREATE SCHEMA IF NOT EXISTS system
    """

    create_if_not_exists table(:predictions_config, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :key, :string, null: false
      add :value, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:predictions_config, [:key], prefix: "system")
  end

  def down do
    drop_if_exists table(:predictions_config, prefix: "system")
    execute "DROP INDEX IF EXISTS mlb.hit_predictions_date_prob_idx"
    drop table(:hit_predictions, prefix: "mlb")
  end
end
