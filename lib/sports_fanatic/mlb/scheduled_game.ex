defmodule SportsFanatic.Mlb.ScheduledGame do
  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "mlb"

  schema "scheduled_games" do
    field :game_id, :integer
    field :game_date, :date
    field :game_datetime, :utc_datetime
    field :away_mlb_id, :integer
    field :home_mlb_id, :integer
    field :away_name, :string
    field :home_name, :string
    field :away_probable_pitcher, :string
    field :home_probable_pitcher, :string
    field :venue_id, :integer
    field :venue_name, :string
    field :status, :string, default: "scheduled"

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :game_id,
      :game_date,
      :game_datetime,
      :away_mlb_id,
      :home_mlb_id,
      :away_name,
      :home_name,
      :away_probable_pitcher,
      :home_probable_pitcher,
      :venue_id,
      :venue_name,
      :status
    ])
    |> validate_required([:game_id, :game_date])
    |> unique_constraint(:game_id)
  end
end
