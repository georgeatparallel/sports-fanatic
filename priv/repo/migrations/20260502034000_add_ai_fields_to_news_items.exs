defmodule SportsFanatic.Repo.Migrations.AddAiFieldsToNewsItems do
  use Ecto.Migration

  def change do
    alter table(:news_items, prefix: "content") do
      add :sentiment, :string, size: 20
      add :ai_summary, :text
      add :s3_key, :string, size: 500
      add :source_url, :string, size: 1000
      add :author, :string, size: 200
      add :ai_processed, :boolean, default: false, null: false
    end
  end
end
