defmodule SportsFanatic.Repo.Migrations.CreateXCredentials do
  use Ecto.Migration

  def change do
    create table(:x_credentials, prefix: "accounts", primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :account_handle, :string, size: 50, null: false
      # X numeric user id
      add :account_id, :string, size: 50, null: false
      add :access_token_ciphertext, :binary, null: false
      add :refresh_token_ciphertext, :binary, null: false
      add :access_token_iv, :binary, null: false
      add :refresh_token_iv, :binary, null: false
      add :expires_at, :utc_datetime, null: false
      add :scope, :string, size: 500, null: false
      # Single-row pattern enforced by UNIQUE(singleton)
      add :singleton, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:x_credentials, [:singleton],
             prefix: "accounts",
             name: :x_credentials_singleton_idx
           )

    create unique_index(:x_credentials, [:account_handle], prefix: "accounts")
  end
end
