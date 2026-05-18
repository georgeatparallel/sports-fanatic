defmodule SportsFanatic.Repo.Migrations.CreatePipelineRunEvents do
  use Ecto.Migration

  def up do
    create table(:pipeline_run_events, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :pipeline_run_id, :binary_id, null: false
      add :step, :string, size: 64, null: false
      add :kind, :string, size: 16, null: false
      add :seq, :bigint, null: false
      add :payload, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("now()")
    end

    execute(
      """
      ALTER TABLE system.pipeline_run_events
        ADD CONSTRAINT pipeline_run_events_kind_check
        CHECK (kind IN ('started','item','completed','failed'))
      """,
      "ALTER TABLE system.pipeline_run_events DROP CONSTRAINT pipeline_run_events_kind_check"
    )

    create index(:pipeline_run_events, [:pipeline_run_id, :inserted_at], prefix: "system")
    create index(:pipeline_run_events, [:pipeline_run_id, :seq], prefix: "system")
    create index(:pipeline_run_events, [:pipeline_run_id, :step, :kind], prefix: "system")
  end

  def down do
    drop table(:pipeline_run_events, prefix: "system")
  end
end
