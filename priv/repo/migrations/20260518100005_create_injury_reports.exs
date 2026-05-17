defmodule SportsFanatic.Repo.Migrations.CreateInjuryReports do
  use Ecto.Migration

  def change do
    create table(:injury_reports, prefix: "content", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :player_id,
          references(:players,
            type: :binary_id,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :run_date, :date, null: false
      add :tldr, :text, null: false
      add :current_status, :string, size: 30, null: false
      # array of {date, event, source_url}
      add :timeline, :map, default: fragment("'[]'::jsonb")
      add :expected_return, :text
      add :fantasy_impact, :text
      # array of {title, url, domain, published_at}
      add :sources, :map, default: fragment("'[]'::jsonb")
      add :model, :string, size: 50
      add :cost_mills, :integer, default: 0
      add :ai_processed, :boolean, default: true

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:injury_reports, [:player_id, :run_date], prefix: "content")
    create index(:injury_reports, [:run_date], prefix: "content")

    execute(
      """
      ALTER TABLE content.injury_reports
      ADD CONSTRAINT injury_reports_status_check
      CHECK (current_status IN (
        'active','day-to-day','injured-list-10','injured-list-15',
        'injured-list-60','recovering','cleared','unknown'
      ))
      """,
      "ALTER TABLE content.injury_reports DROP CONSTRAINT IF EXISTS injury_reports_status_check"
    )
  end
end
