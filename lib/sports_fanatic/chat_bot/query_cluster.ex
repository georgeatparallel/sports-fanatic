defmodule SportsFanatic.ChatBot.QueryCluster do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "accounts"

  schema "query_clusters" do
    field :representative_query, :string
    field :entity_player_ids, {:array, :binary_id}, default: []
    field :entity_team_ids, {:array, :binary_id}, default: []
    field :topics, {:array, :string}, default: []
    field :query_count, :integer, default: 1
    field :scheduled, :boolean, default: false
    field :schedule_frequency, :string, default: "disabled"
    field :last_run_at, :utc_datetime

    has_many :members, SportsFanatic.ChatBot.QueryClusterMember, foreign_key: :cluster_id

    timestamps(type: :utc_datetime)
  end

  @valid_frequencies ~w(hourly daily disabled)

  def changeset(cluster, attrs) do
    cluster
    |> cast(attrs, [
      :representative_query,
      :entity_player_ids,
      :entity_team_ids,
      :topics,
      :query_count,
      :scheduled,
      :schedule_frequency,
      :last_run_at
    ])
    |> validate_required([:representative_query])
    |> validate_inclusion(:schedule_frequency, @valid_frequencies)
    |> validate_number(:query_count, greater_than_or_equal_to: 0)
  end
end
