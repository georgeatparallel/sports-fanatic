defmodule SportsFanatic.Mlb.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "teams" do
    field :name, :string
    field :abbreviation, :string
    field :city, :string
    field :slug, :string
    field :division, :string
    field :league, :string
    field :logo_url, :string
    field :primary_color, :string
    field :secondary_color, :string
    field :external_ids, :map, default: %{}

    belongs_to :sport, SportsFanatic.Mlb.Sport
    has_many :players, SportsFanatic.Mlb.Player

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [
      :name, :abbreviation, :city, :slug, :division, :league,
      :logo_url, :primary_color, :secondary_color, :external_ids, :sport_id
    ])
    |> validate_required([:name])
    |> unique_constraint(:slug)
    |> maybe_generate_slug()
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        city = get_field(changeset, :city) || ""
        name = get_field(changeset, :name) || ""
        slug = Slug.slugify("#{city} #{name}")
        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end

defmodule Slug do
  @moduledoc "Simple slug generation utility."

  def slugify(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  def slugify(_), do: ""
end
