defmodule SportsFanatic.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    # Chat sessions
    create table(:chat_sessions, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all, prefix: "accounts"),
          null: false

      add :status, :string, size: 20, null: false, default: "active"
      add :last_activity_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:chat_sessions, [:user_id], prefix: "accounts")
    create index(:chat_sessions, [:last_activity_at], prefix: "accounts")

    execute(
      "ALTER TABLE accounts.chat_sessions ADD CONSTRAINT chat_sessions_status_check CHECK (status IN ('active', 'expired'))",
      "ALTER TABLE accounts.chat_sessions DROP CONSTRAINT chat_sessions_status_check"
    )

    # Chat messages
    create table(:chat_messages, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :session_id,
          references(:chat_sessions, type: :binary_id, on_delete: :delete_all, prefix: "accounts"),
          null: false

      add :role, :string, size: 20, null: false
      add :content, :text, null: false
      add :metadata, :map, default: %{}
      add :news_item_ids, {:array, :binary_id}, default: []
      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:chat_messages, [:session_id], prefix: "accounts")
    create index(:chat_messages, [:inserted_at], prefix: "accounts")

    execute(
      "ALTER TABLE accounts.chat_messages ADD CONSTRAINT chat_messages_role_check CHECK (role IN ('user', 'assistant', 'progress'))",
      "ALTER TABLE accounts.chat_messages DROP CONSTRAINT chat_messages_role_check"
    )

    # Query clusters
    create table(:query_clusters, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :representative_query, :text, null: false
      add :entity_player_ids, {:array, :binary_id}, default: []
      add :entity_team_ids, {:array, :binary_id}, default: []
      add :topics, {:array, :string}, default: []
      add :query_count, :integer, null: false, default: 1
      add :scheduled, :boolean, null: false, default: false
      add :schedule_frequency, :string, size: 20, null: false, default: "disabled"
      add :last_run_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:query_clusters, [:scheduled], prefix: "accounts", where: "scheduled = true")

    execute(
      "CREATE INDEX idx_query_clusters_entities ON accounts.query_clusters USING GIN (entity_player_ids)",
      "DROP INDEX accounts.idx_query_clusters_entities"
    )

    execute(
      "ALTER TABLE accounts.query_clusters ADD CONSTRAINT query_clusters_frequency_check CHECK (schedule_frequency IN ('hourly', 'daily', 'disabled'))",
      "ALTER TABLE accounts.query_clusters DROP CONSTRAINT query_clusters_frequency_check"
    )

    # Query cluster members
    create table(:query_cluster_members, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :cluster_id,
          references(:query_clusters,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: "accounts"
          ),
          null: false

      add :message_id,
          references(:chat_messages, type: :binary_id, on_delete: :delete_all, prefix: "accounts"),
          null: false

      add :raw_query, :text, null: false
      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:query_cluster_members, [:cluster_id], prefix: "accounts")
    create unique_index(:query_cluster_members, [:message_id], prefix: "accounts")
  end
end
