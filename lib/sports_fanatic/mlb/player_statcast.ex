defmodule SportsFanatic.Mlb.PlayerStatcast do
  @moduledoc "Per-player Statcast aggregates for a season (exit velo, hard-hit, etc.)."

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "mlb"
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "player_statcast" do
    field :player_mlb_id, :integer
    field :season, :integer
    field :avg_exit_velocity, :float
    field :max_exit_velocity, :float
    field :barrel_pct, :float
    field :hard_hit_pct, :float
    field :avg_launch_angle, :float
    field :fb_pct, :float
    field :pulled_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @castable ~w(
    player_mlb_id season avg_exit_velocity max_exit_velocity barrel_pct
    hard_hit_pct avg_launch_angle fb_pct pulled_at
  )a

  def changeset(stat, attrs) do
    stat
    |> cast(attrs, @castable)
    |> validate_required([:player_mlb_id, :season])
    |> unique_constraint([:player_mlb_id, :season],
      name: :player_statcast_player_season_idx
    )
  end
end
