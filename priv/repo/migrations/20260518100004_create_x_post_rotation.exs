defmodule SportsFanatic.Repo.Migrations.CreateXPostRotation do
  use Ecto.Migration

  def change do
    create table(:x_post_rotation, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :run_date, :date, null: false
      # e.g. ["injury","top_hits","team_magazine"]
      add :post_order, {:array, :string}, null: false
      # %{"top_hits" => "2026-05-17T20:14:00Z", ...}
      add :scheduled_times, :map, null: false
      # which team got the magazine today
      add :selected_team_slug, :string, size: 100
      add :skipped_slots, :map, default: fragment("'[]'::jsonb")
      add :earliest_game_at, :utc_datetime

      add :inserted_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index(:x_post_rotation, [:run_date], prefix: "system")
  end
end
