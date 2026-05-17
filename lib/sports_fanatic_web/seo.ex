defmodule SportsFanaticWeb.SEO do
  @moduledoc """
  Site-wide SEO defaults and URL helpers for Open Graph, Twitter Cards, and
  canonical links.

  Reads the endpoint URL config so dev (`http://localhost:4000`) and prod
  (`https://www.sports-fan-agent.com` via `PHX_HOST`) both produce correct
  absolute URLs. This eliminates an entire class of "wrong domain in og:url"
  bugs that previously existed in the codebase (controllers used to hardcode
  `https://sportsfanatic.com` — the wrong production host).
  """

  alias SportsFanaticWeb.Endpoint

  @default_title "Sports Fan Agent — AI-Powered MLB Scouting, Predictions & Game Day Intel"
  @default_description "AI-powered MLB scouting reports, hit & HR predictions, real-time " <>
                         "Game Day Magazines, and a conversational research agent for every " <>
                         "player and matchup."
  @title_suffix " | Sports Fan Agent"
  @default_og_image_path "/images/og-default.png"
  @default_og_image_alt "Sports Fan Agent — AI-powered MLB scouting, predictions, and game-day intelligence"
  # No Twitter/X account yet — leave nil so the `twitter:site` tag is omitted.
  @twitter_handle nil

  @spec default_title() :: String.t()
  def default_title, do: @default_title

  @spec default_description() :: String.t()
  def default_description, do: @default_description

  @spec title_suffix() :: String.t()
  def title_suffix, do: @title_suffix

  @spec default_og_image_path() :: String.t()
  def default_og_image_path, do: @default_og_image_path

  @spec default_og_image_alt() :: String.t()
  def default_og_image_alt, do: @default_og_image_alt

  @spec twitter_handle() :: String.t() | nil
  def twitter_handle, do: @twitter_handle

  @doc """
  Returns the canonical site URL with no trailing slash (e.g.
  `https://www.sports-fan-agent.com` in prod, `http://localhost:4000` in dev).

  Reads from `Endpoint.url/0` which honors `PHX_HOST` in prod.
  """
  @spec site_url() :: String.t()
  def site_url, do: Endpoint.url()

  @doc """
  Converts a path or absolute URL into an absolute URL suitable for `og:image`.

  - Already-absolute `https://` URLs are returned unchanged (third-party CDN
    images are fine — they're rendered by the social unfurler, not our server,
    so there's no SSRF surface).
  - `http://` URLs are rejected to avoid mixed-content warnings; we fall back
    to the default OG image instead.
  - Paths starting with `/` get the site URL prepended.
  - `nil` returns the absolute URL of the default OG image.
  """
  @spec absolute_image_url(String.t() | nil) :: String.t()
  def absolute_image_url(nil), do: absolute_image_url(@default_og_image_path)
  def absolute_image_url("https://" <> _ = url), do: url
  # Reject http:// to avoid mixed-content warnings on https sites.
  def absolute_image_url("http://" <> _), do: absolute_image_url(@default_og_image_path)
  def absolute_image_url("/" <> _ = path), do: site_url() <> path
  def absolute_image_url(path) when is_binary(path), do: site_url() <> "/" <> path

  @doc """
  Builds an absolute URL from a path. Pass-through for already-absolute URLs.
  """
  @spec absolute_url(String.t()) :: String.t()
  def absolute_url("https://" <> _ = url), do: url
  def absolute_url("http://" <> _ = url), do: url
  def absolute_url("/" <> _ = path), do: site_url() <> path
  def absolute_url(path) when is_binary(path), do: site_url() <> "/" <> path

  @doc """
  Returns `assigns[:canonical_url]` when set; otherwise reconstructs an
  absolute URL from the current request path (for controllers / LiveViews
  that forgot to assign one). Falls back to `site_url/0 <> "/"` if no
  conn is in scope.
  """
  @spec canonical_or_request_url(map()) :: String.t()
  def canonical_or_request_url(assigns) when is_map(assigns) do
    cond do
      is_binary(assigns[:canonical_url]) ->
        assigns[:canonical_url]

      match?(%Plug.Conn{}, assigns[:conn]) ->
        site_url() <> assigns[:conn].request_path

      true ->
        site_url() <> "/"
    end
  end

  def canonical_or_request_url(_), do: site_url() <> "/"
end
