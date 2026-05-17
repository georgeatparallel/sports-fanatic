defmodule SportsFanaticWeb.LineupController do
  use SportsFanaticWeb, :controller

  import Ecto.Query
  alias SportsFanatic.Mlb.{Lineup, Player, ScheduledGame, Team}
  alias SportsFanatic.Repo

  def show(conn, %{"date" => date_str}) do
    date = Date.from_iso8601!(date_str)

    games =
      ScheduledGame
      |> where([sg], sg.game_date == ^date)
      |> order_by([sg], sg.game_datetime)
      |> Repo.all()

    lineups =
      Lineup
      |> where([l], l.game_date == ^date)
      |> order_by([l], asc: l.team_code, asc: l.batting_order)
      |> Repo.all()
      |> Repo.preload(player: :team)

    # Batch resolve teams by MLB ID from scheduled games
    mlb_ids =
      games
      |> Enum.flat_map(fn g -> [g.away_mlb_id, g.home_mlb_id] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    teams_by_mlb_id =
      if mlb_ids != [] do
        Team
        |> where([t], fragment("(? ->> 'mlb_id')::int = ANY(?)", t.external_ids, ^mlb_ids))
        |> Repo.all()
        |> Map.new(fn t ->
          mlb_id = t.external_ids["mlb_id"]
          {to_integer(mlb_id), t}
        end)
      else
        %{}
      end

    # Group lineups by team_code for lookup via team abbreviation
    lineups_by_team_code = Enum.group_by(lineups, & &1.team_code)

    # Resolve probable pitchers to player records for linking
    pitcher_names =
      games
      |> Enum.flat_map(fn g -> [g.away_probable_pitcher, g.home_probable_pitcher] end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    pitchers_by_name =
      if pitcher_names != [] do
        Player
        |> where([p], p.full_name in ^pitcher_names)
        |> preload(:team)
        |> Repo.all()
        |> Map.new(fn p -> {p.full_name, p} end)
      else
        %{}
      end

    canonical = SportsFanaticWeb.SEO.absolute_url("/mlb/lineups/#{date_str}")
    site_url = SportsFanaticWeb.SEO.site_url()
    today_iso = SportsFanatic.DateHelper.today() |> Date.to_iso8601()

    # Build breadcrumb JSON-LD
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
            "name" => "Lineups",
            "item" => site_url <> "/mlb/lineups/#{today_iso}"
          },
          %{
            "@type" => "ListItem",
            "position" => 4,
            "name" => format_date(date)
          }
        ]
      })

    prev_date = nearest_lineup_date_before(date)
    next_date = nearest_lineup_date_after(date)

    conn
    |> assign(:page_title, "MLB Lineups for #{format_date(date)} | Sports Fan Agent")
    |> assign(
      :meta_description,
      "Confirmed MLB lineups for #{format_date(date)}. Starting lineups, batting orders, and probable pitchers for all games."
    )
    |> assign(:canonical_url, canonical)
    |> assign(:json_ld, json_ld)
    |> render(:show,
      date: date,
      date_str: date_str,
      games: games,
      teams_by_mlb_id: teams_by_mlb_id,
      lineups_by_team_code: lineups_by_team_code,
      pitchers_by_name: pitchers_by_name,
      prev_date: prev_date,
      next_date: next_date
    )
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

  defp format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  defp to_integer(val) when is_integer(val), do: val
  defp to_integer(val) when is_binary(val), do: String.to_integer(val)
  defp to_integer(_), do: nil
end
