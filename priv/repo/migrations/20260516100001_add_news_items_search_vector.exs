defmodule SportsFanatic.Repo.Migrations.AddNewsItemsSearchVector do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE content.news_items ADD COLUMN search_vector tsvector
      GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(ai_summary, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(body, '')), 'C')
      ) STORED
    """

    execute "CREATE INDEX idx_news_items_search ON content.news_items USING GIN (search_vector)"

    execute """
    CREATE UNIQUE INDEX idx_news_items_exa_url
      ON content.news_items(source_url)
      WHERE source = 'exa' AND source_url IS NOT NULL
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS content.idx_news_items_exa_url"
    execute "DROP INDEX IF EXISTS content.idx_news_items_search"
    execute "ALTER TABLE content.news_items DROP COLUMN IF EXISTS search_vector"
  end
end
