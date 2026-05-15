defmodule SportsFanatic.Repo.Migrations.CreateNewsAgentTables do
  use Ecto.Migration

  def change do
    # Agent settings table
    create table(:news_agent_settings, prefix: "accounts", primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all, prefix: "accounts"),
        null: false

      add :raw_prompt, :text, null: false
      add :parsed_criteria, :map
      add :status, :string, null: false, default: "pending"
      add :last_run_at, :utc_datetime
      add :last_result, :map
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:news_agent_settings, [:user_id], prefix: "accounts")
    create index(:news_agent_settings, [:status], prefix: "accounts")

    execute(
      """
      ALTER TABLE accounts.news_agent_settings
      ADD CONSTRAINT news_agent_settings_status_check
      CHECK (status IN ('pending', 'active', 'running', 'completed', 'failed', 'expired'))
      """,
      """
      ALTER TABLE accounts.news_agent_settings
      DROP CONSTRAINT IF EXISTS news_agent_settings_status_check
      """
    )

    # Agent results table
    create table(:news_agent_results, prefix: "accounts", primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all, prefix: "accounts"),
        null: false

      add :setting_id,
          references(:news_agent_settings,
            type: :uuid,
            on_delete: :delete_all,
            prefix: "accounts"
          ),
          null: false

      add :matched_news_item_ids, {:array, :uuid}, default: []
      add :exa_results, :map, default: fragment("'[]'::jsonb")
      add :explanation, :text
      add :run_date, :date, null: false

      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create index(:news_agent_results, [:user_id, :setting_id], prefix: "accounts")
    create index(:news_agent_results, [:run_date], prefix: "accounts")

    # Add domain_tags to news_items
    alter table(:news_items, prefix: "content") do
      add :domain_tags, {:array, :string}, default: []
    end

    create index(:news_items, [:domain_tags], prefix: "content", using: "GIN")
  end
end
