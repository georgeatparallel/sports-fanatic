defmodule SportsFanatic.ChatBot.QueryClusterMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "accounts"

  schema "query_cluster_members" do
    field :raw_query, :string
    field :inserted_at, :utc_datetime

    belongs_to :cluster, SportsFanatic.ChatBot.QueryCluster, type: :binary_id
    belongs_to :message, SportsFanatic.ChatBot.ChatMessage, type: :binary_id
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:cluster_id, :message_id, :raw_query])
    |> validate_required([:cluster_id, :message_id, :raw_query])
    |> foreign_key_constraint(:cluster_id)
    |> foreign_key_constraint(:message_id)
    |> unique_constraint(:message_id)
  end
end
