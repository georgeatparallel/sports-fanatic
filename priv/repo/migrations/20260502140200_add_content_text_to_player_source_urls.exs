defmodule SportsFanatic.Repo.Migrations.AddContentTextToPlayerSourceUrls do
  use Ecto.Migration

  def change do
    alter table(:player_source_urls, prefix: "content") do
      add :content_text, :text
    end
  end
end
