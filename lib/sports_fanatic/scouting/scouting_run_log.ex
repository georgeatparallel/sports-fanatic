defmodule SportsFanatic.Scouting.ScoutingRunLog do
  @moduledoc "Per-player step log entry for a scouting pipeline run."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "system"

  @valid_steps ~w(research classify generate complete error)
  @valid_statuses ~w(started completed failed skipped)

  schema "scouting_run_logs" do
    field :step, :string
    field :status, :string
    field :message, :string
    field :metadata, :map, default: %{}

    belongs_to :scouting_run, SportsFanatic.Scouting.ScoutingRun
    belongs_to :player, SportsFanatic.Mlb.Player, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:scouting_run_id, :player_id, :step, :status, :message, :metadata])
    |> validate_required([:scouting_run_id, :player_id, :step, :status])
    |> validate_inclusion(:step, @valid_steps)
    |> validate_inclusion(:status, @valid_statuses)
  end
end
