defmodule SportsFanatic.Repo.Migrations.CreateXPosts do
  use Ecto.Migration

  def change do
    create table(:x_posts, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      # top_hits | injury | team_magazine | scorecard | reply
      add :post_type, :string, size: 30, null: false
      add :status, :string, size: 20, null: false, default: "pending"
      add :main_body, :text, null: false, default: ""
      # nullable for non-link-bearing posts
      add :reply_body, :text
      add :link_url, :string, size: 500
      add :main_tweet_id, :string, size: 50
      add :reply_tweet_id, :string, size: 50
      # for inbound/outbound replies
      add :in_reply_to_tweet_id, :string, size: 50
      add :scheduled_at, :utc_datetime, null: false
      add :posted_at, :utc_datetime
      add :engagement_metrics, :map, default: fragment("'{}'::jsonb")
      # mills = tenths of a cent
      add :cost_mills, :integer, default: 0
      # source data used to compose
      add :context, :map, default: fragment("'{}'::jsonb")
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:x_posts, [:status, :scheduled_at], prefix: "system")
    create index(:x_posts, [:posted_at], prefix: "system")
    create index(:x_posts, [:post_type, :scheduled_at], prefix: "system")
    create index(:x_posts, [:in_reply_to_tweet_id], prefix: "system")

    execute(
      """
      ALTER TABLE system.x_posts
      ADD CONSTRAINT x_posts_status_check
      CHECK (status IN ('pending','approved','posted','failed','rejected','cancelled'))
      """,
      "ALTER TABLE system.x_posts DROP CONSTRAINT IF EXISTS x_posts_status_check"
    )

    execute(
      """
      ALTER TABLE system.x_posts
      ADD CONSTRAINT x_posts_post_type_check
      CHECK (post_type IN ('top_hits','injury','team_magazine','scorecard','reply'))
      """,
      "ALTER TABLE system.x_posts DROP CONSTRAINT IF EXISTS x_posts_post_type_check"
    )
  end
end
