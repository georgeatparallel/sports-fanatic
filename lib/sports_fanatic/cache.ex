defmodule SportsFanatic.Cache do
  @moduledoc """
  Valkey (Redis-compatible) cache wrapper using Redix.

  Key namespace design:
    sf:page:{page_type}:{identifiers}  - Rendered HTML fragments
    sf:data:{entity}:{id}              - Serialized data
    sf:meta:{page_type}:{identifiers}  - SEO meta tag data
    sf:sitemap:{type}                  - Generated sitemap XML
  """

  @default_ttl 300

  # TTLs by key pattern (seconds)
  @ttls %{
    "sf:page:player:" => 300,
    "sf:page:team:" => 600,
    "sf:page:lineup:today" => 120,
    "sf:page:lineup:" => 86_400,
    "sf:page:players:" => 86_400,
    "sf:page:news:" => 300,
    "sf:page:scouting:" => 900,
    "sf:page:gameday:" => 600,
    "sf:data:players:roster" => 86_400,
    "sf:data:player:card:" => 21_600,
    "sf:data:game_card:" => 86_400,
    "sf:data:predictions:" => 300,
    "sf:data:news:feed:" => 60,
    "sf:sitemap:" => 21_600
  }

  def get(key) do
    case Redix.command(:redix, ["GET", key]) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  end

  def set(key, value, ttl \\ nil) do
    ttl = ttl || ttl_for_key(key)

    case Redix.command(:redix, ["SETEX", key, ttl, value]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def del(key) do
    case Redix.command(:redix, ["DEL", key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def del_pattern(pattern) do
    case Redix.command(:redix, ["KEYS", pattern]) do
      {:ok, []} ->
        :ok

      {:ok, keys} ->
        Redix.command(:redix, ["DEL" | keys])
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_or_set(key, ttl \\ nil, fun) do
    case get(key) do
      {:ok, nil} ->
        value = fun.()
        set(key, value, ttl)
        {:ok, value}

      {:ok, value} ->
        {:ok, value}

      {:error, _reason} ->
        # Cache failure: execute function directly
        {:ok, fun.()}
    end
  end

  # Key builders
  def player_page_key(team_slug, player_slug),
    do: "sf:page:player:#{team_slug}:#{player_slug}"

  def team_page_key(team_slug),
    do: "sf:page:team:#{team_slug}"

  def lineup_page_key(date_str),
    do: "sf:page:lineup:#{date_str}"

  @doc """
  Page-cache key for the rewritten /mlb/lineups/:date Players page.
  Accepts an ISO 8601 string or a `%Date{}`.
  """
  @spec players_page_key(Date.t() | String.t()) :: String.t()
  def players_page_key(%Date{} = date),
    do: "sf:page:players:#{Date.to_iso8601(date)}"

  def players_page_key(date_str) when is_binary(date_str),
    do: "sf:page:players:#{date_str}"

  @doc """
  Data-cache key for the slim roster used by the Players page search dropdown.
  Single canonical key — the roster does not vary by date.
  """
  @spec players_roster_key() :: String.t()
  def players_roster_key, do: "sf:data:players:roster"

  @doc """
  Data-cache key for the per-card render data (status, link target, headshot).
  `id_or_mlb_id` is the integer mlb_id from `player.external_ids["mlb_id"]`
  when present, falling back to the player's binary UUID.
  """
  @spec player_card_key(integer() | String.t()) :: String.t()
  def player_card_key(id_or_mlb_id),
    do: "sf:data:player:card:#{id_or_mlb_id}"

  @doc """
  Data-cache key for the per-player "today's scheduled game" card rendered on
  the public scouting and player pages. `player_id` is the player's binary
  UUID primary key (NOT a slug — slugs can change, UUIDs cannot). `date` is a
  `%Date{}` or ISO-8601 string.

  TTL is set at write time via `DateHelper.seconds_until_eastern_midnight/0`
  so entries expire when the ET day rolls over.
  """
  @spec game_card_key(String.t(), Date.t() | String.t()) :: String.t()
  def game_card_key(player_id, %Date{} = date),
    do: game_card_key(player_id, Date.to_iso8601(date))

  def game_card_key(player_id, date_iso) when is_binary(player_id) and is_binary(date_iso),
    do: "sf:data:game_card:player:#{player_id}:#{date_iso}"

  def news_page_key(date_str, slug \\ nil) do
    if slug, do: "sf:page:news:#{date_str}:#{slug}", else: "sf:page:news:#{date_str}"
  end

  def scouting_page_key(team_slug, player_slug),
    do: "sf:page:scouting:#{team_slug}:#{player_slug}"

  def gameday_page_key(date_str, slug),
    do: "sf:page:gameday:#{date_str}:#{slug}"

  def news_feed_key(%Date{} = date),
    do: "sf:data:news:feed:#{Date.to_iso8601(date)}"

  def news_feed_key(date_str) when is_binary(date_str),
    do: "sf:data:news:feed:#{date_str}"

  def sitemap_key(type),
    do: "sf:sitemap:#{type}"

  defp ttl_for_key(key) do
    @ttls
    |> Enum.find(fn {prefix, _ttl} -> String.starts_with?(key, prefix) end)
    |> case do
      {_, ttl} -> ttl
      nil -> @default_ttl
    end
  end
end
