defmodule SportsFanatic.Repo.Migrations.AddRunKindToPipelineRuns do
  use Ecto.Migration

  def up do
    alter table(:pipeline_runs, prefix: "system") do
      add :run_kind, :string, size: 24, null: false, default: "daily"
      add :seed_from_date, :date
      add :seed_through_date, :date
      add :current_step, :string, size: 64
      add :checkpoint, :map, default: %{}
    end

    execute(
      """
      ALTER TABLE system.pipeline_runs
        ADD CONSTRAINT pipeline_runs_run_kind_check
        CHECK (run_kind IN ('daily','initial_seed','manual'))
      """,
      "ALTER TABLE system.pipeline_runs DROP CONSTRAINT pipeline_runs_run_kind_check"
    )

    create index(:pipeline_runs, [:run_kind, :status, :started_at], prefix: "system")
  end

  def down do
    drop index(:pipeline_runs, [:run_kind, :status, :started_at], prefix: "system")
    execute "ALTER TABLE system.pipeline_runs DROP CONSTRAINT pipeline_runs_run_kind_check"

    alter table(:pipeline_runs, prefix: "system") do
      remove :checkpoint
      remove :current_step
      remove :seed_through_date
      remove :seed_from_date
      remove :run_kind
    end
  end
end
