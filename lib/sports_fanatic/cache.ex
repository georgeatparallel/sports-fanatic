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
    "sf:page:news:" => 300,
    "sf:page:scouting:" => 900,
    "sf:page:gameday:" => 600,
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
