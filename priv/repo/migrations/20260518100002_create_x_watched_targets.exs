defmodule SportsFanatic.Repo.Migrations.CreateXWatchedTargets do
  use Ecto.Migration

  def change do
    create table(:x_watched_targets, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :handle, :string, size: 50, null: false
      # X numeric id, resolved at insert
      add :account_id, :string, size: 50
      # free-text description of what this account posts about
      add :focus, :text
      add :enabled, :boolean, null: false, default: true
      add :last_polled_at, :utc_datetime
      add :last_reply_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:x_watched_targets, [:handle], prefix: "accounts")
    create index(:x_watched_targets, [:enabled, :last_polled_at], prefix: "accounts")
  end
end
