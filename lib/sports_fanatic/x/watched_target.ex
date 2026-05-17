defmodule SportsFanatic.X.WatchedTarget do
  @moduledoc """
  Ecto schema for `accounts.x_watched_targets`. Each row is an external X
  account we proactively poll for new tweets and may reply to (gated by
  the `x_agent_outbound_replies_enabled` feature flag).

  `handle` is stored without the leading '@'. Validation enforces
  `^[A-Za-z0-9_]{1,15}$` (X's username rules).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "accounts"

  @handle_regex ~r/^[A-Za-z0-9_]{1,15}$/

  schema "x_watched_targets" do
    field :handle, :string
    field :account_id, :string
    field :focus, :string
    field :enabled, :boolean, default: true
    field :last_polled_at, :utc_datetime
    field :last_reply_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @cast_fields [:handle, :account_id, :focus, :enabled, :last_polled_at, :last_reply_at]

  def changeset(target, attrs) do
    target
    |> cast(attrs, @cast_fields)
    |> validate_required([:handle])
    |> normalize_handle()
    |> validate_format(:handle, @handle_regex,
      message: "must match the X username rules (letters, digits, underscore; 1-15 chars)"
    )
    |> validate_length(:account_id, max: 50)
    |> unique_constraint(:handle)
  end

  defp normalize_handle(changeset) do
    case get_change(changeset, :handle) || get_field(changeset, :handle) do
      handle when is_binary(handle) ->
        put_change(changeset, :handle, String.replace_prefix(handle, "@", ""))

      _ ->
        changeset
    end
  end
end
