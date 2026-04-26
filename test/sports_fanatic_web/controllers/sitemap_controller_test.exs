defmodule SportsFanaticWeb.SitemapControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  alias SportsFanatic.Content.Sitemap
  alias SportsFanatic.Repo

  describe "GET /sitemap.xml" do
    test "returns 200 with XML content type", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")
      assert response(conn, 200)
      assert response_content_type(conn, :xml)
    end

    test "returns sitemap XML with sitemapindex or urlset structure", %{conn: conn} do
      conn = get(conn, "/sitemap.xml")
      body = response(conn, 200)
      assert body =~ "<?xml"
    end

    test "returns custom XML when sitemap index exists in DB", %{conn: conn} do
      Repo.insert!(%Sitemap{
        sitemap_type: "index",
        xml_content:
          "<?xml version=\"1.0\"?><sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\"><sitemap><loc>https://sportsfanatic.com/sitemaps/players</loc></sitemap></sitemapindex>",
        page_count: 1
      })

      conn = get(conn, "/sitemap.xml")
      body = response(conn, 200)
      assert body =~ "sitemapindex"
      assert body =~ "sportsfanatic.com"
    end
  end

  describe "GET /sitemaps/:type" do
    test "returns 200 with XML for known type", %{conn: conn} do
      Repo.insert!(%Sitemap{
        sitemap_type: "players",
        xml_content:
          "<?xml version=\"1.0\"?><urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\"></urlset>",
        page_count: 0
      })

      conn = get(conn, "/sitemaps/players")
      assert response(conn, 200)
      assert response_content_type(conn, :xml)
    end

    test "returns empty sitemap XML for type with no DB record", %{conn: conn} do
      conn = get(conn, "/sitemaps/nonexistent-type")
      body = response(conn, 200)
      assert body =~ "<?xml"
      assert body =~ "urlset"
    end

    test "returns 200 for teams type", %{conn: conn} do
      conn = get(conn, "/sitemaps/teams")
      assert response(conn, 200)
    end

    test "returns 200 for news type", %{conn: conn} do
      conn = get(conn, "/sitemaps/news")
      assert response(conn, 200)
    end
  end

  describe "GET /robots.txt" do
    test "returns 200 with text/plain content type", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      assert response(conn, 200)
      assert response_content_type(conn, :text)
    end

    test "disallows /premium/ path", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)
      assert body =~ "Disallow: /premium/"
    end

    test "allows /mlb/ path", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)
      assert body =~ "Allow: /mlb/"
    end

    test "includes sitemap reference", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)
      assert body =~ "Sitemap:"
    end

    test "disallows /account/ and /api/ paths", %{conn: conn} do
      conn = get(conn, "/robots.txt")
      body = response(conn, 200)
      assert body =~ "Disallow: /account/"
      assert body =~ "Disallow: /api/"
    end
  end
end
