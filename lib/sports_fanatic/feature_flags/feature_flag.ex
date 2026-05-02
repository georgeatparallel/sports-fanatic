defmodule SportsFanatic.FeatureFlags.FeatureFlag do
  @moduledoc """
  Ecto schema for feature flags stored in the `system.feature_flags` table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"

  schema "feature_flags" do
    field :key, :string
    field :enabled, :boolean, default: false
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a new feature flag."
  def create_changeset(flag, attrs) do
    flag
    |> cast(attrs, [:key, :enabled, :description])
    |> validate_required([:key])
    |> validate_length(:key, min: 1, max: 100)
    |> validate_format(:key, ~r/\A[a-z0-9_]+\z/,
      message: "must contain only lowercase letters, numbers, and underscores"
    )
    |> unique_constraint(:key, name: "feature_flags_key_index")
  end

  @doc "Changeset for updating an existing feature flag."
  def update_changeset(flag, attrs) do
    flag
    |> cast(attrs, [:enabled, :description])
  end
end
