defmodule SportsFanatic.Scouting.ScoutingRun do
  @moduledoc "Tracks a scouting pipeline execution run."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "system"

  @valid_statuses ~w(pending running completed failed cancelled)

  schema "scouting_runs" do
    field :status, :string, default: "pending"
    field :total_players, :integer, default: 0
    field :processed_players, :integer, default: 0
    field :config, :map, default: %{}
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :error, :string

    has_many :logs, SportsFanatic.Scouting.ScoutingRunLog

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :status,
      :total_players,
      :processed_players,
      :config,
      :started_at,
      :completed_at,
      :error
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
