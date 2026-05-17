defmodule SportsFanaticWeb.SEOTest do
  use ExUnit.Case, async: true

  alias SportsFanaticWeb.SEO

  # ---------------------------------------------------------------------------
  # site_url/0
  # ---------------------------------------------------------------------------

  describe "site_url/0" do
    test "returns a string beginning with http:// or https://" do
      url = SEO.site_url()
      assert is_binary(url)
      assert String.starts_with?(url, "http://") or String.starts_with?(url, "https://")
    end

    test "has no trailing slash" do
      url = SEO.site_url()
      refute String.ends_with?(url, "/")
    end

    test "is non-empty" do
      assert SEO.site_url() != ""
    end
  end

  # ---------------------------------------------------------------------------
  # Static string accessors
  # ---------------------------------------------------------------------------

  describe "default_title/0" do
    test "returns a non-empty string" do
      assert is_binary(SEO.default_title())
      assert String.length(SEO.default_title()) > 0
    end

    test "contains the brand name" do
      assert SEO.default_title() =~ "Sports Fan Agent"
    end
  end

  describe "default_description/0" do
    test "returns a non-empty string" do
      assert is_binary(SEO.default_description())
      assert String.length(SEO.default_description()) > 0
    end

    test "is 200 characters or fewer (safe for Twitter)" do
      assert String.length(SEO.default_description()) <= 200
    end
  end

  describe "title_suffix/0" do
    test "returns a non-empty string" do
      assert is_binary(SEO.title_suffix())
      assert String.length(SEO.title_suffix()) > 0
    end

    test "contains the brand name" do
      assert SEO.title_suffix() =~ "Sports Fan Agent"
    end
  end

  describe "default_og_image_path/0" do
    test "returns a non-empty string" do
      assert is_binary(SEO.default_og_image_path())
      assert String.length(SEO.default_og_image_path()) > 0
    end

    test "starts with a slash (relative path)" do
      assert String.starts_with?(SEO.default_og_image_path(), "/")
    end
  end

  describe "default_og_image_alt/0" do
    test "returns a non-empty string" do
      assert is_binary(SEO.default_og_image_alt())
      assert String.length(SEO.default_og_image_alt()) > 0
    end
  end

  describe "twitter_handle/0" do
    test "returns nil (no Twitter account yet)" do
      assert SEO.twitter_handle() == nil
    end
  end

  # ---------------------------------------------------------------------------
  # absolute_image_url/1
  # ---------------------------------------------------------------------------

  describe "absolute_image_url/1" do
    test "nil returns the default OG image absolute URL" do
      result = SEO.absolute_image_url(nil)
      assert result == SEO.site_url() <> "/images/og-default.png"
    end

    test "nil result starts with site_url" do
      assert String.starts_with?(SEO.absolute_image_url(nil), SEO.site_url())
    end

    test "https:// URL is passed through unchanged" do
      url = "https://cdn.example.com/image.png"
      assert SEO.absolute_image_url(url) == url
    end

    test "https:// URL with path is passed through unchanged" do
      url = "https://images.sportspro.com/players/judge-2026.jpg"
      assert SEO.absolute_image_url(url) == url
    end

    test "http:// URL falls back to the default OG image (mixed-content rejection)" do
      result = SEO.absolute_image_url("http://insecure.example.com/x.png")
      assert result == SEO.site_url() <> "/images/og-default.png"
    end

    test "http:// URL result is never the original insecure URL" do
      result = SEO.absolute_image_url("http://insecure.example.com/x.png")
      refute result == "http://insecure.example.com/x.png"
    end

    test "path starting with / gets site_url prepended" do
      result = SEO.absolute_image_url("/images/foo.png")
      assert result == SEO.site_url() <> "/images/foo.png"
    end

    test "path without leading slash gets site_url and / prepended" do
      result = SEO.absolute_image_url("images/foo.png")
      assert result == SEO.site_url() <> "/images/foo.png"
    end

    test "result for a relative path starts with http:// or https://" do
      result = SEO.absolute_image_url("/some/path.png")
      assert String.starts_with?(result, "http://") or String.starts_with?(result, "https://")
    end

    test "result is always a non-empty string" do
      assert is_binary(SEO.absolute_image_url(nil))
      assert is_binary(SEO.absolute_image_url("/path.png"))
      assert is_binary(SEO.absolute_image_url("https://cdn.example.com/a.png"))
    end
  end

  # ---------------------------------------------------------------------------
  # absolute_url/1
  # ---------------------------------------------------------------------------

  describe "absolute_url/1" do
    test "path with leading slash gets site_url prepended" do
      result = SEO.absolute_url("/path")
      assert result == SEO.site_url() <> "/path"
    end

    test "path without leading slash gets site_url and / prepended" do
      result = SEO.absolute_url("path")
      assert result == SEO.site_url() <> "/path"
    end

    test "both /path and path produce the same absolute URL" do
      assert SEO.absolute_url("/path") == SEO.absolute_url("path")
    end

    test "already-absolute https:// URL is passed through" do
      url = "https://www.example.com/foo"
      assert SEO.absolute_url(url) == url
    end

    test "already-absolute http:// URL is passed through" do
      url = "http://localhost:4000/foo"
      assert SEO.absolute_url(url) == url
    end

    test "result starts with http:// or https://" do
      result = SEO.absolute_url("/mlb/teams")
      assert String.starts_with?(result, "http://") or String.starts_with?(result, "https://")
    end

    test "deep path is built correctly" do
      result = SEO.absolute_url("/mlb/players/new-york-yankees/aaron-judge")
      assert result == SEO.site_url() <> "/mlb/players/new-york-yankees/aaron-judge"
    end
  end

  # ---------------------------------------------------------------------------
  # canonical_or_request_url/1
  # ---------------------------------------------------------------------------

  describe "canonical_or_request_url/1" do
    test "returns canonical_url when it is a binary" do
      result = SEO.canonical_or_request_url(%{canonical_url: "https://example.com/x"})
      assert result == "https://example.com/x"
    end

    test "prefers canonical_url over conn when both are present" do
      conn = %Plug.Conn{request_path: "/other"}
      result = SEO.canonical_or_request_url(%{canonical_url: "https://example.com/x", conn: conn})
      assert result == "https://example.com/x"
    end

    test "falls back to conn.request_path when no canonical_url" do
      conn = %Plug.Conn{request_path: "/foo"}
      result = SEO.canonical_or_request_url(%{conn: conn})
      assert result == SEO.site_url() <> "/foo"
    end

    test "falls back to site_url/0 <> '/' when assigns is empty map" do
      result = SEO.canonical_or_request_url(%{})
      assert result == SEO.site_url() <> "/"
    end

    test "falls back to site_url/0 <> '/' when non-map is passed" do
      result = SEO.canonical_or_request_url(nil)
      assert result == SEO.site_url() <> "/"
    end

    test "result always starts with http:// or https://" do
      for assigns <- [
            %{canonical_url: "https://example.com/x"},
            %{conn: %Plug.Conn{request_path: "/foo"}},
            %{}
          ] do
        result = SEO.canonical_or_request_url(assigns)
        assert String.starts_with?(result, "http://") or String.starts_with?(result, "https://")
      end
    end

    test "conn path /mlb/news/2026-05-17 produces correct absolute URL" do
      conn = %Plug.Conn{request_path: "/mlb/news/2026-05-17"}
      result = SEO.canonical_or_request_url(%{conn: conn})
      assert result == SEO.site_url() <> "/mlb/news/2026-05-17"
    end

    test "ignores :canonical (old name) — returns fallback, not the old assign" do
      # Confirms the rename from :canonical → :canonical_url is enforced
      result = SEO.canonical_or_request_url(%{canonical: "https://old.example.com/x"})
      # Should NOT return the old assign value; should use the fallback
      assert result == SEO.site_url() <> "/"
    end
  end
end
