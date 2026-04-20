defmodule SportsFanatic.Repo.Migrations.CreateMlbSchema do
  use Ecto.Migration

  def up do
    execute "CREATE SCHEMA IF NOT EXISTS mlb"

    create table(:games, prefix: "mlb") do
      add :game_id, :integer, null: false
      add :game_datetime, :utc_datetime
      add :game_date, :date
      add :status, :string, size: 20
      add :away_mlb_id, :integer
      add :home_mlb_id, :integer
      add :away_name, :string, size: 100
      add :home_name, :string, size: 100
      add :away_score, :integer
      add :home_score, :integer
      add :away_starter_mlb_id, :integer
      add :home_starter_mlb_id, :integer
      add :venue_id, :integer
      add :venue_name, :string, size: 200

      timestamps(type: :utc_datetime)
    end

    create unique_index(:games, [:game_id], prefix: "mlb")
    create index(:games, [:game_date], prefix: "mlb")

    create table(:scheduled_games, prefix: "mlb") do
      add :game_id, :integer, null: false
      add :game_date, :date, null: false
      add :game_datetime, :utc_datetime
      add :away_mlb_id, :integer
      add :home_mlb_id, :integer
      add :away_name, :string, size: 100
      add :home_name, :string, size: 100
      add :away_probable_pitcher, :string, size: 100
      add :home_probable_pitcher, :string, size: 100
      add :venue_id, :integer
      add :venue_name, :string, size: 200
      add :status, :string, size: 20, default: "scheduled"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:scheduled_games, [:game_id], prefix: "mlb")
    create index(:scheduled_games, [:game_date], prefix: "mlb")

    create table(:player_boxscores, prefix: "mlb") do
      add :game_id, :integer, null: false
      add :player_mlb_id, :integer, null: false
      add :team_mlb_id, :integer
      add :batting_order, :integer
      add :is_home, :boolean
      add :ab, :integer, default: 0
      add :h, :integer, default: 0
      add :hr, :integer, default: 0
      add :doubles, :integer, default: 0
      add :triples, :integer, default: 0
      add :rbi, :integer, default: 0
      add :r, :integer, default: 0
      add :bb, :integer, default: 0
      add :k, :integer, default: 0
      add :sb, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:player_boxscores, [:game_id, :player_mlb_id], prefix: "mlb")
    create index(:player_boxscores, [:player_mlb_id], prefix: "mlb")

    create table(:lineups, prefix: "mlb") do
      add :game_date, :date, null: false
      add :player_nerds_id, :integer, null: false
      add :team_code, :string, size: 10
      add :batting_order, :integer
      add :position, :string, size: 10
      add :confirmed, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lineups, [:game_date, :player_nerds_id], prefix: "mlb")
    create index(:lineups, [:game_date], prefix: "mlb")

    create table(:game_weather, prefix: "mlb") do
      add :game_id, :integer, null: false
      add :temperature_2m, :float
      add :wind_speed_10m, :float
      add :wind_direction_10m, :integer
      add :precipitation, :float
      add :weathercode, :integer
      add :surface_pressure, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_weather, [:game_id], prefix: "mlb")

    create table(:game_weather_forecast, prefix: "mlb") do
      add :venue_id, :integer, null: false
      add :game_datetime, :utc_datetime, null: false
      add :temperature_2m, :float
      add :wind_speed_10m, :float
      add :wind_direction_10m, :integer
      add :precipitation, :float
      add :weathercode, :integer
      add :surface_pressure, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_weather_forecast, [:venue_id, :game_datetime], prefix: "mlb")

    create table(:picks, prefix: "mlb", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :pipeline_run_id, :binary_id
      add :prediction_date, :date, null: false
      add :player_id, :binary_id
      add :player_mlb_id, :integer, null: false
      add :player_name, :string, size: 200
      add :player_team, :string, size: 100
      add :vs_team, :string, size: 100
      add :probable_pitcher_name, :string, size: 100
      add :venue_id, :integer
      add :venue_name, :string, size: 200
      add :prediction, :string, size: 20
      add :confidence, :float
      add :temperature, :float
      add :wind_speed, :float
      add :wind_direction, :integer
      add :precipitation, :float
      add :weathercode, :integer
      add :surface_pressure, :float
      add :vs_avg, :string, size: 10
      add :vs_plate_appearances, :integer
      add :vs_home_runs, :integer
      add :vs_season_score, :float
      add :actual_result, :string, size: 20
      add :actual_hits, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:picks, [:prediction_date, :player_mlb_id], prefix: "mlb")
    create index(:picks, [:prediction_date], prefix: "mlb")

    create table(:hr_picks, prefix: "mlb", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :pipeline_run_id, :binary_id
      add :prediction_date, :date, null: false
      add :player_id, :binary_id
      add :player_mlb_id, :integer, null: false
      add :player_name, :string, size: 200
      add :player_team, :string, size: 100
      add :vs_team, :string, size: 100
      add :probable_pitcher_name, :string, size: 100
      add :pitcher_hand, :string, size: 5
      add :venue_id, :integer
      add :venue_name, :string, size: 200
      add :hr_probability, :float
      add :confidence_tier, :string, size: 5
      add :temperature, :float
      add :wind_speed, :float
      add :wind_direction, :integer
      add :wind_score, :float
      add :precipitation, :float
      add :park_hr_factor, :float
      add :player_iso_30d, :float
      add :player_hr_rate_season, :float
      add :player_slg_season, :float
      add :pitcher_hr_per_9, :float
      add :pitcher_era, :float
      add :batting_order, :integer
      add :home_away, :string, size: 10
      add :day_night, :string, size: 10
      add :top_factors, :map
      add :narrative, :text
      add :actual_result, :string, size: 20

      timestamps(type: :utc_datetime)
    end

    create unique_index(:hr_picks, [:prediction_date, :player_mlb_id], prefix: "mlb")
    create index(:hr_picks, [:prediction_date], prefix: "mlb")

    create table(:pitcher_stats, prefix: "mlb") do
      add :player_id, references(:players, type: :binary_id, prefix: "public")
      add :season, :integer, null: false
      add :batting_avg_against, :float
      add :k_per_9, :float
      add :whip, :float
      add :bb_per_9, :float
      add :hr_per_9, :float
      add :era, :float
      add :games_played, :integer
      add :innings_pitched, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:pitcher_stats, [:player_id, :season], prefix: "mlb")

    create table(:player_season_stats, prefix: "mlb") do
      add :player_mlb_id, :integer, null: false
      add :season, :integer, null: false
      add :stat_group, :string, size: 20, null: false
      add :games_played, :integer
      add :at_bats, :integer
      add :hits, :integer
      add :home_runs, :integer
      add :rbi, :integer
      add :runs, :integer
      add :stolen_bases, :integer
      add :avg, :float
      add :obp, :float
      add :slg, :float
      add :ops, :float
      add :pulled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:player_season_stats, [:player_mlb_id, :season], prefix: "mlb")

    create table(:batter_vs_pitcher, prefix: "mlb") do
      add :batter_id, references(:players, type: :binary_id, prefix: "public")
      add :pitcher_id, references(:players, type: :binary_id, prefix: "public")
      add :season, :integer, null: false
      add :at_bats, :integer
      add :hits, :integer
      add :home_runs, :integer
      add :batting_avg, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:batter_vs_pitcher, [:batter_id, :pitcher_id, :season], prefix: "mlb")

    create table(:park_hr_factors, prefix: "mlb") do
      add :venue_id, :integer, null: false
      add :season, :integer, null: false
      add :hr_factor, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:park_hr_factors, [:venue_id, :season], prefix: "mlb")
  end

  def down do
    drop table(:park_hr_factors, prefix: "mlb")
    drop table(:batter_vs_pitcher, prefix: "mlb")
    drop table(:player_season_stats, prefix: "mlb")
    drop table(:pitcher_stats, prefix: "mlb")
    drop table(:hr_picks, prefix: "mlb")
    drop table(:picks, prefix: "mlb")
    drop table(:game_weather_forecast, prefix: "mlb")
    drop table(:game_weather, prefix: "mlb")
    drop table(:lineups, prefix: "mlb")
    drop table(:player_boxscores, prefix: "mlb")
    drop table(:scheduled_games, prefix: "mlb")
    drop table(:games, prefix: "mlb")
    execute "DROP SCHEMA IF EXISTS mlb CASCADE"
  end
end
