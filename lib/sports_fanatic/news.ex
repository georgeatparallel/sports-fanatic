defmodule SportsFanatic.News do
  @moduledoc """
  News context for managing MLB news items with AI enrichment.

  Provides cache-first access to news feeds via Valkey, with
  PostgreSQL as the source of truth.
  """

  import Ecto.Query

  alias SportsFanatic.Cache
  alias SportsFanatic.Content.NewsItem
  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.Repo

  require Logger

  @news_feed_ttl 60

  @doc """
  Lists news items for a given date, ordered by most recent first.
  """
  def list_news_by_date(%Date{} = date) do
    NewsItem
    |> where([n], n.published_date == ^date)
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the most recent date that has news items, or today if none exist.
  """
  def latest_news_date do
    query =
      NewsItem
      |> select([n], max(n.published_date))

    Repo.one(query) || SportsFanatic.DateHelper.today()
  end

  @doc """
  Returns the nearest date before `date` that has news items, or nil.
  """
  def nearest_news_date_before(%Date{} = date) do
    NewsItem
    |> where([n], n.published_date < ^date)
    |> select([n], max(n.published_date))
    |> Repo.one()
  end

  @doc """
  Returns the nearest date after `date` that has news items, or nil.
  """
  def nearest_news_date_after(%Date{} = date) do
    NewsItem
    |> where([n], n.published_date > ^date)
    |> select([n], min(n.published_date))
    |> Repo.one()
  end

  @doc """
  Creates a news item. If a record with the same (source, external_id) already
  exists, the insert is silently skipped (on_conflict: :nothing). Callers should
  filter duplicates before calling this function to avoid wasted S3/AI work.

  Returns {:ok, news_item} or {:error, changeset}.
  """
  def create_news_item(attrs) do
    %NewsItem{}
    |> NewsItem.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source, :external_id],
      returning: true
    )
  end

  @doc """
  Checks if a news item with the given source and external_id already exists.
  """
  def exists?(source, external_id) do
    NewsItem
    |> where([n], n.source == ^source and n.external_id == ^external_id)
    |> Repo.exists?()
  end

  @doc """
  Returns a MapSet of external_ids that already exist in the database for the
  given source. Accepts a list of candidate external_ids and filters in the
  database, so only one query is issued regardless of list size.

  Returns `MapSet.t()` (empty MapSet when the input list is empty).
  """
  def existing_external_ids(_source, []), do: MapSet.new()

  def existing_external_ids(source, external_ids) when is_list(external_ids) do
    NewsItem
    |> where([n], n.source == ^source and n.external_id in ^external_ids)
    |> select([n], n.external_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Checks if a news item with the given source_url already exists.
  """
  def exists_by_source_url?(source_url) when is_binary(source_url) do
    NewsItem
    |> where([n], n.source_url == ^source_url)
    |> Repo.exists?()
  end

  def exists_by_source_url?(_), do: false

  @doc """
  Returns the cached news feed for a date. On cache miss, queries the
  database, resolves player/team entities, builds the response, and caches it.

  Returns {:ok, feed_data} where feed_data is a list of enriched news maps.
  """
  def get_cached_feed(%Date{} = date) do
    cache_key = Cache.news_feed_key(date)

    case Cache.get(cache_key) do
      {:ok, nil} ->
        feed = build_feed(date)
        encoded = Jason.encode!(feed)

        case Cache.set(cache_key, encoded, @news_feed_ttl) do
          :ok -> :ok
          {:error, reason} -> Logger.warning("Failed to cache news feed: #{inspect(reason)}")
        end

        {:ok, feed}

      {:ok, cached} ->
        {:ok, Jason.decode!(cached)}

      {:error, reason} ->
        Logger.warning("Cache read failed, falling back to DB: #{inspect(reason)}")
        {:ok, build_feed(date)}
    end
  end

  @doc """
  Invalidates the Valkey cache for a given date's news feed.
  """
  def invalidate_feed_cache(%Date{} = date) do
    Cache.del(Cache.news_feed_key(date))
  end

  # Builds the feed data by querying DB and resolving entity references.
  defp build_feed(date) do
    news_items = list_news_by_date(date)

    # Batch-load all referenced players and teams
    all_player_ids =
      news_items
      |> Enum.flat_map(&(&1.player_ids || []))
      |> Enum.uniq()

    all_team_ids =
      news_items
      |> Enum.flat_map(&(&1.team_ids || []))
      |> Enum.uniq()

    players_map = load_players_map(all_player_ids)
    teams_map = load_teams_map(all_team_ids)

    Enum.map(news_items, fn item ->
      resolved_players =
        (item.player_ids || [])
        |> Enum.map(&Map.get(players_map, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn p ->
          team = Map.get(teams_map, p.team_id)

          %{
            "id" => p.id,
            "full_name" => p.full_name,
            "slug" => p.slug,
            "team_slug" => if(team, do: team.slug, else: nil)
          }
        end)

      resolved_teams =
        (item.team_ids || [])
        |> Enum.map(&Map.get(teams_map, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn t ->
          %{
            "id" => t.id,
            "name" => t.name,
            "slug" => t.slug,
            "abbreviation" => t.abbreviation,
            "league" => t.league
          }
        end)

      %{
        "id" => item.id,
        "slug" => item.slug,
        "title" => item.title,
        "body" => item.body,
        "summary" => item.summary,
        "category" => item.category,
        "sentiment" => item.sentiment,
        "ai_summary" => item.ai_summary,
        "source" => item.source,
        "source_url" => item.source_url,
        "image_url" => item.image_url,
        "author" => item.author,
        "ai_processed" => item.ai_processed,
        "injury_area" => item.injury_area,
        "injury_grade" => item.injury_grade,
        "published_date" => Date.to_iso8601(item.published_date),
        "inserted_at" => DateTime.to_iso8601(item.inserted_at),
        "domain_tags" => item.domain_tags || [],
        "players" => resolved_players,
        "teams" => resolved_teams
      }
    end)
  end

  defp load_players_map([]), do: %{}

  defp load_players_map(player_ids) do
    Player
    |> where([p], p.id in ^player_ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp load_teams_map([]), do: %{}

  defp load_teams_map(team_ids) do
    Team
    |> where([t], t.id in ^team_ids)
    |> Repo.all()
    |> Map.new(&{&1.id, &1})
  end
end
