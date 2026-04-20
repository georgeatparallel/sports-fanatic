defmodule SportsFanatic.Mlb.Sport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sports" do
    field :name, :string
    field :code, :string

    has_many :teams, SportsFanatic.Mlb.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(sport, attrs) do
    sport
    |> cast(attrs, [:name, :code])
    |> validate_required([:name, :code])
    |> unique_constraint(:code)
  end
end
