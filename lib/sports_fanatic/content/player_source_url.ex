defmodule SportsFanatic.Content.PlayerSourceUrl do
  @moduledoc "Tracks processed source URLs per player for deduplication."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @schema_prefix "content"

  @valid_source_types ~w(news analyst fantasy_betting)
  @valid_classifications ~w(
    performance_analysis injury_report trade_rumor prospect_evaluation
    fantasy_value betting_insight general_news
  )

  schema "player_source_urls" do
    field :url, :string
    field :source_type, :string
    field :classification, :string
    field :content_summary, :string
    field :key_facts, :map
    field :content_text, :string
    field :digest, :string
    field :processed_at, :utc_datetime

    belongs_to :player, SportsFanatic.Mlb.Player, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(source_url, attrs) do
    source_url
    |> cast(attrs, [
      :player_id,
      :url,
      :source_type,
      :classification,
      :content_summary,
      :key_facts,
      :content_text,
      :digest,
      :processed_at
    ])
    |> validate_required([:player_id, :url, :source_type])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> validate_inclusion(:classification, @valid_classifications ++ [nil])
    |> validate_url()
    |> unique_constraint([:player_id, :url])
  end

  defp validate_url(changeset) do
    validate_change(changeset, :url, fn :url, url ->
      uri = URI.parse(url)

      if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
        []
      else
        [url: "must be a valid HTTP(S) URL"]
      end
    end)
  end
end
