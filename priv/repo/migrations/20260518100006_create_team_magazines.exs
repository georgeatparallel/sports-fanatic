defmodule SportsFanatic.Repo.Migrations.CreateTeamMagazines do
  use Ecto.Migration

  def change do
    create table(:team_magazines, prefix: "content", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :team_id,
          references(:teams,
            type: :binary_id,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false

      add :run_date, :date, null: false
      add :state_of_the_team, :text, null: false
      # array of bullet strings
      add :today_at_a_glance, :map, default: fragment("'[]'::jsonb")
      add :game_summary_prose, :text
      add :sources, :map, default: fragment("'[]'::jsonb")
      add :model, :string, size: 50
      add :cost_mills, :integer, default: 0
      add :ai_processed, :boolean, default: true

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:team_magazines, [:team_id, :run_date], prefix: "content")
    create index(:team_magazines, [:run_date], prefix: "content")
  end
end
