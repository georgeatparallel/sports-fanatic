defmodule SportsFanatic.Billing.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "accounts"

  schema "subscriptions" do
    field :stripe_subscription_id, :string
    field :stripe_price_id, :string
    field :plan, :string
    field :status, :string
    field :current_period_start, :utc_datetime
    field :current_period_end, :utc_datetime
    field :trial_end, :utc_datetime
    field :canceled_at, :utc_datetime

    belongs_to :user, SportsFanatic.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [
      :user_id, :stripe_subscription_id, :stripe_price_id, :plan,
      :status, :current_period_start, :current_period_end,
      :trial_end, :canceled_at
    ])
    |> validate_required([:user_id, :stripe_subscription_id, :stripe_price_id, :plan, :status, :current_period_start, :current_period_end])
    |> unique_constraint(:stripe_subscription_id)
  end
end
