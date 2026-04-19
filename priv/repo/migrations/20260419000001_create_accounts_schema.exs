defmodule SportsFanatic.Repo.Migrations.CreateAccountsSchema do
  use Ecto.Migration

  def up do
    execute "CREATE SCHEMA IF NOT EXISTS accounts"

    create table(:users, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :string, size: 320, null: false
      add :password_hash, :string, size: 200, null: false
      add :display_name, :string, size: 100
      add :confirmed_at, :utc_datetime
      add :confirmation_token, :string, size: 100
      add :reset_token, :string, size: 100
      add :reset_token_expires_at, :utc_datetime
      add :stripe_customer_id, :string, size: 100
      add :subscription_tier, :string, size: 20, null: false, default: "free"
      add :subscription_expires_at, :utc_datetime
      add :is_admin, :boolean, default: false
      add :last_sign_in_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email], prefix: "accounts")
    create unique_index(:users, [:stripe_customer_id], prefix: "accounts")

    create table(:subscriptions, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :binary_id, prefix: "accounts"), null: false
      add :stripe_subscription_id, :string, size: 100, null: false
      add :stripe_price_id, :string, size: 100, null: false
      add :plan, :string, size: 20, null: false
      add :status, :string, size: 30, null: false
      add :current_period_start, :utc_datetime, null: false
      add :current_period_end, :utc_datetime, null: false
      add :trial_end, :utc_datetime
      add :canceled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:stripe_subscription_id], prefix: "accounts")
    create index(:subscriptions, [:user_id], prefix: "accounts")
    create index(:subscriptions, [:status], prefix: "accounts")

    create table(:sessions, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :binary_id, prefix: "accounts"), null: false
      add :token, :string, size: 200, null: false
      add :ip_address, :string, size: 45
      add :user_agent, :text
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:sessions, [:token], prefix: "accounts")
    create index(:sessions, [:user_id], prefix: "accounts")
  end

  def down do
    drop table(:sessions, prefix: "accounts")
    drop table(:subscriptions, prefix: "accounts")
    drop table(:users, prefix: "accounts")
    execute "DROP SCHEMA IF EXISTS accounts CASCADE"
  end
end
