defmodule SportsFanatic.Content.Sitemap do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "content"

  schema "sitemaps" do
    field :sitemap_type, :string
    field :xml_content, :string
    field :page_count, :integer, default: 0
    field :generated_at, :utc_datetime
  end

  def changeset(sitemap, attrs) do
    sitemap
    |> cast(attrs, [:sitemap_type, :xml_content, :page_count, :generated_at])
    |> validate_required([:sitemap_type, :xml_content])
    |> unique_constraint(:sitemap_type)
  end
end
