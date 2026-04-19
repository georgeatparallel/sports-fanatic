defmodule SportsFanatic.Mlb.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "mlb"

  schema "games" do
    field :game_id, :integer
    field :game_datetime, :utc_datetime
    field :game_date, :date
    field :status, :string
    field :away_mlb_id, :integer
    field :home_mlb_id, :integer
    field :away_name, :string
    field :home_name, :string
    field :away_score, :integer
    field :home_score, :integer
    field :away_starter_mlb_id, :integer
    field :home_starter_mlb_id, :integer
    field :venue_id, :integer
    field :venue_name, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :game_id, :game_datetime, :game_date, :status,
      :away_mlb_id, :home_mlb_id, :away_name, :home_name,
      :away_score, :home_score, :away_starter_mlb_id, :home_starter_mlb_id,
      :venue_id, :venue_name
    ])
    |> validate_required([:game_id])
    |> unique_constraint(:game_id)
  end
end
