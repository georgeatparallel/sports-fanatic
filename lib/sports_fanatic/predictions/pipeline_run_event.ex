defmodule SportsFanatic.Predictions.PipelineRunEvent do
  @moduledoc """
  Ecto schema for `system.pipeline_run_events`.

  Streaming progress event log written by
  `SportsFanatic.Predictions.Progress`. One row per step lifecycle event
  (`started`, `item`, `completed`, `failed`).

  The `payload` field is a sanitised jsonb map (no secrets, nil keys
  stripped) — see `Progress.sanitize_payload/1`.
  """

  use Ecto.Schema

  @schema_prefix "system"
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "pipeline_run_events" do
    field :pipeline_run_id, :binary_id
    field :step, :string
    field :kind, :string
    field :seq, :integer
    field :payload, :map, default: %{}
    field :inserted_at, :utc_datetime_usec
  end
end
