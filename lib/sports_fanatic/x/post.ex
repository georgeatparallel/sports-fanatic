defmodule SportsFanatic.X.Post do
  @moduledoc """
  Ecto schema for `system.x_posts`. One row per tweet (main + reply share a
  row; reply tweet id is stored alongside the main tweet id).

  Status state machine: `pending → approved → posted` (happy path),
  `pending → rejected`, `pending|approved → cancelled`, any → `failed`.

  Costs are stored in `cost_mills` (tenths of a cent). See
  `SportsFanatic.X.SpendLedger`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "system"

  @post_types ~w(top_hits injury team_magazine scorecard reply)
  @statuses ~w(pending approved posted failed rejected cancelled)

  schema "x_posts" do
    field :post_type, :string
    field :status, :string, default: "pending"
    field :main_body, :string
    field :reply_body, :string
    field :link_url, :string
    field :main_tweet_id, :string
    field :reply_tweet_id, :string
    field :in_reply_to_tweet_id, :string
    field :scheduled_at, :utc_datetime
    field :posted_at, :utc_datetime
    field :engagement_metrics, :map, default: %{}
    field :cost_mills, :integer, default: 0
    field :context, :map, default: %{}
    field :error_message, :string

    timestamps(type: :utc_datetime)
  end

  @cast_fields [
    :post_type,
    :status,
    :main_body,
    :reply_body,
    :link_url,
    :main_tweet_id,
    :reply_tweet_id,
    :in_reply_to_tweet_id,
    :scheduled_at,
    :posted_at,
    :engagement_metrics,
    :cost_mills,
    :context,
    :error_message
  ]

  def changeset(post, attrs) do
    post
    |> cast(attrs, @cast_fields)
    |> validate_required([:post_type, :status, :scheduled_at])
    |> validate_inclusion(:post_type, @post_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:main_body, max: 1000)
    |> validate_length(:reply_body, max: 1000)
    |> validate_length(:link_url, max: 500)
  end

  def post_types, do: @post_types
  def statuses, do: @statuses
end
