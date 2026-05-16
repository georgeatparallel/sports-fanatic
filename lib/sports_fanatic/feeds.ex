defmodule SportsFanatic.Feeds do
  @moduledoc """
  Context for user feed CRUD operations. All operations are user-scoped
  to enforce ownership.
  """

  import Ecto.Query

  alias SportsFanatic.Feeds.UserFeed
  alias SportsFanatic.Repo

  @max_feeds_per_user 10

  # ── CRUD ──────────────────────────────────────────────────────

  @doc """
  Creates a new feed for the given user. Enforces a maximum of
  #{@max_feeds_per_user} feeds per user.
  """
  def create_feed(user_id, name, attrs \\ %{}) when is_binary(user_id) do
    if count_user_feeds(user_id) >= @max_feeds_per_user do
      {:error, :max_feeds_reached}
    else
      next_order = next_display_order(user_id)

      %UserFeed{}
      |> UserFeed.changeset(
        Map.merge(attrs, %{
          user_id: user_id,
          name: name,
          display_order: next_order
        })
      )
      |> Repo.insert()
    end
  end

  @doc """
  Lists all feeds for a user, ordered by display_order ascending.
  """
  def list_feeds(user_id) when is_binary(user_id) do
    from(f in UserFeed,
      where: f.user_id == ^user_id,
      order_by: [asc: f.display_order, asc: f.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single feed by ID, scoped to the given user. Raises if not found.
  """
  def get_feed!(feed_id, user_id) when is_binary(feed_id) and is_binary(user_id) do
    from(f in UserFeed, where: f.id == ^feed_id and f.user_id == ^user_id)
    |> Repo.one!()
  end

  @doc """
  Gets the first active feed for a user (by display_order).
  Returns nil if no active feeds exist.
  """
  def get_active_feed(user_id) when is_binary(user_id) do
    from(f in UserFeed,
      where: f.user_id == ^user_id and f.is_active == true,
      order_by: [asc: f.display_order],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Updates a feed. Validates user ownership.
  """
  def update_feed(%UserFeed{} = feed, user_id, attrs)
      when is_binary(user_id) do
    if feed.user_id != user_id do
      {:error, :unauthorized}
    else
      feed
      |> UserFeed.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Updates a feed without ownership check (for worker use).
  """
  def update_feed(%UserFeed{} = feed, attrs) do
    feed
    |> UserFeed.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a feed by ID, scoped to the given user.
  """
  def delete_feed(feed_id, user_id) when is_binary(feed_id) and is_binary(user_id) do
    feed = get_feed!(feed_id, user_id)
    Repo.delete(feed)
  end

  @doc """
  Reorders feeds for a user. `feed_ids_in_order` is a list of feed UUIDs
  in the desired display order.
  """
  def reorder_feeds(user_id, feed_ids_in_order)
      when is_binary(user_id) and is_list(feed_ids_in_order) do
    Repo.transaction(fn ->
      feed_ids_in_order
      |> Enum.with_index()
      |> Enum.each(fn {feed_id, index} ->
        from(f in UserFeed,
          where: f.id == ^feed_id and f.user_id == ^user_id
        )
        |> Repo.update_all(set: [display_order: index])
      end)
    end)
  end

  # ── Queries ──────────────────────────────────────────────────

  @doc """
  Counts the number of feeds for a user.
  """
  def count_user_feeds(user_id) when is_binary(user_id) do
    from(f in UserFeed, where: f.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Filters a list of feed articles (maps) by whether their player_ids
  or team_ids overlap with the feed's player_ids/team_ids.
  Returns `{matching, non_matching}`.
  """
  def partition_articles_by_feed(nil, articles), do: {[], articles}

  def partition_articles_by_feed(%UserFeed{} = feed, articles) when is_list(articles) do
    player_set = MapSet.new(feed.player_ids)
    team_set = MapSet.new(feed.team_ids)

    if MapSet.size(player_set) == 0 and MapSet.size(team_set) == 0 do
      {[], articles}
    else
      Enum.split_with(articles, fn item ->
        # Extract player IDs from either "player_ids" (raw) or "players" (enriched feed format)
        item_player_ids =
          case item["players"] do
            players when is_list(players) and players != [] ->
              Enum.map(players, fn p -> p["id"] end) |> Enum.reject(&is_nil/1)
            _ ->
              (item["player_ids"] || []) |> List.wrap()
          end

        # Primary match: player overlap
        player_match = Enum.any?(item_player_ids, &MapSet.member?(player_set, &1))

        # Only match on teams if the feed has NO players (team-only feed)
        team_match =
          if MapSet.size(player_set) == 0 do
            item_team_ids =
              case item["teams"] do
                teams when is_list(teams) and teams != [] ->
                  Enum.map(teams, fn t -> t["id"] end) |> Enum.reject(&is_nil/1)
                _ ->
                  (item["team_ids"] || []) |> List.wrap()
              end

            Enum.any?(item_team_ids, &MapSet.member?(team_set, &1))
          else
            false
          end

        player_match or team_match
      end)
    end
  end

  @doc """
  Lists all active feeds across all users (for the research worker).
  """
  def list_all_active_feeds do
    from(f in UserFeed, where: f.is_active == true)
    |> Repo.all()
  end

  @doc """
  Lists all feeds across all users with user preloaded (for admin view).
  """
  def list_all_feeds(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(f in UserFeed,
      join: u in assoc(f, :user),
      preload: [user: u],
      order_by: [desc: f.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Gets specific feeds by IDs.
  """
  def get_feeds(feed_ids) when is_list(feed_ids) do
    from(f in UserFeed, where: f.id in ^feed_ids)
    |> Repo.all()
  end

  @doc """
  Returns feed research stats for admin display.
  """
  def feed_research_stats do
    today = DateTime.utc_now() |> DateTime.to_date()

    total = Repo.aggregate(from(f in UserFeed), :count)

    researched_today =
      from(f in UserFeed,
        where: fragment("?::date = ?", f.last_researched_at, ^today)
      )
      |> Repo.aggregate(:count)

    total_players =
      from(f in UserFeed,
        select: fragment("array_length(player_ids, 1)")
      )
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.sum()

    %{
      total_feeds: total,
      researched_today: researched_today,
      pending_today: total - researched_today,
      total_players: total_players
    }
  end

  # ── Private ──────────────────────────────────────────────────

  defp next_display_order(user_id) do
    from(f in UserFeed,
      where: f.user_id == ^user_id,
      select: max(f.display_order)
    )
    |> Repo.one()
    |> case do
      nil -> 0
      max -> max + 1
    end
  end
end
