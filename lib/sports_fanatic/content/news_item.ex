defmodule SportsFanatic.Content.NewsItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "content"

  schema "news_items" do
    field :source, :string
    field :external_id, :string
    field :slug, :string
    field :title, :string
    field :body, :string
    field :summary, :string
    field :published_date, :date
    field :published_at, :utc_datetime
    field :player_ids, {:array, :binary_id}
    field :team_ids, {:array, :binary_id}
    field :category, :string
    field :is_premium, :boolean, default: false
    field :image_url, :string

    # AI enrichment fields
    field :sentiment, :string
    field :ai_summary, :string
    field :s3_key, :string
    field :source_url, :string
    field :author, :string
    field :ai_processed, :boolean, default: false

    # Injury detail fields
    field :injury_area, :string
    field :injury_grade, :string

    # Domain tags for agent matching
    field :domain_tags, {:array, :string}, default: []

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @cast_fields [
    :source,
    :external_id,
    :slug,
    :title,
    :body,
    :summary,
    :published_date,
    :published_at,
    :player_ids,
    :team_ids,
    :category,
    :is_premium,
    :image_url,
    :sentiment,
    :ai_summary,
    :s3_key,
    :source_url,
    :author,
    :ai_processed,
    :injury_area,
    :injury_grade,
    :domain_tags
  ]

  @valid_sentiments ~w(positive neutral negative)
  @valid_categories ~w(
    injury_new injury_worsening injury_update injury_recovery injury_cleared
    injury_elbow injury_shoulder injury_oblique injury_back
    injury_knee injury_hamstring injury_other
    trade performance transaction hit_by_pitch news general
  )

  @valid_injury_grades ~w(
    day_to_day 10_day_il 15_day_il 60_day_il season_ending
    pending_imaging cleared rehab_assignment unknown
  )

  def changeset(news_item, attrs) do
    news_item
    |> cast(attrs, @cast_fields)
    |> validate_required([:source, :slug, :title, :body, :published_date])
    |> validate_inclusion(:sentiment, @valid_sentiments)
    |> validate_inclusion(:category, @valid_categories)
    |> validate_inclusion(:injury_grade, @valid_injury_grades)
    |> validate_length(:sentiment, max: 20)
    |> validate_length(:s3_key, max: 500)
    |> validate_length(:source_url, max: 1000)
    |> validate_length(:author, max: 200)
    |> validate_length(:injury_area, max: 50)
    |> unique_constraint([:source, :external_id])
  end
end
