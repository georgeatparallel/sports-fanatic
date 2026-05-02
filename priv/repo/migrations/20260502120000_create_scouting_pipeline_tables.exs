defmodule SportsFanatic.Repo.Migrations.CreateScoutingPipelineTables do
  use Ecto.Migration

  def change do
    # Pipeline execution tracking
    create table(:scouting_runs, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :status, :string, null: false, default: "pending"
      add :total_players, :integer, null: false, default: 0
      add :processed_players, :integer, null: false, default: 0
      add :config, :map, null: false, default: %{}
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :error, :text

      timestamps(type: :utc_datetime)
    end

    create index(:scouting_runs, [:status], prefix: "system")
    create index(:scouting_runs, [:started_at], prefix: "system")

    # Per-player step logs
    create table(:scouting_run_logs, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :scouting_run_id, references(:scouting_runs, type: :binary_id, prefix: "system"),
        null: false

      add :player_id, references(:players, type: :binary_id, prefix: "public"), null: false
      add :step, :string, null: false
      add :status, :string, null: false
      add :message, :text
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:scouting_run_logs, [:scouting_run_id], prefix: "system")
    create index(:scouting_run_logs, [:player_id], prefix: "system")
    create index(:scouting_run_logs, [:scouting_run_id, :step], prefix: "system")

    # URL deduplication table
    create table(:player_source_urls, prefix: "content", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :player_id, references(:players, type: :binary_id, prefix: "public"), null: false
      add :url, :text, null: false
      add :source_type, :string, null: false
      add :classification, :string
      add :content_summary, :text
      add :key_facts, :map
      add :processed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:player_source_urls, [:player_id, :url], prefix: "content")
    create index(:player_source_urls, [:player_id], prefix: "content")
    create index(:player_source_urls, [:classification], prefix: "content")
  end
end
