defmodule SportsFanatic.Repo.Migrations.CreateFeatureFlags do
  use Ecto.Migration

  def up do
    create table(:feature_flags, prefix: "system", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :key, :string, size: 100, null: false
      add :enabled, :boolean, null: false, default: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:feature_flags, [:key], prefix: "system")

    # Seed the initial subscriptions_enabled flag (disabled by default)
    execute """
    INSERT INTO system.feature_flags (id, key, enabled, description, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'subscriptions_enabled',
      false,
      'When enabled, subscription gating is active. Premium content requires a subscription, and subscribe CTAs are shown. When disabled, all premium content is accessible without a subscription.',
      now(),
      now()
    )
    """
  end

  def down do
    drop table(:feature_flags, prefix: "system")
  end
end
