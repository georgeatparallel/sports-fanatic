defmodule SportsFanatic.Repo.Migrations.CreatePublicTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"", "SELECT 1"
    execute "CREATE EXTENSION IF NOT EXISTS \"pg_trgm\"", "SELECT 1"

    create table(:sports, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, size: 50, null: false
      add :code, :string, size: 10, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sports, [:code])

    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :sport_id, references(:sports, type: :binary_id)
      add :name, :string, size: 100, null: false
      add :abbreviation, :string, size: 10
      add :city, :string, size: 100
      add :slug, :string, size: 100
      add :division, :string, size: 50
      add :league, :string, size: 10
      add :logo_url, :string, size: 500
      add :primary_color, :string, size: 7
      add :secondary_color, :string, size: 7
      add :external_ids, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:teams, [:slug])
    create index(:teams, [:abbreviation])

    create table(:players, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :team_id, references(:teams, type: :binary_id)
      add :first_name, :string, size: 100
      add :last_name, :string, size: 100
      add :full_name, :string, size: 200, null: false
      add :slug, :string, size: 200
      add :position, :string, size: 20
      add :bats, :string, size: 5
      add :throws, :string, size: 5
      add :throw_hand, :string, size: 5
      add :height, :string, size: 10
      add :weight, :integer
      add :birth_date, :date
      add :headshot_url, :string, size: 500
      add :bio, :text
      add :status, :string, size: 20, default: "active"
      add :jersey_number, :integer
      add :external_ids, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:players, [:team_id])
    create index(:players, [:slug])
    create index(:players, [:status])

    create table(:venues, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, size: 200, null: false
      add :city, :string, size: 100
      add :state, :string, size: 50
      add :capacity, :integer
      add :surface, :string, size: 50
      add :roof_type, :string, size: 50
      add :latitude, :float
      add :longitude, :float
      add :external_id, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:venues, [:external_id])
  end
end
