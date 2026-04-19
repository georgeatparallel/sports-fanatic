defmodule SportsFanatic.Repo.Migrations.CreateSystemSchema do
  use Ecto.Migration

  def up do
    execute "CREATE SCHEMA IF NOT EXISTS system"

    create table(:pipeline_runs, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :pipeline_name, :string, size: 100, null: false
      add :status, :string, size: 20, null: false, default: "running"
      add :started_at, :utc_datetime, null: false, default: fragment("now()")
      add :completed_at, :utc_datetime
      add :error, :text
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create index(:pipeline_runs, [:pipeline_name, :started_at], prefix: "system")

    create table(:cache_invalidations, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :pattern, :string, size: 500, null: false
      add :reason, :string, size: 200
      add :invalidated_at, :utc_datetime, null: false, default: fragment("now()")
    end
  end

  def down do
    drop table(:cache_invalidations, prefix: "system")
    drop table(:pipeline_runs, prefix: "system")
    execute "DROP SCHEMA IF EXISTS system CASCADE"
  end
end
