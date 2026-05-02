defmodule SportsFanatic.Mlb.Lineup do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "mlb"

  schema "lineups" do
    field :game_date, :date
    field :player_nerds_id, :integer
    field :team_code, :string
    field :batting_order, :integer
    field :position, :string
    field :confirmed, :boolean, default: false

    belongs_to :player, SportsFanatic.Mlb.Player, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(lineup, attrs) do
    lineup
    |> cast(attrs, [
      :game_date,
      :player_nerds_id,
      :team_code,
      :batting_order,
      :position,
      :confirmed,
      :player_id
    ])
    |> validate_required([:game_date, :player_nerds_id])
    |> unique_constraint([:game_date, :player_nerds_id])
  end
end
