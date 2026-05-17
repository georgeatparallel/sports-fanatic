defmodule SportsFanatic.Repo.Migrations.CreateUserFeeds do
  use Ecto.Migration

  def change do
    create table(:user_feeds, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, size: 100, null: false
      add :player_ids, {:array, :binary_id}, null: false, default: []
      add :team_ids, {:array, :binary_id}, null: false, default: []
      add :display_order, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true
      add :last_researched_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:user_feeds, [:user_id], prefix: "accounts")
    create unique_index(:user_feeds, [:user_id, :name], prefix: "accounts")
  end
end
