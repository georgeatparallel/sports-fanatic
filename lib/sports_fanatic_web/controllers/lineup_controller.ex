defmodule SportsFanaticWeb.LineupController do
  use SportsFanaticWeb, :controller

  import Ecto.Query

  alias SportsFanatic.{Cache, DateHelper, Players, Repo}
  alias SportsFanatic.Mlb.ScheduledGame

  require Logger

  @doc """
  Renders the Players page at `/mlb/players/:date`.

  Response body is the three-group player roster (in lineup / active /
  inactive) plus a global search dropdown. The legacy URL
  `/mlb/lineups/:date` 301-redirects here via `RedirectController`, so
  external backlinks and bookmarks continue to resolve.

  Caching strategy (ADR-002):

    * **Anonymous visitors** — full rendered HTML document is read from
      Valkey on a hit (zero Postgres, zero render work) and captured into
      Valkey on a miss via `Plug.Conn.register_before_send/2`.
    * **Authenticated visitors** — bypass the page cache (the layout
      switches Sign In ↔ Dashboard per user), but still get the benefit of
      the per-card and roster data caches inside the `Players` context.

  Date param validation: invalid strings raise `Ecto.NoResultsError`
  (matching prior behaviour); they propagate to a 404 via Plug's default
  error handling.
  """
  def show(conn, %{"date" => date_str}) do
    date = parse_date(date_str)

    current_user = conn.assigns[:current_user]
    page_key = Cache.players_page_key(date)

    if is_nil(current_user) do
      case safe_cache_get(page_key) do
        {:ok, html} when is_binary(html) and byte_size(html) > 0 ->
          conn
          |> put_resp_content_type("text/html; charset=utf-8")
          |> put_resp_header("cache-control", "public, max-age=60")
          |> send_resp(200, html)

        _ ->
          render_and_cache(conn, date, date_str, page_key)
      end
    else
      render_without_cache(conn, date, date_str)
    end
  end

  # ── private ─────────────────────────────────────────────────

  defp render_and_cache(conn, date, date_str, page_key) do
    conn
    |> Plug.Conn.register_before_send(fn sent_conn ->
      maybe_cache_body(sent_conn, page_key)
    end)
    |> assign_seo(date, date_str)
    |> assign_players_data(date)
    |> put_resp_header("cache-control", "public, max-age=60")
    |> render(:show)
  end

  defp render_without_cache(conn, date, date_str) do
    conn
    |> assign_seo(date, date_str)
    |> assign_players_data(date)
    |> render(:show)
  end

  defp maybe_cache_body(%Plug.Conn{status: 200, resp_body: body} = conn, page_key)
       when is_binary(body) and byte_size(body) > 0 do
    ttl = DateHelper.seconds_until_eastern_midnight() |> max(600)
    _ = safe_cache_set(page_key, body, ttl)
    conn
  end

  defp maybe_cache_body(conn, _page_key), do: conn

  defp assign_players_data(conn, date) do
    %{groups: groups, cards: cards} = Players.groups_with_cards_for_date(date)
    roster = Players.roster_for_search()
    # SEC-ROSTER-1: escape: :html_safe emits < for `<` and \/ for `/`,
    # so a player full_name containing `</script>` cannot break out of the
    # `<script type="application/json">` tag in show.html.heex.
    roster_json = Jason.encode!(roster, escape: :html_safe)

    prev_date = nearest_lineup_date_before(date)
    next_date = nearest_lineup_date_after(date)

    conn
    |> assign(:date, date)
    |> assign(:date_str, Date.to_iso8601(date))
    |> assign(:groups, groups)
    |> assign(:cards, cards)
    |> assign(:roster_json, roster_json)
    |> assign(:roster_count, length(roster))
    |> assign(:prev_date, prev_date)
    |> assign(:next_date, next_date)
  end

  defp assign_seo(conn, date, date_str) do
    canonical = SportsFanaticWeb.SEO.absolute_url("/mlb/players/#{date_str}")
    site_url = SportsFanaticWeb.SEO.site_url()
    today_iso = DateHelper.today() |> Date.to_iso8601()

    json_ld =
      Jason.encode!(%{
        "@context" => "https://schema.org",
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          %{
            "@type" => "ListItem",
            "position" => 1,
            "name" => "Home",
            "item" => site_url <> "/"
          },
          %{
            "@type" => "ListItem",
            "position" => 2,
            "name" => "Baseball",
            "item" => site_url <> "/mlb/teams"
          },
          %{
            "@type" => "ListItem",
            "position" => 3,
            "name" => "Players",
            "item" => site_url <> "/mlb/players/#{today_iso}"
          },
          %{
            "@type" => "ListItem",
            "position" => 4,
            "name" => format_date(date)
          }
        ]
      })

    formatted = format_date(date)

    conn
    |> assign(:page_title, "MLB Players - #{formatted}")
    |> assign(
      :meta_description,
      "Every MLB player for #{formatted} — in the lineup, on the roster, or inactive. " <>
        "Photos, positions, scouting status, and quick search across all of MLB."
    )
    |> assign(:canonical_url, canonical)
    |> assign(:og_type, "website")
    |> assign(:json_ld, json_ld)
  end

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, %Date{} = date} -> date
      _ -> raise Ecto.NoResultsError, queryable: ScheduledGame
    end
  end

  defp nearest_lineup_date_before(date) do
    ScheduledGame
    |> where([sg], sg.game_date < ^date)
    |> select([sg], max(sg.game_date))
    |> Repo.one()
  end

  defp nearest_lineup_date_after(date) do
    ScheduledGame
    |> where([sg], sg.game_date > ^date)
    |> select([sg], min(sg.game_date))
    |> Repo.one()
  end

  defp format_date(date), do: Calendar.strftime(date, "%B %d, %Y")

  defp safe_cache_get(key) do
    Cache.get(key)
  rescue
    e ->
      Logger.warning("LineupController cache get failed: #{inspect(e)}")
      {:error, :exception}
  end

  defp safe_cache_set(key, value, ttl) do
    Cache.set(key, value, ttl)
  rescue
    e ->
      Logger.warning("LineupController cache set failed: #{inspect(e)}")
      :ok
  end
end
