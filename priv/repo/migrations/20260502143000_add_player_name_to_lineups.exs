defmodule SportsFanatic.Repo.Migrations.AddPlayerNameToLineups do
  use Ecto.Migration

  def change do
    alter table(:lineups, prefix: :mlb) do
      add :player_name, :string
    end
  end
end
