defmodule SportsFanatic.Accounts.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "accounts"

  schema "sessions" do
    field :token, :string
    field :ip_address, :string
    field :user_agent, :string
    field :expires_at, :utc_datetime

    belongs_to :user, SportsFanatic.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :token, :ip_address, :user_agent, :expires_at])
    |> validate_required([:user_id, :token, :expires_at])
    |> unique_constraint(:token)
  end
end
