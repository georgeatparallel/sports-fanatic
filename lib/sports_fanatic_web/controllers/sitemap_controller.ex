defmodule SportsFanaticWeb.SitemapController do
  use SportsFanaticWeb, :controller

  import Ecto.Query

  alias SportsFanatic.Mlb.{Player, Team}
  alias SportsFanatic.Repo

  @domain "https://www.sports-fan-agent.com"

  def index(conn, _params) do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <sitemap><loc>#{@domain}/sitemaps/players</loc></sitemap>
      <sitemap><loc>#{@domain}/sitemaps/teams</loc></sitemap>
      <sitemap><loc>#{@domain}/sitemaps/pages</loc></sitemap>
    </sitemapindex>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  def show(conn, %{"type" => "players"}) do
    players =
      Player
      |> join(:inner, [p], t in Team, on: p.team_id == t.id)
      |> where([p, t], not is_nil(p.slug) and not is_nil(t.slug))
      |> select([p, t], {t.slug, p.slug})
      |> Repo.all()

    urls =
      Enum.map(players, fn {team_slug, player_slug} ->
        "  <url><loc>#{@domain}/mlb/players/#{team_slug}/#{player_slug}</loc><changefreq>daily</changefreq></url>"
      end)

    xml = wrap_urlset(urls)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  def show(conn, %{"type" => "teams"}) do
    teams =
      Team
      |> where([t], not is_nil(t.slug))
      |> select([t], t.slug)
      |> Repo.all()

    urls =
      Enum.map(teams, fn slug ->
        "  <url><loc>#{@domain}/mlb/teams/#{slug}</loc><changefreq>daily</changefreq></url>"
      end)

    xml = wrap_urlset(urls)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  def show(conn, %{"type" => "pages"}) do
    urls = [
      "  <url><loc>#{@domain}/</loc><changefreq>hourly</changefreq><priority>1.0</priority></url>",
      "  <url><loc>#{@domain}/mlb/teams</loc><changefreq>daily</changefreq><priority>0.9</priority></url>",
      "  <url><loc>#{@domain}/mlb/players</loc><changefreq>daily</changefreq><priority>0.9</priority></url>",
      "  <url><loc>#{@domain}/mlb/lineups</loc><changefreq>daily</changefreq><priority>0.9</priority></url>",
      "  <url><loc>#{@domain}/mlb/news</loc><changefreq>hourly</changefreq><priority>0.9</priority></url>"
    ]

    xml = wrap_urlset(urls)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, wrap_urlset([]))
  end

  def robots(conn, _params) do
    robots_txt = """
    User-agent: *
    Allow: /
    Allow: /mlb/
    Disallow: /premium/
    Disallow: /admin
    Disallow: /joshua

    Sitemap: #{@domain}/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, robots_txt)
  end

  defp wrap_urlset(urls) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.join(urls, "\n")}
    </urlset>
    """
  end
end
