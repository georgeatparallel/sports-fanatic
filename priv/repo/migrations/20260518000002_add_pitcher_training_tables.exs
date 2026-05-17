defmodule SportsFanatic.Repo.Migrations.AddPitcherTrainingTables do
  use Ecto.Migration

  def up do
    # pitcher_game_logs (new)
    execute """
    CREATE TABLE IF NOT EXISTS mlb.pitcher_game_logs (
      id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      pitcher_mlb_id INTEGER NOT NULL,
      game_id       INTEGER NOT NULL,
      game_date     DATE,
      innings_pitched DOUBLE PRECISION,
      hits_allowed  INTEGER,
      hr_allowed    INTEGER,
      bb_allowed    INTEGER,
      strikeouts    INTEGER,
      earned_runs   INTEGER,
      pitches_thrown INTEGER,
      inserted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute """
    CREATE UNIQUE INDEX IF NOT EXISTS pitcher_game_logs_pitcher_game_idx
      ON mlb.pitcher_game_logs (pitcher_mlb_id, game_id)
    """

    execute """
    CREATE INDEX IF NOT EXISTS pitcher_game_logs_pitcher_date_idx
      ON mlb.pitcher_game_logs (pitcher_mlb_id, game_date)
    """

    # player_statcast (new)
    execute """
    CREATE TABLE IF NOT EXISTS mlb.player_statcast (
      id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      player_mlb_id      INTEGER NOT NULL,
      season             INTEGER NOT NULL,
      avg_exit_velocity  DOUBLE PRECISION,
      max_exit_velocity  DOUBLE PRECISION,
      barrel_pct         DOUBLE PRECISION,
      hard_hit_pct       DOUBLE PRECISION,
      avg_launch_angle   DOUBLE PRECISION,
      fb_pct             DOUBLE PRECISION,
      pulled_at          TIMESTAMPTZ,
      inserted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """

    execute """
    CREATE UNIQUE INDEX IF NOT EXISTS player_statcast_player_season_idx
      ON mlb.player_statcast (player_mlb_id, season)
    """

    # Missing columns on mlb.pitcher_stats (idempotent ADDs)
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS games_started INTEGER"
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS hits_allowed INTEGER"
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS hr_allowed INTEGER"
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS bb_allowed INTEGER"
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS strikeouts INTEGER"
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS h_per_9 DOUBLE PRECISION"
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS ops_against DOUBLE PRECISION"
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS last_updated TIMESTAMPTZ"
    execute "ALTER TABLE mlb.pitcher_stats ADD COLUMN IF NOT EXISTS pitcher_mlb_id INTEGER"

    # Index for fast freshness lookup
    execute """
    CREATE INDEX IF NOT EXISTS pitcher_stats_mlb_id_season_idx
      ON mlb.pitcher_stats (pitcher_mlb_id, season)
    """

    # mlb.park_hr_factors.hit_factor (new column for hit-park-factor lookups)
    execute "ALTER TABLE mlb.park_hr_factors ADD COLUMN IF NOT EXISTS hit_factor DOUBLE PRECISION"

    # mlb.player_boxscores.is_home is already present in existing migration; no-op.
    # mlb.games.away_starter_mlb_id and .home_starter_mlb_id already exist; no-op.
  end

  def down do
    execute "ALTER TABLE mlb.park_hr_factors DROP COLUMN IF EXISTS hit_factor"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS pitcher_mlb_id"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS last_updated"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS ops_against"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS h_per_9"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS strikeouts"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS bb_allowed"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS hr_allowed"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS hits_allowed"
    execute "ALTER TABLE mlb.pitcher_stats DROP COLUMN IF EXISTS games_started"
    execute "DROP TABLE IF EXISTS mlb.player_statcast"
    execute "DROP TABLE IF EXISTS mlb.pitcher_game_logs"
  end
end
