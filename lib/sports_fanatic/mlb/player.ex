defmodule SportsFanatic.Mlb.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "players" do
    field :first_name, :string
    field :last_name, :string
    field :full_name, :string
    field :slug, :string
    field :position, :string
    field :bats, :string
    field :throws, :string
    field :throw_hand, :string
    field :height, :string
    field :weight, :integer
    field :birth_date, :date
    field :headshot_url, :string
    field :bio, :string
    field :status, :string, default: "active"
    field :jersey_number, :integer
    field :external_ids, :map, default: %{}

    belongs_to :team, SportsFanatic.Mlb.Team

    timestamps(type: :utc_datetime)
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [
      :first_name,
      :last_name,
      :full_name,
      :slug,
      :position,
      :bats,
      :throws,
      :throw_hand,
      :height,
      :weight,
      :birth_date,
      :headshot_url,
      :bio,
      :status,
      :jersey_number,
      :external_ids,
      :team_id
    ])
    |> validate_required([:full_name])
    |> maybe_generate_slug()
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :full_name) || ""
        put_change(changeset, :slug, Slug.slugify(name))

      _ ->
        changeset
    end
  end
end
