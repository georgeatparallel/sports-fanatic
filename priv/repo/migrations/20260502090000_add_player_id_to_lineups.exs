defmodule SportsFanatic.Repo.Migrations.AddPlayerIdToLineups do
  use Ecto.Migration

  def change do
    alter table(:lineups, prefix: :mlb) do
      add :player_id,
          references(:players, type: :binary_id, prefix: :public, on_delete: :nilify_all)
    end

    create index(:lineups, [:player_id], prefix: :mlb)
  end
end
