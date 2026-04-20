defmodule SportsFanatic.Workers.GenerateSitemapWorker do
  @moduledoc "Regenerates XML sitemaps every 6 hours."

  use Oban.Worker,
    queue: :system,
    max_attempts: 2,
    unique: [period: 3600]

  import Ecto.Query
  alias SportsFanatic.Repo
  alias SportsFanatic.Mlb.{Team, Player}
  alias SportsFanatic.Content.{Sitemap, ScoutingReport, GameDayMagazine, NewsItem}

  require Logger

  @base_url "https://sportsfanatic.com"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    generate_sitemap("players", &player_urls/0)
    generate_sitemap("teams", &team_urls/0)
    generate_sitemap("lineups", &lineup_urls/0)
    generate_sitemap("news", &news_urls/0)
    generate_sitemap("scouting", &scouting_urls/0)
    generate_sitemap("gameday", &gameday_urls/0)
    generate_index_sitemap()

    Logger.info("All sitemaps regenerated")
    :ok
  end

  defp generate_sitemap(type, url_fn) do
    urls = url_fn.()
    xml = build_sitemap_xml(urls)

    %Sitemap{}
    |> Sitemap.changeset(%{
      sitemap_type: type,
      xml_content: xml,
      page_count: length(urls),
      generated_at: DateTime.utc_now()
    })
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :sitemap_type)
  end

  defp generate_index_sitemap do
    types = ["players", "teams", "lineups", "news", "scouting", "gameday"]

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(types, "\n", fn type ->
      "  <sitemap><loc>#{@base_url}/sitemap-#{type}.xml</loc><lastmod>#{Date.utc_today()}</lastmod></sitemap>"
    end)}
    </sitemapindex>
    """

    %Sitemap{}
    |> Sitemap.changeset(%{
      sitemap_type: "index",
      xml_content: xml,
      page_count: length(types),
      generated_at: DateTime.utc_now()
    })
    |> Repo.insert(on_conflict: :replace_all, conflict_target: :sitemap_type)
  end

  defp player_urls do
    from(p in Player,
      join: t in Team,
      on: p.team_id == t.id,
      where: not is_nil(p.slug) and not is_nil(t.slug),
      select: {t.slug, p.slug, p.updated_at}
    )
    |> Repo.all()
    |> Enum.map(fn {team_slug, player_slug, updated} ->
      %{loc: "#{@base_url}/mlb/players/#{team_slug}/#{player_slug}", lastmod: updated, changefreq: "daily"}
    end)
  end

  defp team_urls do
    from(t in Team, where: not is_nil(t.slug), select: {t.slug, t.updated_at})
    |> Repo.all()
    |> Enum.map(fn {slug, updated} ->
      %{loc: "#{@base_url}/mlb/teams/#{slug}", lastmod: updated, changefreq: "daily"}
    end)
  end

  defp lineup_urls do
    today = Date.utc_today()
    start_date = Date.add(today, -30)

    Date.range(start_date, today)
    |> Enum.map(fn date ->
      %{loc: "#{@base_url}/mlb/lineups/#{date}", lastmod: date, changefreq: if(date == today, do: "daily", else: "weekly")}
    end)
  end

  defp news_urls do
    from(n in NewsItem,
      where: n.published_date >= ^Date.add(Date.utc_today(), -90),
      select: {n.published_date, n.slug},
      order_by: [desc: n.published_date]
    )
    |> Repo.all()
    |> Enum.map(fn {date, slug} ->
      %{loc: "#{@base_url}/mlb/news/#{date}/#{slug}", lastmod: date, changefreq: "daily"}
    end)
  end

  defp scouting_urls do
    from(sr in ScoutingReport,
      join: p in Player,
      on: sr.player_id == p.id,
      join: t in Team,
      on: p.team_id == t.id,
      where: not is_nil(t.slug) and not is_nil(p.slug),
      select: {t.slug, p.slug, sr.updated_at},
      distinct: [p.id]
    )
    |> Repo.all()
    |> Enum.map(fn {team_slug, player_slug, updated} ->
      %{loc: "#{@base_url}/mlb/scouting/#{team_slug}/#{player_slug}", lastmod: updated, changefreq: "weekly"}
    end)
  end

  defp gameday_urls do
    from(m in GameDayMagazine,
      where: m.game_date >= ^Date.add(Date.utc_today(), -30),
      select: {m.game_date, m.slug},
      order_by: [desc: m.game_date]
    )
    |> Repo.all()
    |> Enum.map(fn {date, slug} ->
      %{loc: "#{@base_url}/mlb/game-day/#{date}/#{slug}", lastmod: date, changefreq: "daily"}
    end)
  end

  defp build_sitemap_xml(urls) do
    entries =
      Enum.map_join(urls, "\n", fn url ->
        lastmod = format_date(url.lastmod)

        """
          <url>
            <loc>#{url.loc}</loc>
            <lastmod>#{lastmod}</lastmod>
            <changefreq>#{url.changefreq}</changefreq>
          </url>
        """
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{entries}
    </urlset>
    """
  end

  defp format_date(%DateTime{} = dt), do: DateTime.to_date(dt) |> Date.to_iso8601()
  defp format_date(%Date{} = d), do: Date.to_iso8601(d)
  defp format_date(_), do: Date.utc_today() |> Date.to_iso8601()
end
