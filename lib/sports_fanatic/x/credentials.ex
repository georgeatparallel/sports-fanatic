defmodule SportsFanatic.X.Credentials do
  @moduledoc """
  Ecto schema for the single-row `accounts.x_credentials` table.

  Stores OAuth 2.0 PKCE user-context tokens for the org X account encrypted
  via `SportsFanatic.X.TokenVault` (AES-256-GCM). Plaintext token virtual
  fields are present so callers can manipulate the decrypted values without
  re-querying.

  `@derive {Inspect, ...}` excludes both plaintext and ciphertext fields so
  tokens never leak through `inspect/1` or Phoenix error pages.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "accounts"

  @derive {Inspect,
           except: [
             :access_token,
             :refresh_token,
             :access_token_ciphertext,
             :refresh_token_ciphertext,
             :access_token_iv,
             :refresh_token_iv
           ]}
  schema "x_credentials" do
    field :account_handle, :string
    field :account_id, :string
    field :access_token_ciphertext, :binary
    field :refresh_token_ciphertext, :binary
    field :access_token_iv, :binary
    field :refresh_token_iv, :binary
    field :expires_at, :utc_datetime
    field :scope, :string
    field :singleton, :boolean, default: true

    # Virtual — populated after TokenVault.decrypt/2; never persisted.
    field :access_token, :string, virtual: true, redact: true
    field :refresh_token, :string, virtual: true, redact: true

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :account_handle,
    :account_id,
    :access_token_ciphertext,
    :refresh_token_ciphertext,
    :access_token_iv,
    :refresh_token_iv,
    :expires_at,
    :scope,
    :singleton
  ]

  @required_fields [
    :account_handle,
    :account_id,
    :access_token_ciphertext,
    :refresh_token_ciphertext,
    :access_token_iv,
    :refresh_token_iv,
    :expires_at,
    :scope
  ]

  def changeset(credentials, attrs) do
    credentials
    |> cast(attrs, @cast_fields)
    |> validate_required(@required_fields)
    |> validate_length(:account_handle, max: 50)
    |> validate_length(:account_id, max: 50)
    |> validate_length(:scope, max: 500)
    |> put_change(:singleton, true)
    |> unique_constraint(:singleton, name: :x_credentials_singleton_idx)
    |> unique_constraint(:account_handle)
  end
end
