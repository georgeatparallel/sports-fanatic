defmodule SportsFanaticWeb.PageControllerTest do
  use SportsFanaticWeb.ConnCase, async: true

  @base_url SportsFanaticWeb.Endpoint.url()

  test "GET / renders homepage with 200 status", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200)
  end

  describe "GET / — Open Graph and Twitter Card meta tags" do
    setup %{conn: conn} do
      {:ok, resp: html_response(get(conn, ~p"/"), 200)}
    end

    test "contains a <title> tag with the brand name", %{resp: resp} do
      assert resp =~ "<title>"
      assert resp =~ "Sports Fan Agent"
    end

    test "renders meta name=description", %{resp: resp} do
      assert resp =~ ~s(<meta name="description")
    end

    test "renders link rel=canonical pointing to the home page", %{resp: resp} do
      assert resp =~ ~s(rel="canonical")
      assert resp =~ ~s(href="#{@base_url}/")
    end

    test "renders og:type as website", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:type" content="website")
    end

    test "renders og:site_name as Sports Fan Agent", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:site_name" content="Sports Fan Agent")
    end

    test "renders og:title", %{resp: resp} do
      assert resp =~ ~s(property="og:title")
    end

    test "renders og:description", %{resp: resp} do
      assert resp =~ ~s(property="og:description")
    end

    test "renders og:url pointing to the home page", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:url" content="#{@base_url}/")
    end

    test "renders og:image pointing to the default OG image", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:image" content="#{@base_url}/images/og-default.png")
    end

    test "renders og:image:width as 1200", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:image:width" content="1200")
    end

    test "renders og:image:height as 630", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:image:height" content="630")
    end

    test "renders og:image:type as image/png", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:image:type" content="image/png")
    end

    test "renders og:image:alt", %{resp: resp} do
      assert resp =~ ~s(property="og:image:alt")
    end

    test "renders og:locale as en_US", %{resp: resp} do
      assert resp =~ ~s(<meta property="og:locale" content="en_US")
    end

    test "renders twitter:card as summary_large_image", %{resp: resp} do
      assert resp =~ ~s(<meta name="twitter:card" content="summary_large_image")
    end

    test "renders twitter:image pointing to the default OG image", %{resp: resp} do
      assert resp =~ ~s(<meta name="twitter:image" content="#{@base_url}/images/og-default.png")
    end

    test "does NOT render twitter:site (no Twitter account configured)", %{resp: resp} do
      refute resp =~ ~s(name="twitter:site")
    end

    test "renders meta name=theme-color as #2563eb", %{resp: resp} do
      assert resp =~ ~s(<meta name="theme-color" content="#2563eb")
    end

    test "renders a JSON-LD script block", %{resp: resp} do
      assert resp =~ ~s(type="application/ld+json")
    end

    test "JSON-LD contains an Organization type", %{resp: resp} do
      # Jason.encode! produces compact JSON so keys are quoted without spaces
      assert resp =~ ~s("@type":"Organization") or resp =~ ~s("@type": "Organization")
    end

    test "JSON-LD contains a WebSite type", %{resp: resp} do
      assert resp =~ ~s("@type":"WebSite") or resp =~ ~s("@type": "WebSite")
    end

    test "og:image URL is absolute (starts with http:// or https://)", %{resp: resp} do
      assert resp =~ ~s(property="og:image" content="http)
    end

    test "canonical URL is absolute", %{resp: resp} do
      assert resp =~ ~s(href="#{@base_url}/)
    end
  end
end
