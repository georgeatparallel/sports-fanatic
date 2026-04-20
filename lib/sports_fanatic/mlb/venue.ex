defmodule SportsFanatic.Mlb.Venue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "venues" do
    field :name, :string
    field :city, :string
    field :state, :string
    field :capacity, :integer
    field :surface, :string
    field :roof_type, :string
    field :latitude, :float
    field :longitude, :float
    field :external_id, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:name, :city, :state, :capacity, :surface, :roof_type, :latitude, :longitude, :external_id])
    |> validate_required([:name])
    |> unique_constraint(:external_id)
  end
end
