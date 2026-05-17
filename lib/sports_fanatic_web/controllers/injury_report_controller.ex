defmodule SportsFanaticWeb.InjuryReportController do
  @moduledoc """
  Public injury report pages.

  * `:index` — table of players with injury news in the last 3 days; sorted
    by `[in_lineup_today desc, last_published desc]`.
  * `:show`  — per-player flattened classification trail. Slug regex is
    checked BEFORE any DB lookup. First request of the day triggers the
    Python Bridge generator; second request reads from DB (idempotent).
  * `:og_image` — serves a static placeholder PNG. Slug regex + storage
    sanitize.
  """

  use SportsFanaticWeb, :controller

  require Logger
  alias SportsFanatic.Storage
  alias SportsFanatic.X.InjuryReport

  @slug_regex ~r/^[a-z0-9-]{1,100}$/
  @og_fallback "priv/static/og/injury-default.png"

  def index(conn, _params) do
    rows = InjuryReport.list_for_today()

    conn
    |> assign(:page_title, "MLB Injury Report — Daily Status Updates | Sports Fanatic")
    |> assign(
      :meta_description,
      "Real-time MLB injury report. Players on the IL, day-to-day, and back in today's lineup, with sources and fantasy impact."
    )
    |> assign(:canonical_url, "https://sportsfanatic.com/mlb/injury-report")
    |> assign(:og_image, "https://sportsfanatic.com/og/injury-default.png")
    |> assign(:json_ld, Jason.encode!(index_json_ld(rows)))
    |> assign(:rows, rows)
    |> render(:index)
  end

  def show(conn, %{"player_slug" => slug}) when is_binary(slug) do
    if Regex.match?(@slug_regex, slug) do
      do_show(conn, slug)
    else
      conn
      |> put_status(404)
      |> put_view(SportsFanaticWeb.ErrorHTML)
      |> render("404.html")
    end
  end

  def og_image(conn, %{"player_slug" => slug}) when is_binary(slug) do
    if Regex.match?(@slug_regex, slug) do
      send_og_image(conn, slug)
    else
      conn
      |> put_status(404)
      |> halt()
    end
  end

  # ── private ─────────────────────────────────────────────────

  defp do_show(conn, slug) do
    case InjuryReport.generate_or_fetch(slug) do
      {:ok, %{report: report, player: player, team: team}} ->
        canonical = "https://sportsfanatic.com/mlb/injury-report/#{slug}"
        og = "https://sportsfanatic.com/mlb/injury-report/og/#{slug}"

        conn
        |> assign(:page_title, "#{player.full_name} Injury Status | Sports Fanatic")
        |> assign(:meta_description, String.slice(report.tldr || "", 0, 160))
        |> assign(:canonical_url, canonical)
        |> assign(:og_image, og)
        |> assign(:json_ld, Jason.encode!(detail_json_ld(report, player, team)))
        |> assign(:report, report)
        |> assign(:player, player)
        |> assign(:team, team)
        |> render(:show)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> put_view(SportsFanaticWeb.ErrorHTML)
        |> render("404.html")

      {:error, reason} ->
        Logger.warning("InjuryReportController.show: #{inspect(reason)}")

        conn
        |> put_status(503)
        |> put_view(SportsFanaticWeb.ErrorHTML)
        |> render("503.html")
    end
  end

  defp send_og_image(conn, slug) do
    sanitized = Storage.sanitize_key(slug)
    per_player = "priv/static/og/players/#{sanitized}.png"

    cond do
      File.exists?(per_player) ->
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> put_resp_content_type("image/png")
        |> send_file(200, per_player)

      File.exists?(@og_fallback) ->
        conn
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> put_resp_content_type("image/png")
        |> send_file(200, @og_fallback)

      true ->
        conn |> put_status(404) |> halt()
    end
  end

  defp index_json_ld(rows) do
    %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "name" => "MLB Injury Report — Daily Status Updates",
      "url" => "https://sportsfanatic.com/mlb/injury-report",
      "numberOfItems" => length(rows)
    }
  end

  defp detail_json_ld(report, player, team) do
    member_of =
      if team do
        %{"@type" => "SportsTeam", "name" => team.name || ""}
      else
        nil
      end

    health_condition = %{
      "@type" => "MedicalCondition",
      "name" => (report.tldr || "") |> String.slice(0, 120),
      "status" => report.current_status,
      "expectedProgressionDate" => report.expected_return || ""
    }

    base = %{
      "@context" => "https://schema.org",
      "@type" => "Person",
      "name" => player.full_name || "",
      "healthCondition" => health_condition
    }

    if member_of, do: Map.put(base, "memberOf", member_of), else: base
  end
end
