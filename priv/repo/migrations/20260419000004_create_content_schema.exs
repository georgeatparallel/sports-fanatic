defmodule SportsFanatic.Repo.Migrations.CreateContentSchema do
  use Ecto.Migration

  def up do
    execute "CREATE SCHEMA IF NOT EXISTS content"

    create table(:scouting_reports, prefix: "content", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :player_id, references(:players, type: :binary_id, prefix: "public"), null: false
      add :report_date, :date, null: false
      add :summary, :text, null: false
      add :overall_grade, :string, size: 5
      add :full_report, :map, null: false
      add :hit_probability, :float
      add :hr_probability, :float
      add :strengths, {:array, :string}
      add :weaknesses, {:array, :string}
      add :injury_risk, :string, size: 20
      add :injury_detail, :text
      add :category_impact, :map
      add :confidence_modifier, :float
      add :sources_count, :integer, default: 0
      add :model_version, :string, size: 50
      add :generation_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:scouting_reports, [:player_id, :report_date], prefix: "content")
    create index(:scouting_reports, [:player_id, :report_date], prefix: "content", name: :idx_scouting_player_date)

    create table(:game_day_magazines, prefix: "content", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :game_date, :date, null: false
      add :away_team_id, references(:teams, type: :binary_id, prefix: "public"), null: false
      add :home_team_id, references(:teams, type: :binary_id, prefix: "public"), null: false
      add :game_id, :integer
      add :slug, :string, size: 200, null: false
      add :headline, :text, null: false
      add :subheadline, :text
      add :matchup_analysis, :text, null: false
      add :weather_impact, :map
      add :away_lineup, :map, null: false
      add :home_lineup, :map, null: false
      add :away_pitcher, :map, null: false
      add :home_pitcher, :map, null: false
      add :batter_matchups, :map
      add :key_storylines, {:array, :string}
      add :historical_data, :map
      add :prediction, :map
      add :status, :string, size: 20, null: false, default: "draft"
      add :model_version, :string, size: 50
      add :generation_ms, :integer
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_day_magazines, [:game_date, :slug], prefix: "content")
    create index(:game_day_magazines, [:game_date], prefix: "content")

    create table(:news_items, prefix: "content", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :source, :string, size: 50, null: false
      add :external_id, :string, size: 100
      add :slug, :string, size: 300, null: false
      add :title, :text, null: false
      add :body, :text, null: false
      add :summary, :text
      add :published_date, :date, null: false
      add :published_at, :utc_datetime
      add :player_ids, {:array, :binary_id}
      add :team_ids, {:array, :binary_id}
      add :category, :string, size: 50
      add :is_premium, :boolean, default: false
      add :image_url, :string, size: 500

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:news_items, [:source, :external_id], prefix: "content")
    create index(:news_items, [:published_date], prefix: "content")
    create index(:news_items, [:published_date, :slug], prefix: "content")

    create table(:sitemaps, prefix: "content", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :sitemap_type, :string, size: 50, null: false
      add :xml_content, :text, null: false
      add :page_count, :integer, null: false, default: 0
      add :generated_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create unique_index(:sitemaps, [:sitemap_type], prefix: "content")
  end

  def down do
    drop table(:sitemaps, prefix: "content")
    drop table(:news_items, prefix: "content")
    drop table(:game_day_magazines, prefix: "content")
    drop table(:scouting_reports, prefix: "content")
    execute "DROP SCHEMA IF EXISTS content CASCADE"
  end
end
