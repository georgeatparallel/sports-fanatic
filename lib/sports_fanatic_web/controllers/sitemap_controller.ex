defmodule SportsFanaticWeb.SitemapController do
  use SportsFanaticWeb, :controller

  alias SportsFanatic.Repo
  alias SportsFanatic.Content.Sitemap

  def index(conn, _params) do
    sitemap = Repo.get_by(Sitemap, sitemap_type: "index")

    if sitemap do
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, sitemap.xml_content)
    else
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, default_index_xml())
    end
  end

  def show(conn, %{"type" => type}) do
    sitemap = Repo.get_by(Sitemap, sitemap_type: type)

    if sitemap do
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, sitemap.xml_content)
    else
      conn
      |> put_resp_content_type("application/xml")
      |> send_resp(200, empty_sitemap_xml())
    end
  end

  def robots(conn, _params) do
    robots_txt = """
    User-agent: *
    Allow: /
    Allow: /mlb/
    Disallow: /premium/
    Disallow: /account/
    Disallow: /api/
    Disallow: /dev/
    Disallow: /admin

    Sitemap: https://sportsfanatic.com/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, robots_txt)
  end

  defp default_index_xml do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <sitemap><loc>https://sportsfanatic.com/sitemap-players.xml</loc></sitemap>
      <sitemap><loc>https://sportsfanatic.com/sitemap-teams.xml</loc></sitemap>
      <sitemap><loc>https://sportsfanatic.com/sitemap-lineups.xml</loc></sitemap>
      <sitemap><loc>https://sportsfanatic.com/sitemap-news.xml</loc></sitemap>
      <sitemap><loc>https://sportsfanatic.com/sitemap-scouting.xml</loc></sitemap>
      <sitemap><loc>https://sportsfanatic.com/sitemap-gameday.xml</loc></sitemap>
    </sitemapindex>
    """
  end

  defp empty_sitemap_xml do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    </urlset>
    """
  end
end
