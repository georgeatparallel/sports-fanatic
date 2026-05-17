defmodule SportsFanatic.Mlb.PitcherGameLog do
  @moduledoc "Per-game pitching log used by recent-form features."

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "mlb"
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "pitcher_game_logs" do
    field :pitcher_mlb_id, :integer
    field :game_id, :integer
    field :game_date, :date
    field :innings_pitched, :float
    field :hits_allowed, :integer
    field :hr_allowed, :integer
    field :bb_allowed, :integer
    field :strikeouts, :integer
    field :earned_runs, :integer
    field :pitches_thrown, :integer

    timestamps(type: :utc_datetime)
  end

  @castable ~w(
    pitcher_mlb_id game_id game_date innings_pitched hits_allowed hr_allowed
    bb_allowed strikeouts earned_runs pitches_thrown
  )a

  def changeset(log, attrs) do
    log
    |> cast(attrs, @castable)
    |> validate_required([:pitcher_mlb_id, :game_id])
    |> unique_constraint([:pitcher_mlb_id, :game_id],
      name: :pitcher_game_logs_pitcher_game_idx
    )
  end
end
