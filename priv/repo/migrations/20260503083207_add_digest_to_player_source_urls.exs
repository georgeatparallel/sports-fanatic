defmodule SportsFanatic.Repo.Migrations.AddDigestToPlayerSourceUrls do
  use Ecto.Migration

  def change do
    alter table(:player_source_urls, prefix: "content") do
      add :digest, :text
    end
  end
end
