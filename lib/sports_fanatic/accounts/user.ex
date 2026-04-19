defmodule SportsFanatic.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "accounts"

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :display_name, :string
    field :confirmed_at, :utc_datetime
    field :confirmation_token, :string
    field :reset_token, :string
    field :reset_token_expires_at, :utc_datetime
    field :stripe_customer_id, :string
    field :subscription_tier, :string, default: "free"
    field :subscription_expires_at, :utc_datetime
    field :is_admin, :boolean, default: false
    field :last_sign_in_at, :utc_datetime

    has_many :subscriptions, SportsFanatic.Billing.Subscription
    has_many :sessions, SportsFanatic.Accounts.Session

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :display_name])
    |> validate_required([:email, :password])
    |> validate_email()
    |> validate_password()
    |> hash_password()
  end

  def login_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
  end

  def subscription_changeset(user, attrs) do
    user
    |> cast(attrs, [:stripe_customer_id, :subscription_tier, :subscription_expires_at])
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 320)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 72)
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
end
