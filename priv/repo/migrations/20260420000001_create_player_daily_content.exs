defmodule SportsFanatic.Repo.Migrations.CreatePlayerDailyContent do
  use Ecto.Migration

  def change do
    create table(:player_daily_content, prefix: "content", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :player_id, references(:players, type: :binary_id, prefix: "public"), null: false
      add :team_id, references(:teams, type: :binary_id, prefix: "public"), null: false
      add :content_date, :date, null: false
      add :headline, :text, null: false
      add :lead_paragraph, :text, null: false
      add :tldr, :text, null: false
      add :matchup_analysis, :text
      add :opposing_pitcher, :map
      add :park_factors, :map
      add :recent_form, :text
      add :trends, {:array, :map}
      add :projections, :map
      add :faq_items, {:array, :map}, null: false, default: fragment("ARRAY[]::jsonb[]")
      add :meta_description, :string, size: 160, null: false
      add :keywords, {:array, :string}, null: false, default: fragment("'{}'::text[]")
      add :json_ld, :map, null: false
      add :status, :string, size: 20, null: false, default: "published"
      add :model_version, :string, size: 50
      add :generation_ms, :integer
      add :source_data, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:player_daily_content, [:player_id, :content_date], prefix: "content")
    create index(:player_daily_content, [:content_date], prefix: "content")
    create index(:player_daily_content, [:team_id, :content_date], prefix: "content")
  end
end
