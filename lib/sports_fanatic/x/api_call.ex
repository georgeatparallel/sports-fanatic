defmodule SportsFanatic.X.ApiCall do
  @moduledoc """
  Ecto schema for `system.x_api_calls` — audit log of every X v2 API write.

  Every `SportsFanatic.X.post_tweet/2` call inserts one row in the same
  transaction as the related `system.x_posts` update. `cost_mills` is
  tenths of a cent (15 mills = $0.015 per text write, 200 mills = $0.20
  per URL-bearing write).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"
  @timestamps_opts [type: :utc_datetime, updated_at: false]

  schema "x_api_calls" do
    field :endpoint, :string
    field :method, :string
    field :http_status, :integer
    field :tweet_id, :string
    field :had_url, :boolean, default: false
    field :cost_mills, :integer, default: 0
    field :actor, :string
    field :error_message, :string
    field :duration_ms, :integer

    timestamps()
  end

  @cast_fields [
    :endpoint,
    :method,
    :http_status,
    :tweet_id,
    :had_url,
    :cost_mills,
    :actor,
    :error_message,
    :duration_ms
  ]

  def changeset(api_call, attrs) do
    api_call
    |> cast(attrs, @cast_fields)
    |> validate_required([:endpoint, :method, :actor])
    |> validate_length(:endpoint, max: 100)
    |> validate_length(:method, max: 10)
    |> validate_length(:actor, max: 100)
    |> validate_length(:tweet_id, max: 50)
    |> validate_number(:cost_mills, greater_than_or_equal_to: 0)
  end
end
